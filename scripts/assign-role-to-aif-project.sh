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
    echo "Usage: ./assign-role-to-aif-project.sh --ai-foundry-project-resource-id <resource-id> --service-principal-object-id <object-id> --app-role-id <role-id>"
    echo ""
    echo "Assign an app role to an AI Foundry project managed identity."
    echo ""
    echo "REQUIRED OPTIONS:"
    echo "  --ai-foundry-project-resource-id <resource-id>"
    echo "                          Resource ID of AI Foundry project"
    echo "                          Format: /subscriptions/{sub}/resourceGroups/{rg}/providers/Microsoft.CognitiveServices/accounts/{account}/projects/{project}"
    echo "  --service-principal-object-id <object-id>"
    echo "                          Object ID of the service principal that owns the app role"
    echo "  --app-role-id <role-id>"
    echo "                          App role ID (GUID) to assign"
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

validate_guid() {
    local guid="$1"
    local field_name="$2"
    if [[ ! "$guid" =~ ^[a-fA-F0-9]{8}-[a-fA-F0-9]{4}-[a-fA-F0-9]{4}-[a-fA-F0-9]{4}-[a-fA-F0-9]{12}$ ]]; then
        echo_error "Invalid $field_name format"
        echo_error "Expected format: GUID (e.g., 12345678-1234-1234-1234-123456789abc)"
        echo_error "Provided: $guid"
        exit 1
    fi
}

# Function to parse command line arguments
parse_arguments() {
    AI_FOUNDRY_PROJECT_RESOURCE_ID=""
    SERVICE_PRINCIPAL_OBJECT_ID=""
    APP_ROLE_ID=""

    while [[ $# -gt 0 ]]; do
        case $1 in
            --ai-foundry-project-resource-id)
                AI_FOUNDRY_PROJECT_RESOURCE_ID="$2"
                shift 2
                ;;
            --service-principal-object-id)
                SERVICE_PRINCIPAL_OBJECT_ID="$2"
                shift 2
                ;;
            --app-role-id)
                APP_ROLE_ID="$2"
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

    if [ -z "$SERVICE_PRINCIPAL_OBJECT_ID" ]; then
        echo_error "Missing required argument: --service-principal-object-id"
        print_usage
        exit 1
    fi

    if [ -z "$APP_ROLE_ID" ]; then
        echo_error "Missing required argument: --app-role-id"
        print_usage
        exit 1
    fi

    # Validate formats
    validate_ai_foundry_project_resource_id "$AI_FOUNDRY_PROJECT_RESOURCE_ID"
    validate_guid "$SERVICE_PRINCIPAL_OBJECT_ID" "service principal object ID"
    validate_guid "$APP_ROLE_ID" "app role ID"

    # Extract components from AI Foundry project resource ID
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
    echo_info "✓ Service Principal Object ID: $SERVICE_PRINCIPAL_OBJECT_ID"
    echo_info "✓ App Role ID: $APP_ROLE_ID"
    echo_info "✓ Using Azure Subscription: $AI_FOUNDRY_SUBSCRIPTION_ID"
    echo_info "✓ Using AI Foundry Account: $AI_FOUNDRY_ACCOUNT_NAME"
    echo_info "✓ Using AI Foundry Resource Group: $AI_FOUNDRY_RESOURCE_GROUP"
    echo_info "✓ Using AI Foundry Project: $AI_FOUNDRY_PROJECT_NAME"
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

    echo_info "Azure CLI login verified"
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

validate_app_role_exists() {
    echo_info "Validating app role ID exists in service principal..."
    
    GRAPH_ACCESS_TOKEN=$(get_access_token "https://graph.microsoft.com")

    echo_info "Fetching service principal details..."
    SP_RESPONSE=$(curl -s -X GET \
        "https://graph.microsoft.com/v1.0/servicePrincipals/$SERVICE_PRINCIPAL_OBJECT_ID?$select=appRoles,displayName" \
        -H "Authorization: Bearer $GRAPH_ACCESS_TOKEN" \
        -H "Content-Type: application/json")

    if [ $? -ne 0 ]; then
        echo_error "Failed to fetch service principal details"
        exit 1
    fi

    # Check if service principal exists
    SP_DISPLAY_NAME=$(jq -r '.displayName // empty' <<< "$SP_RESPONSE")
    if [[ -z "$SP_DISPLAY_NAME" ]]; then
        echo_error "Service principal not found or access denied"
        echo_error "Service Principal Object ID: $SERVICE_PRINCIPAL_OBJECT_ID"
        exit 1
    fi

    echo_info "✓ Service Principal found: $SP_DISPLAY_NAME"

    # Get app roles
    APP_ROLES_JSON=$(jq -r '.appRoles // []' <<< "$SP_RESPONSE")
    
    # Check if the specific app role ID exists
    MATCHING_ROLE=$(echo "$APP_ROLES_JSON" | jq -r ".[] | select(.id==\"$APP_ROLE_ID\")")
    
    if [[ -n "$MATCHING_ROLE" ]]; then
        ROLE_VALUE=$(echo "$MATCHING_ROLE" | jq -r '.value // "N/A"')
        ROLE_DISPLAY_NAME=$(echo "$MATCHING_ROLE" | jq -r '.displayName // "N/A"')
        echo_info "✓ App role ID found: $APP_ROLE_ID"
        echo_info "  Role Value: $ROLE_VALUE"
        echo_info "  Display Name: $ROLE_DISPLAY_NAME"
    else
        echo_error "App role ID not found: $APP_ROLE_ID"
        echo_error ""
        echo_error "Available app roles in service principal '$SP_DISPLAY_NAME':"
        
        APP_ROLES_COUNT=$(echo "$APP_ROLES_JSON" | jq 'length')
        if [[ "$APP_ROLES_COUNT" == "0" ]]; then
            echo_error "  No app roles defined in this service principal"
        else
            echo "$APP_ROLES_JSON" | jq -r '.[] | "  ID: \(.id)  Value: \(.value // "N/A")  DisplayName: \(.displayName // "N/A")"'
        fi
        exit 1
    fi
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
    
    echo_info "✓ AI Foundry Project MI Principal ID: $AI_FOUNDRY_PROJECT_MI_PRINCIPAL_ID"
    echo_info "✓ AI Foundry Project MI Type: $AI_FOUNDRY_PROJECT_MI_TYPE"
    echo_info "✓ AI Foundry Project MI Tenant ID: $AI_FOUNDRY_PROJECT_MI_TENANT_ID"
}

