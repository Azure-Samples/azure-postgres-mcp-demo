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
print_usage() {
    echo "Usage: ./create-aif-mi-connection-assign-role.sh --ai-foundry-project-resource-id <resource-id> --connection-name <name>"
    echo ""
    echo "Create a managed identity connection in AI Foundry project and assign Entra App role."
    echo ""
    echo "REQUIRED OPTIONS:"
    echo "  --ai-foundry-project-resource-id <resource-id>"
    echo "                          Resource ID of AI Foundry project"
    echo "                          Format: /subscriptions/{sub}/resourceGroups/{rg}/providers/Microsoft.CognitiveServices/accounts/{account}/projects/{project}"
    echo "  --connection-name <name>"
    echo "                          Connection name"
    echo ""
    echo "NOTE: deployment-info.json must exist in the same directory as this script."
    echo "      This file is produced when running deploy-azmcp-postgres-server.sh"
    echo "      It should contain: MCP_SERVER_URI, ENTRA_APP_CLIENT_ID, ENTRA_APP_ROLE_VALUE, ENTRA_APP_ROLE_ID_BY_VALUE, ENTRA_APP_SP_OBJECT_ID"
    echo "      Connection target is read from MCP_SERVER_URI"
    echo "      Connection audience is constructed as api://{ENTRA_APP_CLIENT_ID}"
    echo ""
}

validate_ai_foundry_project_resource_id() {
    local resource_id="$1"
    if [[ ! "$resource_id" =~ ^/subscriptions/[a-fA-F0-9-]+/resourceGroups/[^/]+/providers/Microsoft\.CognitiveServices/accounts/[^/]+/projects/[^/]+$ ]]; then
        echo_error "Invalid AI Foundry project resource ID format"
        echo_error "Expected format: /subscriptions/{subscriptionId}/resourceGroups/{resourceGroup}/providers/Microsoft.CognitiveServices/accounts/{accountName}/projects/{projectName}"
        echo_error "Provided: $resource_id"
        exit 1
    fi
}

