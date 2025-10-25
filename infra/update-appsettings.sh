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

update_app_settings() {
    echo_info "Updating appsettings.json with Azure AD configuration..."

    APP_SETTINGS_FILE="$SCRIPT_DIR/../server/src/appsettings.json"

    AZURE_TENANT_ID=$(azd env get-values | grep AZURE_TENANT_ID | cut -d'=' -f2 | tr -d '"')
    ENTRA_APP_CLIENT_ID=$(azd env get-values | grep ENTRA_APP_CLIENT_ID | cut -d'=' -f2 | tr -d '"')

    if [ -z "$AZURE_TENANT_ID" ] || [ -z "$ENTRA_APP_CLIENT_ID" ]; then
        echo_error "Failed to get required values from azd environment"
        echo_error "AZURE_TENANT_ID: $AZURE_TENANT_ID"
        echo_error "ENTRA_APP_CLIENT_ID: $ENTRA_APP_CLIENT_ID"
        exit 1
    fi

    echo_info "Current Tenant ID: $AZURE_TENANT_ID"
    echo_info "Entra App Client ID: $ENTRA_APP_CLIENT_ID"

    cp "$APP_SETTINGS_FILE" "$APP_SETTINGS_FILE.bak"

    cat > "$APP_SETTINGS_FILE" <<EOF
{
  "Logging": {
    "LogLevel": {
      "Default": "Information",
      "Microsoft.AspNetCore": "Warning"
    }
  },
  "AllowedHosts": "*",
  "AzureAd": {
    "Instance": "https://login.microsoftonline.com/",
    "TenantId": "${AZURE_TENANT_ID}",
    "ClientId": "${ENTRA_APP_CLIENT_ID}",
    "Audience": "${ENTRA_APP_CLIENT_ID}"
  }
}
EOF
    
    echo_info "appsettings.json updated successfully!"
}

main() {
    update_app_settings
}

main "$@"
