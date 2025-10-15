#!/bin/bash

set -e

# Configuration
RESOURCE_GROUP="SSS3PT_anuchan-mcp15ccd188" # Placeholder resource group, will be overridden by required --resource-group cmd arg.
LOCATION="eastus2"
APP_NAME="azure-mcp-postgres-server"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Entra App Configuration
ENTRA_APP_NAME="Azure MCP Postgres Server API"
ENTRA_APP_ROLE_DESC="Executor role for MCP Tool operations"
ENTRA_APP_ROLE_DISPLAY="MCP Tool Executor"
ENTRA_APP_ROLE_VALUE="Mcp.Tool.Executor"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Function to display usage
show_usage() {
    echo "Usage: $0 --postgres-resource-id <resource_id> --resource-group <resource_group> [--location <location>]"
    echo ""
    echo "Arguments:"
    echo "  --postgres-resource-id   Resource ID of an existing PostgreSQL Flexible Server, in the format"
    echo "                           /subscriptions/{subscriptionId}/resourceGroups/{resourceGroup}/providers/Microsoft.DBforPostgreSQL/flexibleServers/{serverName}"
    echo "  --resource-group         Azure Resource Group name for deployment"
    echo "  --location               Azure region for deployment (optional, defaults to eastus2)"
    echo ""
    exit 1
}

# Function to validate postgres resource ID format
validate_postgres_resource_id() {
    local resource_id="$1"

    # Check if the postgres resource ID matches the expected pattern
    if [[ ! "$resource_id" =~ ^/subscriptions/[a-fA-F0-9-]+/resourceGroups/[^/]+/providers/Microsoft\.DBforPostgreSQL/flexibleServers/[^/]+$ ]]; then
        echo_error "Invalid postgres resource ID format"
        echo_error "Expected format: /subscriptions/{subscriptionId}/resourceGroups/{resourceGroup}/providers/Microsoft.DBforPostgreSQL/flexibleServers/{serverName}"
        echo_error "Provided: $resource_id"
        exit 1
    fi
    echo_info "Postgres resource ID format is valid"
}

# Function to parse command line arguments
parse_arguments() {
    POSTGRES_RESOURCE_ID=""
    RESOURCE_GROUP=""
    LOCATION="eastus2"  # Default location

    while [[ $# -gt 0 ]]; do
        case $1 in
            --postgres-resource-id)
                POSTGRES_RESOURCE_ID="$2"
                shift 2
                ;;
            --resource-group)
                RESOURCE_GROUP="$2"
                shift 2
                ;;
            --location)
                LOCATION="$2"
                shift 2
                ;;
            -h|--help)
                show_usage
                ;;
            *)
                echo_error "Unknown argument: $1"
                show_usage
                ;;
        esac
    done

    # Check if required arguments are provided
    if [ -z "$POSTGRES_RESOURCE_ID" ]; then
        echo_error "Missing required argument: --postgres-resource-id"
        show_usage
    fi

    if [ -z "$RESOURCE_GROUP" ]; then
        echo_error "Missing required argument: --resource-group"
        show_usage
    fi

    # Validate the postgres resource ID format
    validate_postgres_resource_id "$POSTGRES_RESOURCE_ID"

    # Extract SUBSCRIPTION_ID from POSTGRES_RESOURCE_ID
    SUBSCRIPTION_ID=$(echo "$POSTGRES_RESOURCE_ID" | sed -E 's|^/subscriptions/([^/]+)/.*$|\1|')
    if [[ -z "$SUBSCRIPTION_ID" ]]; then
        echo_error "Failed to extract SUBSCRIPTION_ID from postgres resource ID."
        exit 1
    fi
    
    # Extract POSTGRES_SERVER_NAME from POSTGRES_RESOURCE_ID
    POSTGRES_SERVER_NAME=$(echo "$POSTGRES_RESOURCE_ID" | sed -E 's|^.*/providers/Microsoft\.DBforPostgreSQL/flexibleServers/([^/]+)$|\1|')
    if [[ -z "$POSTGRES_SERVER_NAME" ]]; then
        echo_error "Failed to extract POSTGRES_SERVER_NAME from postgres resource ID."
        exit 1
    fi

    # Extract POSTGRES_RESOURCE_GROUP from POSTGRES_RESOURCE_ID
    POSTGRES_RESOURCE_GROUP=$(echo "$POSTGRES_RESOURCE_ID" | sed -E 's|^/subscriptions/[^/]+/resourceGroups/([^/]+)/.*$|\1|')
    if [[ -z "$POSTGRES_RESOURCE_GROUP" ]]; then
        echo_error "Failed to extract POSTGRES_RESOURCE_GROUP from postgres resource ID."
        exit 1
    fi
    
    echo_info "Using Azure Subscription: $SUBSCRIPTION_ID (From Postgres Resource ID: $POSTGRES_RESOURCE_ID)"
    echo_info "Using PostgreSQL Server: $POSTGRES_SERVER_NAME"
    echo_info "Using PostgreSQL Resource Group: $POSTGRES_RESOURCE_GROUP"
    echo_info "Using Resource Group: $RESOURCE_GROUP"
    echo_info "Using Location: $LOCATION"
}