# Function to parse command line arguments
parse_arguments() {
    AI_FOUNDRY_PROJECT_RESOURCE_ID=""
    CONNECTION_NAME=""

    while [[ $# -gt 0 ]]; do
        case $1 in
            --ai-foundry-project-resource-id)
                AI_FOUNDRY_PROJECT_RESOURCE_ID="$2"
                shift 2
                ;;
            --connection-name)
                CONNECTION_NAME="$2"
                shift 2
                ;;
            -h|--help)
                print_usage
                exit 0
                ;;
            *)
                echo_error "Unknown argument: $1"
                print_usage
                exit 1
                ;;
        esac
    done

    # Check if all required arguments are provided
    if [ -z "$AI_FOUNDRY_PROJECT_RESOURCE_ID" ]; then
        echo_error "Missing required argument: --ai-foundry-project-resource-id"
        print_usage
        exit 1
    fi

    if [ -z "$CONNECTION_NAME" ]; then
        echo_error "Missing required argument: --connection-name"
        print_usage
        exit 1
    fi

    validate_ai_foundry_project_resource_id "$AI_FOUNDRY_PROJECT_RESOURCE_ID"

    AI_FOUNDRY_SUBSCRIPTION_ID=$(echo "$AI_FOUNDRY_PROJECT_RESOURCE_ID" | sed -E 's|^/subscriptions/([^/]+)/.*$|\1|')
    if [[ -z "$AI_FOUNDRY_SUBSCRIPTION_ID" ]]; then
        echo_error "Failed to extract AI_FOUNDRY_SUBSCRIPTION_ID from AI Foundry project resource ID."
        exit 1
    fi
    
    AI_FOUNDRY_ACCOUNT_NAME=$(echo "$AI_FOUNDRY_PROJECT_RESOURCE_ID" | sed -E 's|^.*/providers/Microsoft\.CognitiveServices/accounts/([^/]+)/projects/.*$|\1|')
    if [[ -z "$AI_FOUNDRY_ACCOUNT_NAME" ]]; then
        echo_error "Failed to extract AI_FOUNDRY_ACCOUNT_NAME from AI Foundry project resource ID."
        exit 1
    fi

    AI_FOUNDRY_RESOURCE_GROUP=$(echo "$AI_FOUNDRY_PROJECT_RESOURCE_ID" | sed -E 's|^/subscriptions/[^/]+/resourceGroups/([^/]+)/.*$|\1|')
    if [[ -z "$AI_FOUNDRY_RESOURCE_GROUP" ]]; then
        echo_error "Failed to extract AI_FOUNDRY_RESOURCE_GROUP from AI Foundry project resource ID."
        exit 1
    fi

    AI_FOUNDRY_PROJECT_NAME=$(echo "$AI_FOUNDRY_PROJECT_RESOURCE_ID" | sed -E 's|^.*/projects/([^/]+)$|\1|')
    if [[ -z "$AI_FOUNDRY_PROJECT_NAME" ]]; then
        echo_error "Failed to extract AI_FOUNDRY_PROJECT_NAME from AI Foundry project resource ID."
        exit 1
    fi
    
    echo_info "✓ AI Foundry Project Resource ID: $AI_FOUNDRY_PROJECT_RESOURCE_ID"
    echo_info "✓ Connection Name: $CONNECTION_NAME"
    echo_info "✓ Using Azure Subscription: $AI_FOUNDRY_SUBSCRIPTION_ID"
    echo_info "✓ Using AI Foundry Account: $AI_FOUNDRY_ACCOUNT_NAME"
    echo_info "✓ Using AI Foundry Resource Group: $AI_FOUNDRY_RESOURCE_GROUP"
    echo_info "✓ Using AI Foundry Project: $AI_FOUNDRY_PROJECT_NAME"

    # Load deployment info file from same directory as script
    DEPLOYMENT_INFO_FILE="${SCRIPT_DIR}/deployment-info.json"
    if [ ! -f "$DEPLOYMENT_INFO_FILE" ]; then
        echo_error "Deployment info file not found: $DEPLOYMENT_INFO_FILE"
        exit 1
    fi
    
    echo_info "Loading deployment info from: $DEPLOYMENT_INFO_FILE"
    MCP_SERVER_URI=$(jq -r '.MCP_SERVER_URI // empty' "$DEPLOYMENT_INFO_FILE")
    ENTRA_APP_CLIENT_ID=$(jq -r '.ENTRA_APP_CLIENT_ID // empty' "$DEPLOYMENT_INFO_FILE")
    ENTRA_APP_ROLE_VALUE=$(jq -r '.ENTRA_APP_ROLE_VALUE // empty' "$DEPLOYMENT_INFO_FILE")
    ENTRA_APP_ROLE_ID_BY_VALUE=$(jq -r '.ENTRA_APP_ROLE_ID_BY_VALUE // empty' "$DEPLOYMENT_INFO_FILE")
    ENTRA_APP_SP_OBJECT_ID=$(jq -r '.ENTRA_APP_SP_OBJECT_ID // empty' "$DEPLOYMENT_INFO_FILE")
    
    if [[ -z "$MCP_SERVER_URI" || -z "$ENTRA_APP_CLIENT_ID" || -z "$ENTRA_APP_ROLE_VALUE" || -z "$ENTRA_APP_ROLE_ID_BY_VALUE" || -z "$ENTRA_APP_SP_OBJECT_ID" ]]; then
        echo_error "Missing required fields in deployment-info.json"
        echo_error "Required fields: MCP_SERVER_URI, ENTRA_APP_CLIENT_ID, ENTRA_APP_ROLE_VALUE, ENTRA_APP_ROLE_ID_BY_VALUE, ENTRA_APP_SP_OBJECT_ID"
        exit 1
    fi
    
    # Construct connection target and audience from deployment info
    CONNECTION_TARGET="$MCP_SERVER_URI"
    CONNECTION_AUDIENCE="$ENTRA_APP_CLIENT_ID"
    
    echo_info "✓ Deployment info loaded successfully"
    echo_info "✓ Connection Target: $CONNECTION_TARGET"
    echo_info "✓ Connection Audience: $CONNECTION_AUDIENCE"
}

check_prerequisites() {
    echo_info "Checking prerequisites (az-cli, jq, curl)..."

    if ! command -v az &> /dev/null; then
        echo_error "Azure CLI is not installed. Please install it from https://docs.microsoft.com/en-us/cli/azure/install-azure-cli"
        exit 1
    fi

    if ! command -v jq &> /dev/null; then
        echo_error "jq is required but not installed. Please install jq to continue."
        echo_info "Install with: brew install jq"
        exit 1
    fi

    if ! command -v curl &> /dev/null; then
        echo_error "curl is required but not installed. Please install curl to continue."
        exit 1
    fi
}

login_azure() {
    echo_info "Checking az cli login status..."

    if ! az account show &> /dev/null; then
        echo_info "Not logged in to az-cli. running 'az login'..."
        az login
    fi

    if [ -n "$AI_FOUNDRY_SUBSCRIPTION_ID" ]; then
        echo_info "Setting subscription to $AI_FOUNDRY_SUBSCRIPTION_ID"
        az account set --subscription "$AI_FOUNDRY_SUBSCRIPTION_ID"
    fi
}