assign_role_to_ai_foundry_project_mi() {
    echo_info "Assigning app role to AI Foundry project managed identity..."
    
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

    # Print all current role assignments
    echo_info "Current role assignments for AI Foundry project MI:"
    ASSIGNMENTS_COUNT=$(echo "$EXISTING_RESPONSE" | jq '.value | length')
    if [[ "$ASSIGNMENTS_COUNT" == "0" ]]; then
        echo_info "  No existing role assignments found"
    else
        echo "$EXISTING_RESPONSE" | jq -r '.value[] | "  SP Object ID: \(.resourceId)  App Role ID: \(.appRoleId)  Assignment ID: \(.id)"'
    fi
    echo ""

    EXISTING_ASSIGNMENT=$(echo "$EXISTING_RESPONSE" | jq -r ".value[] | select(.resourceId==\"$SERVICE_PRINCIPAL_OBJECT_ID\" and .appRoleId==\"$APP_ROLE_ID\") | .id" 2>/dev/null)

    if [[ -n "$EXISTING_ASSIGNMENT" ]]; then
        echo_info "✓ App role assignment already exists for this project MI"
        echo_info "✓ Role Assignment ID: $EXISTING_ASSIGNMENT"
        ROLE_ASSIGNMENT_ID="$EXISTING_ASSIGNMENT"
    else
        echo_warn "About to assign app role to AI Foundry project managed identity:"
        echo_warn "  AI Foundry Project: $AI_FOUNDRY_PROJECT_NAME"
        echo_warn "  Service Principal: $SP_DISPLAY_NAME"
        echo_warn "  App Role: $ROLE_VALUE ($ROLE_DISPLAY_NAME)"
        echo_warn ""
        echo -n "Do you want to proceed with the role assignment? (y/N): "
        read -r CONFIRM
        
        if [[ "$CONFIRM" != "y" && "$CONFIRM" != "Y" ]]; then
            echo_info "Role assignment cancelled by user"
            exit 0
        fi

        echo_info "Creating app role assignment..."

        ROLE_ASSIGNMENT_PAYLOAD=$(jq -n \
            --arg principalId "$AI_FOUNDRY_PROJECT_MI_PRINCIPAL_ID" \
            --arg resourceId "$SERVICE_PRINCIPAL_OBJECT_ID" \
            --arg appRoleId "$APP_ROLE_ID" \
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
            ROLE_ASSIGNMENT_ID=$(jq -r '.id // empty' <<< "$ROLE_ASSIGNMENT_RESPONSE")
            if [[ -n "$ROLE_ASSIGNMENT_ID" && "$ROLE_ASSIGNMENT_ID" != "null" ]]; then
                echo_info "✓ Successfully assigned app role to project MI"
                echo_info "✓ Role Assignment ID: $ROLE_ASSIGNMENT_ID"
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

show_results() {
    echo ""
    echo_info "AI Foundry Project Resource ID: $AI_FOUNDRY_PROJECT_RESOURCE_ID"
    echo_info "AI Foundry Project MI Principal ID: $AI_FOUNDRY_PROJECT_MI_PRINCIPAL_ID"
    echo_info "Service Principal Object ID: $SERVICE_PRINCIPAL_OBJECT_ID"
    echo_info "App Role ID: $APP_ROLE_ID"
    echo_info "Role Assignment ID: $ROLE_ASSIGNMENT_ID"
    echo ""
}

# Main function
main() {
    parse_arguments "$@"
    check_prerequisites
    login_azure
    validate_app_role_exists
    get_ai_foundry_project_mi
    assign_role_to_ai_foundry_project_mi
    show_results
}

# Run main function
main "$@"