echo_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

echo_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

echo_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Create or update Entra App registration
create_entra_app() {
    echo_info "Creating Entra App registration for Azure MCP Postgres Server: $ENTRA_APP_NAME"

    # Check if jq is installed
    if ! command -v jq &> /dev/null; then
        echo_error "jq is required but not installed. Please install jq to continue."
        echo_info "Install with: brew install jq"
        exit 1
    fi

    # Register the Entra App with app-role
    ENTRA_APP_JSON=$(az ad app create \
      --display-name "$ENTRA_APP_NAME" \
      --service-management-reference "4405e061-966a-4249-afdd-f7435f54a510" \
      -o json)

    ENTRA_APP_CLIENT_ID=$(jq -r .appId <<< "$ENTRA_APP_JSON")
    ENTRA_APP_OBJECT_ID=$(jq -r .id <<< "$ENTRA_APP_JSON")
    echo_info "ENTRA_APP_CLIENT_ID=$ENTRA_APP_CLIENT_ID"
    echo_info "ENTRA_APP_OBJECT_ID=$ENTRA_APP_OBJECT_ID"

    GRAPH_BASE="https://graph.microsoft.com/v1.0"
    ENTRA_APP_URL="$GRAPH_BASE/applications/$ENTRA_APP_OBJECT_ID"
    ENTRA_APP_ROLES_URL="${ENTRA_APP_URL}?\$select=appRoles"
    ENTRA_APP_ROLE_ID=$(uuidgen)

    # Set Application ID (audience) URI for the Entra App
    echo_info "Setting Application ID URI..."
    az rest --method PATCH \
      --url "$ENTRA_APP_URL" \
      --body "{\"identifierUris\":[\"api://$ENTRA_APP_CLIENT_ID\"]}" >/dev/null

    # Define the app-role in the Entra App
    echo_info "Checking for existing app role: $ENTRA_APP_ROLE_VALUE"

    # Check if the role already exists
    EXISTING_ROLE=$(az rest --method GET \
      --url "$ENTRA_APP_URL" -o json |
      jq --arg roleValue "$ENTRA_APP_ROLE_VALUE" '.appRoles[]? | select(.value == $roleValue)')

    if [ -z "$EXISTING_ROLE" ]; then
        echo_info "Role does not exist, adding app role: $ENTRA_APP_ROLE_VALUE"

        # Prepare the app-roles payload by fetching existing roles, appending a new one
        ENTRA_APP_ROLES_PATCH_JSON=$(az rest --method GET \
          --url "$ENTRA_APP_URL" -o json |
          jq --arg description "$ENTRA_APP_ROLE_DESC" \
             --arg displayName "$ENTRA_APP_ROLE_DISPLAY" \
             --arg roleValue  "$ENTRA_APP_ROLE_VALUE" \
             --arg roleId   "$ENTRA_APP_ROLE_ID" '
             .appRoles = (.appRoles // []) +
               [{
                 allowedMemberTypes: ["Application"],
                  description: $description,
                  displayName: $displayName,
                  id: $roleId,
                 isEnabled: true,
                  value: $roleValue,
                 origin: "Application"
               }] | {appRoles: .appRoles}
          ')

        # PATCH back the updated app-roles
        az rest --method PATCH \
          --url "$ENTRA_APP_URL" \
          --body "$ENTRA_APP_ROLES_PATCH_JSON" >/dev/null

        echo_info "App role added successfully"
        # Export the role ID we just created
        export ENTRA_APP_ROLE_ID_BY_VALUE="$ENTRA_APP_ROLE_ID"
    else
        echo_info "App role '$ENTRA_APP_ROLE_VALUE' already exists, extracting role ID"
        # Extract the role ID from existing role
        ENTRA_APP_ROLE_ID_BY_VALUE=$(echo "$EXISTING_ROLE" | jq -r '.id')
        export ENTRA_APP_ROLE_ID_BY_VALUE
    fi

    # Print the app-roles to verify
    APP_ROLES_READ=$(az rest --method GET \
      --url "$ENTRA_APP_ROLES_URL" \
      --query appRoles -o json)
    echo_info "Roles in Entra App:"
    echo "$APP_ROLES_READ"
    
    # Get the service principal object ID for the Entra App
    echo_info "Getting Entra App Service Principal Object ID..."
    ENTRA_APP_SP_OBJECT_ID=$(az ad sp list --filter "appId eq '$ENTRA_APP_CLIENT_ID'" --query "[0].id" -o tsv)
    if [ -z "$ENTRA_APP_SP_OBJECT_ID" ] || [ "$ENTRA_APP_SP_OBJECT_ID" = "null" ]; then
        echo_info "Entra App Service Principal not found, creating one..."
        az ad sp create --id "$ENTRA_APP_CLIENT_ID" >/dev/null
        ENTRA_APP_SP_OBJECT_ID=$(az ad sp list --filter "appId eq '$ENTRA_APP_CLIENT_ID'" --query "[0].id" -o tsv)
    fi
    echo_info "Entra App Service Principal Object ID: $ENTRA_APP_SP_OBJECT_ID"

    # Export variables for use in other functions
    export ENTRA_APP_CLIENT_ID
    export ENTRA_APP_OBJECT_ID
    export ENTRA_APP_ROLE_VALUE
    export ENTRA_APP_ROLE_ID_BY_VALUE
    export ENTRA_APP_SP_OBJECT_ID

    echo_info "Entra App registration completed successfully!"
}

# Check if required tools are installed
check_prerequisites() {
    echo_info "Checking prerequisites (az-cli, docker)..."

    if ! command -v az &> /dev/null; then
        echo_error "Azure CLI is not installed. Please install it from https://docs.microsoft.com/en-us/cli/azure/install-azure-cli"
        exit 1
    fi

    if ! command -v docker &> /dev/null; then
        echo_error "Docker is not installed. Please install Docker Desktop."
        exit 1
    fi

    echo_info "Prerequisites satisfied."
}

# Login to Azure
login_azure() {
    echo_info "Checking az cli login status..."

    if ! az account show &> /dev/null; then
        echo_info "Not logged in to az-cli. running 'az login'..."
        az login
    fi

    if [ -n "$SUBSCRIPTION_ID" ]; then
        echo_info "Setting subscription to $SUBSCRIPTION_ID"
        az account set --subscription "$SUBSCRIPTION_ID"
    fi

    echo_info "az cli login successful!"
}

# Create resource group
create_resource_group() {
    echo_info "Creating resource group: $RESOURCE_GROUP"

    az group create \
        --name "$RESOURCE_GROUP" \
        --location "$LOCATION" \
        --output table
}

# Deploy infrastructure
deploy_infrastructure() {
    echo_info "Creating Azure Container resources..."

    az deployment group create \
        --resource-group "$RESOURCE_GROUP" \
        --template-file "$SCRIPT_DIR/main.bicep" \
        --parameters "$SCRIPT_DIR/main.parameters.json" \
        --output table

    echo_info "Azure Container resources deployment completed!"
}

# Get deployment outputs
get_deployment_outputs() {
    echo_info "Getting deployment outputs..."

    # Get the latest deployment
    DEPLOYMENT_NAME=$(az deployment group list \
        --resource-group "$RESOURCE_GROUP" \
        --query "[0].name" \
        --output tsv)

    # Get outputs
    CONTAINER_REGISTRY=$(az deployment group show \
        --resource-group "$RESOURCE_GROUP" \
        --name "$DEPLOYMENT_NAME" \
        --query "properties.outputs.containerRegistryLoginServer.value" \
        --output tsv)

    CONTAINER_APP_URL=$(az deployment group show \
        --resource-group "$RESOURCE_GROUP" \
        --name "$DEPLOYMENT_NAME" \
        --query "properties.outputs.containerAppUrl.value" \
        --output tsv)

    echo_info "Container Registry: $CONTAINER_REGISTRY"
    echo_info "Container App URL: $CONTAINER_APP_URL"
}

# Update appsettings.json with Azure AD configuration
update_app_settings() {
    echo_info "Updating appsettings.json with Azure AD configuration..."

    # Get current tenant ID from Azure account
    echo_info "Getting current tenant ID from Azure account..."
    CURRENT_TENANT_ID=$(az account show --query "tenantId" --output tsv)
    echo_info "Current Tenant ID: $CURRENT_TENANT_ID"

    # Update appsettings.json with Entra App Client ID and Tenant ID
    echo_info "Updating appsettings.json with Tenant ID and Client ID..."
    APP_SETTINGS_FILE="$SCRIPT_DIR/../server/src/appsettings.json"

    # Create a backup
    cp "$APP_SETTINGS_FILE" "$APP_SETTINGS_FILE.bak"

    # Update TenantId, ClientId and Audience
    jq --arg tenantId "$CURRENT_TENANT_ID" \
       --arg clientId "$ENTRA_APP_CLIENT_ID" \
       '.AzureAd.TenantId = $tenantId | .AzureAd.ClientId = $clientId | .AzureAd.Audience = $clientId' \
       "$APP_SETTINGS_FILE" > "$APP_SETTINGS_FILE.tmp" && \
       mv "$APP_SETTINGS_FILE.tmp" "$APP_SETTINGS_FILE"
    
    echo_info "appsettings.json updated successfully!"
}

# Build and push container image
build_and_push_image() {
    echo_info "Building and pushing container image..."

    # Update appsettings.json with Azure AD configuration
    update_app_settings

    # Extract ACR name from login server (remove .azurecr.io)
    ACR_NAME="${CONTAINER_REGISTRY%.azurecr.io}"
    echo_info "Logging into ACR: $ACR_NAME"

    # Login to ACR
    az acr login --name "$ACR_NAME"

    # Build image
    IMAGE_TAG="$CONTAINER_REGISTRY/$APP_NAME:latest"

    echo_info "Building image: $IMAGE_TAG"
    docker build --platform linux/amd64 -f "$SCRIPT_DIR/../docker/Dockerfile" -t "$IMAGE_TAG" "$SCRIPT_DIR/.."

    echo_info "Pushing image: $IMAGE_TAG"
    docker push "$IMAGE_TAG"

    echo_info "Image pushed successfully!"
}

# Update container app with 'Azure MCP Postgres Server' image
update_container_app() {
    echo_info "Updating Azure Container App with 'Azure MCP Postgres Server' image..."

    IMAGE_TAG="$CONTAINER_REGISTRY/$APP_NAME:latest"

    az containerapp update \
        --name "$APP_NAME" \
        --resource-group "$RESOURCE_GROUP" \
        --image "$IMAGE_TAG" \
        --output table

    echo_info "Azure Container App updated successfully!"
}

# Show recent logs from the container app (showing azmcp and proxy server logs)
show_container_logs() {
    echo_info "Waiting 10 seconds for Azure Container App to initialize then fetching logs..."
    sleep 10

    echo ""
    echo_info "Azure Container App logs (hosting 'Azure MCP Postgres Server'):"
    echo "Begin_Azure_Container_App_Logs ---->"
    if az containerapp logs show \
        --name "$APP_NAME" \
        --resource-group "$RESOURCE_GROUP" \
        --tail 50 \
        --output table 2>/dev/null; then
        echo "<---- End_Azure_Container_App_Logs"
        echo ""
    else
        echo_warn "Could not retrieve logs. The Azure Container App might still be starting up, use the following command to check logs later."
        echo_info "az containerapp logs show --name $APP_NAME --resource-group $RESOURCE_GROUP --tail 50"
    fi
}

# Assign RBAC "Reader" role to Container App MI for PostgreSQL resource
assign_postgres_rbac() {
    echo_info "Assigning Reader role to Container App Managed Identity for PostgreSQL resource..."

    echo_info "Getting Container App Managed Identity Principal ID..."
    ACA_MI_PRINCIPAL_ID=$(az containerapp show \
        --resource-group "$RESOURCE_GROUP" \
        --name "$APP_NAME" \
        --query "identity.principalId" \
        --output tsv)

    if [ -z "$ACA_MI_PRINCIPAL_ID" ] || [ "$ACA_MI_PRINCIPAL_ID" = "null" ]; then
        echo_error "Failed to get Container App Managed Identity Principal ID"
        echo_error "Make sure the Container App has a system-assigned managed identity enabled"
        exit 1
    fi

    echo_info "Container App MI Principal ID: $ACA_MI_PRINCIPAL_ID"
    
    # Get the display name for the managed identity
    echo_info "Getting Container App Managed Identity Display Name..."
    ACA_MI_DISPLAY_NAME=$(az ad sp show --id "$ACA_MI_PRINCIPAL_ID" --query "displayName" --output tsv)
    echo_info "Container App MI Display Name: $ACA_MI_DISPLAY_NAME"

    echo_info "Assigning Reader role to Azure Container App MI for PostgreSQL resource scope: $POSTGRES_RESOURCE_ID"

    EXISTING_ASSIGNMENT=$(az role assignment list \
        --assignee "$ACA_MI_PRINCIPAL_ID" \
        --scope "$POSTGRES_RESOURCE_ID" \
        --role "Reader" \
        --query "[0].id" \
        --output tsv 2>/dev/null || echo "")

    if [ -n "$EXISTING_ASSIGNMENT" ] && [ "$EXISTING_ASSIGNMENT" != "null" ]; then
        echo_info "Reader role assignment already exists for this Managed Identity and PostgreSQL resource"
    else
        echo_info "Creating Reader role assignment..."
        az role assignment create \
            --assignee-object-id "$ACA_MI_PRINCIPAL_ID" \
            --assignee-principal-type "ServicePrincipal" \
            --role "Reader" \
            --scope "$POSTGRES_RESOURCE_ID"
        
        if [ $? -eq 0 ]; then
            echo_info "Successfully assigned Reader role to Container App MI for PostgreSQL resource"
        else
            echo_error "Failed to assign Reader role to Container App MI"
            exit 1
        fi
    fi
    
    # Export variables for use in deployment summary
    export ACA_MI_PRINCIPAL_ID
    export ACA_MI_DISPLAY_NAME
}

# Display deployment summary as JSON
show_deployment_summary() {
    echo_info "Deployment Summary (JSON):"
    
    # Create JSON summary
    SUMMARY_JSON=$(jq -n \
        --arg mcp_server_uri "$CONTAINER_APP_URL" \
        --arg entra_app_client_id "$ENTRA_APP_CLIENT_ID" \
        --arg entra_app_object_id "$ENTRA_APP_OBJECT_ID" \
        --arg entra_app_role_value "$ENTRA_APP_ROLE_VALUE" \
        --arg entra_app_role_id_by_value "$ENTRA_APP_ROLE_ID_BY_VALUE" \
        --arg entra_app_sp_object_id "$ENTRA_APP_SP_OBJECT_ID" \
        --arg aca_mi_principal_id "$ACA_MI_PRINCIPAL_ID" \
        --arg aca_mi_display_name "$ACA_MI_DISPLAY_NAME" \
        --arg postgres_server_name "$POSTGRES_SERVER_NAME" \
        --arg postgres_resource_group "$POSTGRES_RESOURCE_GROUP" \
        --arg resource_group "$RESOURCE_GROUP" \
        --arg subscription_id "$SUBSCRIPTION_ID" \
        --arg location "$LOCATION" \
        '{
            "MCP_SERVER_URI": $mcp_server_uri,
            "ENTRA_APP_CLIENT_ID": $entra_app_client_id,
            "ENTRA_APP_OBJECT_ID": $entra_app_object_id,
            "ENTRA_APP_SP_OBJECT_ID": $entra_app_sp_object_id,
            "ENTRA_APP_ROLE_VALUE": $entra_app_role_value,
            "ENTRA_APP_ROLE_ID_BY_VALUE": $entra_app_role_id_by_value,
            "ACA_MI_PRINCIPAL_ID": $aca_mi_principal_id,
            "ACA_MI_DISPLAY_NAME": $aca_mi_display_name,
            "RESOURCE_GROUP": $resource_group,
            "SUBSCRIPTION_ID": $subscription_id,
            "POSTGRES_RESOURCE_GROUP": $postgres_resource_group,
            "POSTGRES_SERVER_NAME": $postgres_server_name,
            "LOCATION": $location
        }')
    
    echo "$SUMMARY_JSON"
    
    DEPLOYMENT_INFO_FILE="$SCRIPT_DIR/deployment-info.json"
    echo "$SUMMARY_JSON" > "$DEPLOYMENT_INFO_FILE"
    echo_info "Deployment information written to: $DEPLOYMENT_INFO_FILE"
}

# Main function
main() {
    echo_info "Starting Azure Container Apps deployment..."

    parse_arguments "$@"

    check_prerequisites
    login_azure
    create_entra_app
    create_resource_group
    deploy_infrastructure
    get_deployment_outputs
    build_and_push_image
    update_container_app
    assign_postgres_rbac
    show_container_logs

    echo_info "Deployment completed!"
    show_deployment_summary
}

# Run main function
main "$@"