get_access_token() {
    local resource_uri="$1"
    
    if [[ -z "$resource_uri" ]]; then
        echo_error "Resource URI is required"
        exit 1
    fi

    TOKEN_JSON=$(az account get-access-token --resource "$resource_uri" -o json)

    if [ $? -ne 0 ]; then
        echo_error "Failed to get access token for $resource_uri"
        exit 1
    fi

    ACCESS_TOKEN=$(jq -r '.accessToken // empty' <<< "$TOKEN_JSON")
    if [[ -z "$ACCESS_TOKEN" ]]; then
        echo_error "Failed to extract access token for $resource_uri"
        exit 1
    fi

    echo "$ACCESS_TOKEN"
}

get_ai_foundry_project_mi() {
    echo_info "Fetching AI Foundry account region..."

    AI_FOUNDRY_ACCOUNT_JSON=$(az cognitiveservices account show \
        --name "$AI_FOUNDRY_ACCOUNT_NAME" \
        --resource-group "$AI_FOUNDRY_RESOURCE_GROUP" \
        -o json)

    if [ $? -ne 0 ]; then
        echo_error "Failed to get AI Foundry account details"
        exit 1
    fi

    AI_FOUNDRY_REGION=$(jq -r '.location // empty' <<< "$AI_FOUNDRY_ACCOUNT_JSON")
    if [[ -z "$AI_FOUNDRY_REGION" ]]; then
        echo_error "Failed to extract region from AI Foundry account"
        exit 1
    fi

    # Normalize region name (remove spaces, convert to lowercase)
    AI_FOUNDRY_REGION=$(echo "$AI_FOUNDRY_REGION" | tr '[:upper:]' '[:lower:]' | tr -d ' ')

    ARM_ACCESS_TOKEN=$(get_access_token "https://management.azure.com")

    echo_info "Fetching AI Foundry project details..."

    API_ENDPOINT="https://${AI_FOUNDRY_REGION}.management.azure.com:443/subscriptions/${AI_FOUNDRY_SUBSCRIPTION_ID}/resourcegroups/${AI_FOUNDRY_RESOURCE_GROUP}/providers/Microsoft.CognitiveServices/accounts/${AI_FOUNDRY_ACCOUNT_NAME}/projects/${AI_FOUNDRY_PROJECT_NAME}?api-version=2025-04-01-preview"

    AI_FOUNDRY_PROJECT_JSON=$(curl -s -X GET \
        -H "Authorization: Bearer $ARM_ACCESS_TOKEN" \
        -H "Content-Type: application/json" \
        "$API_ENDPOINT")

    if [ $? -ne 0 ]; then
        echo_error "Failed to fetch AI Foundry project details"
        exit 1
    fi

    if [[ -z "$AI_FOUNDRY_PROJECT_JSON" ]]; then
        echo_error "Empty response from API"
        exit 1
    fi

    AI_FOUNDRY_PROJECT_MI_PRINCIPAL_ID=$(jq -r '.identity.principalId // empty' <<< "$AI_FOUNDRY_PROJECT_JSON")
    if [[ -z "$AI_FOUNDRY_PROJECT_MI_PRINCIPAL_ID" ]]; then
        echo_error "Failed to extract project MI Principal ID from AI Foundry project"
        echo_error "Response:"
        echo_error "$AI_FOUNDRY_PROJECT_JSON"
        exit 1
    fi

    AI_FOUNDRY_PROJECT_MI_TENANT_ID=$(jq -r '.identity.tenantId // empty' <<< "$AI_FOUNDRY_PROJECT_JSON")
    AI_FOUNDRY_PROJECT_MI_TYPE=$(jq -r '.identity.type // empty' <<< "$AI_FOUNDRY_PROJECT_JSON")
}

