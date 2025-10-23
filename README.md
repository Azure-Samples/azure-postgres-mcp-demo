# Azure MCP PostgreSQL Server

This repository provides a prototype of a self-hosted "Azure MCP Server" - hosted on Azure Container Apps (ACA) - that enables secure access to PostgreSQL databases using ACA Managed Identity.

## Components

The system consists of three main components:

1. **AI Foundry Agent** (Client): Authenticates to the Azure MCP Server using its Managed Identity.  
   *Note: This prototype uses Azure Container Instance (ACI) with MI as substitute client (identical token acquisition as future AI Foundry MI, expected in early October under a feature flag).*

2. **Azure MCP PostgreSQL Server** (Server): Runs in Azure Container Apps (ACA), using ACA Managed Identity for PostgreSQL access.

3. **PostgreSQL Database** (Target): Azure Database for PostgreSQL Flexible Server with Entra ID authentication enabled.

**Identity Separation**: Two separate managed identities are used - the client MI (ACI/AI Foundry) authenticates to the MCP Server, while the MCP Server uses its own ACA MI to access PostgreSQL, ensuring proper security isolation.

## Prerequisites


- [Azure CLI](https://docs.microsoft.com/en-us/cli/azure/install-azure-cli)  
- [Docker Desktop](https://www.docker.com/products/docker-desktop)  
- [PostgreSQL Client](https://www.postgresql.org/download/)  
- Azure Database for PostgreSQL Flexible Server

## Getting Started

### Step 1: Verify PostgreSQL Connection

Connect locally before deploying the MCP server:

1. Navigate to your PostgreSQL server in the Azure portal
2. Follow the steps in the **Connect** section to set up Microsoft Entra ID authentication
3. Connect using `psql`:

![PostgreSQL Connection](images/PostgreSQL_Connect.png)

4. Launch the PostgreSQL client:
```bash
psql
```

5. Inside `psql`, run:
```sql
\conninfo
```

You should see output similar to:
![Local PostgreSQL Connection](images/PostgreSQL_Local_Connect.png)

### Step 2: (Server) Deploy Azure MCP PostgreSQL Server to Azure Container App

1. Start Docker  
2. Login to Azure:
   ```bash
   az login
   az account set --subscription "your-subscription-id"
   ```
3. Run deployment script:
   ```bash
   chmod +x scripts/deploy-azmcp-postgres-server.sh 
   ./scripts/deploy-azmcp-postgres-server.sh --postgres-resource-id "/subscriptions/{sub}/resourceGroups/{rg}/providers/Microsoft.DBforPostgreSQL/flexibleServers/{server}" --resource-group "{rg-for-mcp-server-aca}"
   ```

<details>
<summary>Example Output (deployment-info.json)</summary>
<br/>

The script creates a `deployment-info.json` file with all the deployment details:

```json
{
   "MCP_SERVER_URI": "https://<mcp-server-uri>",
   "ENTRA_APP_CLIENT_ID": "<entra-app-client-id>",
   "ENTRA_APP_OBJECT_ID": "<entra-app-object-id>",
   "ENTRA_APP_SP_OBJECT_ID": "<entra-app-sp-object-id>",
   "ENTRA_APP_ROLE_VALUE": "<entra-app-role-value>",
   "ENTRA_APP_ROLE_ID_BY_VALUE": "<entra-app-role-id-by-value>",
   "ACA_MI_PRINCIPAL_ID": "<aca-mi-principal-id>",
   "ACA_MI_DISPLAY_NAME": "<aca-mi-display-name>",
   "RESOURCE_GROUP": "<resource-group>",
   "SUBSCRIPTION_ID": "<subscription-id>",
   "POSTGRES_SERVER_NAME": "<postgres-server-name>",
   "POSTGRES_RESOURCE_GROUP": "<postgres-resource-group>",
   "LOCATION": "<location>"
}
```

</details>

### Step 3: Configure PostgreSQL Database Access

In `psql` terminal (from Step 1):

```sql
SELECT * FROM pgaadauth_create_principal('<ACA_MI_DISPLAY_NAME>', false, false);
```

Replace `<ACA_MI_DISPLAY_NAME>` with the value from `deployment-info.json` (output of step 2) (e.g., `azure-mcp-postgres-server`).

### Step 4a: Create AI Foundry Connection
Use the REST API to create a connections

[INFO] Only works in UAE North Region

```bash
PUT https://{{ _.region }}.management.azure.com:443/subscriptions/{{ _.subscriptionID }}/resourcegroups/{{ _.resourceGroup }}/providers/Microsoft.CognitiveServices/accounts/{{ _.account }}/projects/{{ _.project }}/connections/{{ _.connectionName }}?api-version=2025-04-01-preview
{
  "tags": null,
  "location": null,
  "name": "{connection-name}",
  "type": "Microsoft.MachineLearningServices/workspaces/connections",
  "properties": {
    "authType": "ProjectManagedIdentity",
    "group": "ServicesAndApps",
    "category": "RemoteTool",
    "expiryTime": null,
    "target": "{ $MCP_SERVER_URI }",
    "isSharedToAll": true,
    "sharedUserList": [],
  "audience": "{ $ENTRA_APP_CLIENT_ID }",
    "Credentials": {
    },
    "metadata": {
      "ApiType": "Azure"
    }
  }
}
```

### Step 4b: (Client) Configure AI Foundry Connection

Assign the correct permissions to AI Foundry connection.

```bash
chmod +x scripts/create-aif-mi-connection-assign-role.sh
./scripts/create-aif-mi-connection-assign-role.sh \
  --ai-foundry-project-resource-id "/subscriptions/{sub}/resourceGroups/{rg}/providers/Microsoft.CognitiveServices/accounts/{ai-foundry-resource-name}/projects/{ai-foundry-project-name}" \
  --connection-name "{connection-name}"
```

<details>
<summary>Example Output of the script</summary>

The script will output properties of the AI Foundry resource and connection that was connected:

```json
{
  "AI_FOUNDRY_PROJECT_RESOURCE_ID": "/subscriptions/{subscription-id}/resourceGroups/{resource-group}/providers/Microsoft.CognitiveServices/accounts/{ai-foundry-account-name}/projects/{ai-foundry-project-name}",
  "AI_FOUNDRY_SUBSCRIPTION_ID": "{subscription-id}",
  "AI_FOUNDRY_RESOURCE_GROUP": "{resource-group}",
  "AI_FOUNDRY_ACCOUNT_NAME": "{ai-foundry-account-name}",
  "AI_FOUNDRY_PROJECT_NAME": "{ai-foundry-project-name}",
  "AI_FOUNDRY_REGION": "{region}",
  "AI_FOUNDRY_PROJECT_MI_PRINCIPAL_ID": "{managed-identity-principal-id}",
  "AI_FOUNDRY_PROJECT_MI_TYPE": "SystemAssigned",
  "AI_FOUNDRY_PROJECT_MI_TENANT_ID": "{tenant-id}",
  "AI_FOUNDRY_PROJECT_MI_CONNECTION_NAME": "{connection-name}",
  "AI_FOUNDRY_PROJECT_MI_CONNECTION_TARGET": "https://{mcp-server-uri}",
  "AI_FOUNDRY_PROJECT_MI_CONNECTION_AUDIENCE": "{entra-app-client-id}"
}
```

</details>

### Step 5: Test in AI Foundry
[NOTE] Azure MCP server will not return values in the vector column. You can still do vector search, You just can return ve tor values in your results.

## Appendix

### AI Foundry Project Managed Identity Authentication Flow [Needs to be updated]

For detailed information about how AI Foundry projects will authenticate to Azure MCP servers using managed identity, including SDK usage patterns and sequence diagrams, see: [AI Foundry Project Managed Identity Server Authentication](https://gist.github.com/anuchandy/0726a2565431aaa46616c55830dda241).

### Architecture Diagram [Needs to be updated]

<details>
<summary>Architecture diagram</summary>

![Architecture Diagram](images/AIFountry_AzMcpPostgresServer_PostgresDB.png)

</details>