#!/bin/bash

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

echo_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

echo_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Function to display usage
show_usage() {
    echo "Usage: $0"
    echo ""
    echo "This script creates an Azure Container Instance (ACI) to verify Azure MCP Postgres server connection."
    echo "It reads deployment information from 'deployment-info.json' created by 'deploy-azmcp-postgres-server.sh'"
    echo ""
    echo "Prerequisites:"
    echo "  - 'deployment-info.json' file must exist (created by running deploy-azmcp-postgres-server.sh)"
    echo "  - Azure CLI must be installed and logged in"
    echo ""
    exit 1
}

# Function to validate deployment info file
validate_deployment_info() {
    DEPLOYMENT_INFO_FILE="$SCRIPT_DIR/deployment-info.json"
    
    if [ ! -f "$DEPLOYMENT_INFO_FILE" ]; then
        echo_error "Deployment info file not found: $DEPLOYMENT_INFO_FILE"
        echo_error "Please run deploy-azmcp-postgres-server.sh first to create the deployment info file."
        exit 1
    fi
    
    echo_info "Found deployment info file: $DEPLOYMENT_INFO_FILE"
    
    if ! command -v jq &> /dev/null; then
        echo_error "jq is required but not installed. Please install jq to continue."
        echo_info "Install with: brew install jq"
        exit 1
    fi
    
    MCP_SERVER_URI=$(jq -r '.MCP_SERVER_URI // empty' "$DEPLOYMENT_INFO_FILE")
    ENTRA_APP_CLIENT_ID=$(jq -r '.ENTRA_APP_CLIENT_ID // empty' "$DEPLOYMENT_INFO_FILE")
    ENTRA_APP_ROLE_VALUE=$(jq -r '.ENTRA_APP_ROLE_VALUE // empty' "$DEPLOYMENT_INFO_FILE")
    ENTRA_APP_ROLE_ID_BY_VALUE=$(jq -r '.ENTRA_APP_ROLE_ID_BY_VALUE // empty' "$DEPLOYMENT_INFO_FILE")
    ENTRA_APP_SP_OBJECT_ID=$(jq -r '.ENTRA_APP_SP_OBJECT_ID // empty' "$DEPLOYMENT_INFO_FILE")
    RESOURCE_GROUP=$(jq -r '.RESOURCE_GROUP // empty' "$DEPLOYMENT_INFO_FILE")
    LOCATION=$(jq -r '.LOCATION // empty' "$DEPLOYMENT_INFO_FILE")
    
    local missing_fields=()
    [ -z "$MCP_SERVER_URI" ] && missing_fields+=("MCP_SERVER_URI")
    [ -z "$ENTRA_APP_CLIENT_ID" ] && missing_fields+=("ENTRA_APP_CLIENT_ID")
    [ -z "$ENTRA_APP_ROLE_VALUE" ] && missing_fields+=("ENTRA_APP_ROLE_VALUE")
    [ -z "$ENTRA_APP_ROLE_ID_BY_VALUE" ] && missing_fields+=("ENTRA_APP_ROLE_ID_BY_VALUE")
    [ -z "$ENTRA_APP_SP_OBJECT_ID" ] && missing_fields+=("ENTRA_APP_SP_OBJECT_ID")
    [ -z "$RESOURCE_GROUP" ] && missing_fields+=("RESOURCE_GROUP")
    [ -z "$LOCATION" ] && missing_fields+=("LOCATION")
    
    if [ ${#missing_fields[@]} -gt 0 ]; then
        echo_error "Missing required fields in deployment info file:"
        for field in "${missing_fields[@]}"; do
            echo_error "  - $field"
        done
        exit 1
    fi
    
    echo_info "Deployment info validation passed"
    echo_info "MCP Server URI: $MCP_SERVER_URI"
    echo_info "Resource Group: $RESOURCE_GROUP"
    echo_info "Location: $LOCATION"
    echo_info "Entra App Client ID: $ENTRA_APP_CLIENT_ID"
}

# Function to create ACI
create_aci() {
    echo_info "Creating/Starting Azure Container Instance for Azure MCP Postgres server verification..."
    
    # Register Microsoft.ContainerInstance provider
    echo_info "Registering Microsoft.ContainerInstance provider..."
    az provider register --namespace Microsoft.ContainerInstance >/dev/null 2>&1 || true

    ACI_NAME="aci-mcp-verify"
    IMG="mcr.microsoft.com/azure-cli"

    # Check if ACI already exists
    echo_info "Checking if ACI '$ACI_NAME' already exists..."
    EXISTING_ACI=$(az container show -g "$RESOURCE_GROUP" -n "$ACI_NAME" --query "name" -o tsv 2>/dev/null || echo "")
    
    if [ -n "$EXISTING_ACI" ] && [ "$EXISTING_ACI" != "null" ]; then
        echo_info "ACI '$ACI_NAME' already exists"
        
        # Check current state
        STATE=$(az container show -g "$RESOURCE_GROUP" -n "$ACI_NAME" --query "instanceView.state" -o tsv 2>/dev/null || echo "")
        echo_info "Current ACI state: $STATE"
        
        if [ "$STATE" = "Stopped" ] || [ "$STATE" = "Terminated" ] || [ "$STATE" = "Succeeded" ]; then
            echo_info "ACI is in '$STATE' state, starting it..."
            az container start -g "$RESOURCE_GROUP" -n "$ACI_NAME"
        elif [ "$STATE" = "Running" ]; then
            echo_info "ACI is already running"
        else
            echo_info "ACI is in state: $STATE, waiting for it to stabilize..."
        fi
    else
        echo_info "ACI does not exist, creating new ACI: $ACI_NAME"
        az container create -g "$RESOURCE_GROUP" -n "$ACI_NAME" \
          --image "$IMG" \
          --location "$LOCATION" \
          --os-type Linux \
          --cpu 1 --memory 1.5 \
          --assign-identity \
          --restart-policy Never \
          --command-line "sleep 1800" 
    fi

    # Wait for Running state
    echo_info "Waiting for ACI to reach Running state..."
    for i in {1..36}; do
      STATE=$(az container show -g "$RESOURCE_GROUP" -n "$ACI_NAME" --query "instanceView.state" -o tsv 2>/dev/null || true)
      echo_info "ACI state: ${STATE:-<transitioning>} (attempt $i/36)"
      [ "$STATE" = "Running" ] && break
      sleep 5
    done
    
    if [ "$STATE" != "Running" ]; then
        echo_error "ACI failed to reach Running state after 3 minutes"
        exit 1
    fi
    
    echo_info "ACI is now running"
}

# Function to assign app role to ACI identity
assign_app_role() {
    echo_info "Assigning app role to ACI system-assigned identity..."
    
    # Capture the system-assigned identity principal ID of the ACI
    CONTAINER_PRINCIPAL_ID=$(az container show -g "$RESOURCE_GROUP" -n "aci-mcp-verify" --query "identity.principalId" -o tsv)
    if [ -z "$CONTAINER_PRINCIPAL_ID" ] || [ "$CONTAINER_PRINCIPAL_ID" = "null" ]; then
        echo_error "Failed to get ACI system-assigned identity principal ID"
        exit 1
    fi
    
    echo_info "ACI System Identity Principal ID: $CONTAINER_PRINCIPAL_ID"
    
    # Check if app role assignment already exists
    EXISTING_ASSIGNMENT=$(az rest --method GET \
        --url "https://graph.microsoft.com/v1.0/servicePrincipals/$CONTAINER_PRINCIPAL_ID/appRoleAssignments" \
        --query "value[?resourceId=='$ENTRA_APP_SP_OBJECT_ID' && appRoleId=='$ENTRA_APP_ROLE_ID_BY_VALUE'].id | [0]" \
        -o tsv 2>/dev/null || echo "")
    
    if [ -n "$EXISTING_ASSIGNMENT" ] && [ "$EXISTING_ASSIGNMENT" != "null" ]; then
        echo_info "App role assignment already exists for this ACI identity"
    else
        echo_info "Assigning app role '$ENTRA_APP_ROLE_VALUE' to ACI identity..."
        
        # Assign the app role to the ACI system-assigned identity
        az rest --method POST \
          --url "https://graph.microsoft.com/v1.0/servicePrincipals/$CONTAINER_PRINCIPAL_ID/appRoleAssignments" \
          --body "{
            \"principalId\": \"$CONTAINER_PRINCIPAL_ID\",
            \"resourceId\": \"$ENTRA_APP_SP_OBJECT_ID\",
            \"appRoleId\": \"$ENTRA_APP_ROLE_ID_BY_VALUE\"
          }" >/dev/null
        
        if [ $? -eq 0 ]; then
            echo_info "Successfully assigned app role to ACI identity"
        else
            echo_error "Failed to assign app role to ACI identity"
            exit 1
        fi
    fi
}

# Function to show verification instructions
show_verification_instructions() {
    echo_info "ACI created and configured successfully!"
    echo ""
    echo_info "To verify the MCP server connection, you can:"
    echo ""
    echo "1. Connect to the ACI container:"
    echo "   az container exec --resource-group \"$RESOURCE_GROUP\" --name \"aci-mcp-verify\" --exec-command \"/bin/sh\""
    echo ""
    echo "2. Inside the container, get an access token for the MCP server:"
    echo "   TOKEN_RESPONSE=\$(curl -s \"http://169.254.169.254/metadata/identity/oauth2/token?api-version=2018-02-01&resource=$ENTRA_APP_CLIENT_ID\" -H \"Metadata: true\")"
    echo "   ACCESS_TOKEN=\$(echo \"\$TOKEN_RESPONSE\" | jq -r .access_token)"
    echo ""
    echo "3. Test the MCP server endpoints:"
    echo "   # List available tools"
    echo "   curl -X POST \"$MCP_SERVER_URI\" \\"
    echo "     -H \"Content-Type: application/json\" \\"
    echo "     -H \"Authorization: Bearer \$ACCESS_TOKEN\" \\"
    echo "     -d '{\"jsonrpc\": \"2.0\", \"id\": \"test\", \"method\": \"tools/list\", \"params\": {}}'"
    echo ""
    echo "4. Access token for mcp-client.html:"
    echo "   # ACCESS_TOKEN"
    echo "   echo \$ACCESS_TOKEN"
    echo ""
    echo "5. Clean up the ACI when done:"
    echo "   az container delete --resource-group \"$RESOURCE_GROUP\" --name \"aci-mcp-verify\" --yes"
    echo ""
}

# Check command line arguments
if [ "$1" = "-h" ] || [ "$1" = "--help" ]; then
    show_usage
fi

# Main execution
main() {
    echo_info "Starting ACI MCP client deployment..."
    
    validate_deployment_info
    create_aci
    assign_app_role
    show_verification_instructions
    
    echo_info "ACI MCP client deployment completed successfully!"
}

# Run main function
main "$@"