set_ai_foundry_mi_role_assignment() {
    echo_info "Assigning app role to AI Foundry project MI..."
    
    GRAPH_ACCESS_TOKEN=$(get_access_token "https://graph.microsoft.com")

    echo_info "Checking for existing role assignment..."
    EXISTING_RESPONSE=$(curl -s -X GET \
        "https://graph.microsoft.com/v1.0/servicePrincipals/$AI_FOUNDRY_PROJECT_MI_PRINCIPAL_ID/appRoleAssignments" \
        -H "Authorization: Bearer $GRAPH_ACCESS_TOKEN" \
        -H "Content-Type: application/json")

    if [ $? -ne 0 ]; then
        echo_error "Failed to query existing role assignments"
        exit 1
    fi

    EXISTING_ASSIGNMENT=$(echo "$EXISTING_RESPONSE" | jq -r ".value[] | select(.resourceId==\"$ENTRA_APP_SP_OBJECT_ID\" and .appRoleId==\"$ENTRA_APP_ROLE_ID_BY_VALUE\") | .id" 2>/dev/null)

    if [[ -n "$EXISTING_ASSIGNMENT" ]]; then
        echo_info "App role assignment already exists for this project MI"
        echo_info "✓ Role Assignment ID: $EXISTING_ASSIGNMENT"
        ENTRA_APP_ROLE_ASSIGNMENT_ID="$EXISTING_ASSIGNMENT"
    else
        echo_info "Creating app role assignment: '$ENTRA_APP_ROLE_VALUE' to project MI..."

        ROLE_ASSIGNMENT_PAYLOAD=$(jq -n \
            --arg principalId "$AI_FOUNDRY_PROJECT_MI_PRINCIPAL_ID" \
            --arg resourceId "$ENTRA_APP_SP_OBJECT_ID" \
            --arg appRoleId "$ENTRA_APP_ROLE_ID_BY_VALUE" \
            '{
                "principalId": $principalId,
                "resourceId": $resourceId,
                "appRoleId": $appRoleId
            }')

        ROLE_ASSIGNMENT_RESPONSE=$(curl -s -X POST \
            "https://graph.microsoft.com/v1.0/servicePrincipals/$AI_FOUNDRY_PROJECT_MI_PRINCIPAL_ID/appRoleAssignments" \
            -H "Authorization: Bearer $GRAPH_ACCESS_TOKEN" \
            -H "Content-Type: application/json" \
            -d "$ROLE_ASSIGNMENT_PAYLOAD")

        if [ $? -eq 0 ]; then
            ENTRA_APP_ROLE_ASSIGNMENT_ID=$(jq -r '.id // empty' <<< "$ROLE_ASSIGNMENT_RESPONSE")
            if [[ -n "$ENTRA_APP_ROLE_ASSIGNMENT_ID" && "$ENTRA_APP_ROLE_ASSIGNMENT_ID" != "null" ]]; then
                echo_info "✓ Successfully assigned app role to project MI"
                echo_info "✓ Role Assignment ID: $ENTRA_APP_ROLE_ASSIGNMENT_ID"
            else
                echo_error "Failed to assign app role to project MI"
                echo_error "Response:"
                echo_error "$ROLE_ASSIGNMENT_RESPONSE"
                exit 1
            fi
        else
            echo_error "Failed to create app role assignment"
            exit 1
        fi
    fi
}

create_ai_foundry_mi_connection() {
    echo_info "Creating managed identity connection: $CONNECTION_NAME..."

    ARM_ACCESS_TOKEN=$(get_access_token "https://management.azure.com")

    CONNECTION_PAYLOAD=$(jq -n \
        --arg name "$CONNECTION_NAME" \
        --arg target "$CONNECTION_TARGET" \
        --arg audience "$CONNECTION_AUDIENCE" \
        '{
            "name": $name,
            "type": "Microsoft.CognitiveServices/accounts/projects/connections",
            "properties": {
                "authType": "ProjectManagedIdentity",
                "audience": $audience,
                "group": "GenericProtocol",
                "category": "RemoteTool",
                "target": $target,
                "useWorkspaceManagedIdentity": false,
                "isSharedToAll": false,
                "sharedUserList": [],
                "metadata": {
                    "type": "custom_MCP"
                }
            }
        }')

    API_ENDPOINT="https://${AI_FOUNDRY_REGION}.management.azure.com:443/subscriptions/${AI_FOUNDRY_SUBSCRIPTION_ID}/resourcegroups/${AI_FOUNDRY_RESOURCE_GROUP}/providers/Microsoft.CognitiveServices/accounts/${AI_FOUNDRY_ACCOUNT_NAME}/projects/${AI_FOUNDRY_PROJECT_NAME}/connections/${CONNECTION_NAME}?api-version=2025-04-01-preview"

    CREATE_CONNECTION_RESPONSE=$(curl -s -X PUT \
        -H "Authorization: Bearer $ARM_ACCESS_TOKEN" \
        -H "Content-Type: application/json" \
        -d "$CONNECTION_PAYLOAD" \
        "$API_ENDPOINT")

    if [ $? -ne 0 ]; then
        echo_error "Failed to create connection"
        exit 1
    fi

    if [[ -z "$CREATE_CONNECTION_RESPONSE" ]]; then
        echo_error "Empty response from API"
        exit 1
    fi

    AI_FOUNDRY_PROJECT_MI_CONNECTION_NAME=$(jq -r '.name // empty' <<< "$CREATE_CONNECTION_RESPONSE")
    if [[ -z "$AI_FOUNDRY_PROJECT_MI_CONNECTION_NAME" ]]; then
        echo_error "Failed to read connection name from response"
        echo_error "Response:"
        echo_error "$CREATE_CONNECTION_RESPONSE"
        exit 1
    fi

    AI_FOUNDRY_PROJECT_MI_CONNECTION_TARGET=$(jq -r '.properties.target // empty' <<< "$CREATE_CONNECTION_RESPONSE")
    if [[ -z "$AI_FOUNDRY_PROJECT_MI_CONNECTION_TARGET" ]]; then
        echo_error "Failed to read connection target from response"
        echo_error "Response:"
        echo_error "$CREATE_CONNECTION_RESPONSE"
        exit 1
    fi

    AI_FOUNDRY_PROJECT_MI_CONNECTION_AUDIENCE=$(jq -r '.properties.audience // empty' <<< "$CREATE_CONNECTION_RESPONSE")
    if [[ -z "$AI_FOUNDRY_PROJECT_MI_CONNECTION_AUDIENCE" ]]; then
        echo_error "Failed to read connection audience from response"
        echo_error "Response:"
        echo_error "$CREATE_CONNECTION_RESPONSE"
        exit 1
    fi
}

# Display results as JSON
show_results() {
    echo ""
    jq -n \
        --arg ai_foundry_project_resource_id "$AI_FOUNDRY_PROJECT_RESOURCE_ID" \
        --arg ai_foundry_subscription_id "$AI_FOUNDRY_SUBSCRIPTION_ID" \
        --arg ai_foundry_resource_group "$AI_FOUNDRY_RESOURCE_GROUP" \
        --arg ai_foundry_account_name "$AI_FOUNDRY_ACCOUNT_NAME" \
        --arg ai_foundry_project_name "$AI_FOUNDRY_PROJECT_NAME" \
        --arg ai_foundry_region "$AI_FOUNDRY_REGION" \
        --arg ai_foundry_project_mi_principal_id "$AI_FOUNDRY_PROJECT_MI_PRINCIPAL_ID" \
        --arg ai_foundry_project_mi_type "$AI_FOUNDRY_PROJECT_MI_TYPE" \
        --arg ai_foundry_project_mi_tenant_id "$AI_FOUNDRY_PROJECT_MI_TENANT_ID" \
        --arg ai_foundry_project_mi_connection_name "$AI_FOUNDRY_PROJECT_MI_CONNECTION_NAME" \
        --arg ai_foundry_project_mi_connection_target "$AI_FOUNDRY_PROJECT_MI_CONNECTION_TARGET" \
        --arg ai_foundry_project_mi_connection_audience "$AI_FOUNDRY_PROJECT_MI_CONNECTION_AUDIENCE" \
        '{
            "AI_FOUNDRY_PROJECT_RESOURCE_ID": $ai_foundry_project_resource_id,
            "AI_FOUNDRY_SUBSCRIPTION_ID": $ai_foundry_subscription_id,
            "AI_FOUNDRY_RESOURCE_GROUP": $ai_foundry_resource_group,
            "AI_FOUNDRY_ACCOUNT_NAME": $ai_foundry_account_name,
            "AI_FOUNDRY_PROJECT_NAME": $ai_foundry_project_name,
            "AI_FOUNDRY_REGION": $ai_foundry_region,
            "AI_FOUNDRY_PROJECT_MI_PRINCIPAL_ID": $ai_foundry_project_mi_principal_id,
            "AI_FOUNDRY_PROJECT_MI_TYPE": $ai_foundry_project_mi_type,
            "AI_FOUNDRY_PROJECT_MI_TENANT_ID": $ai_foundry_project_mi_tenant_id,
            "AI_FOUNDRY_PROJECT_MI_CONNECTION_NAME": $ai_foundry_project_mi_connection_name,
            "AI_FOUNDRY_PROJECT_MI_CONNECTION_TARGET": $ai_foundry_project_mi_connection_target,
            "AI_FOUNDRY_PROJECT_MI_CONNECTION_AUDIENCE": $ai_foundry_project_mi_connection_audience
        }'
    echo ""
}

# Main function
main() {
    parse_arguments "$@"
    check_prerequisites
    login_azure
    get_ai_foundry_project_mi
    create_ai_foundry_mi_connection
    set_ai_foundry_mi_role_assignment
    show_results
}

# Run main function
main "$@"
