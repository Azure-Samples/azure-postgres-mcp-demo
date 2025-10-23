# Azure MCP PostgreSQL Server Demo

This is a demo repo that will show you how to setup the **Azure Database for Postgres MCP server** that enables AI agents to interact with Azure PostgreSQL databases through natural language queries. Supports SQL operations, schema discovery, and data analysis with enterprise-grade security.

This server is a part of the **[Azure MCP Server](https://learn.microsoft.com/en-us/azure/developer/azure-mcp-server/)**. This repo will show you how to enable the Postgres specific features and how to connect it **Azure AI Foundry** and other MCP clients to interact with Azure Database for Postgres via MCP

## Features

- 🔍 **SQL Operations** - Execute queries, manage data, perform analytics
- 📊 **Schema Discovery** - Automatic table and column analysis
- 🔐 **Enterprise Security** - Azure managed identity and Entra ID authentication  
- 🐳 **Production Ready** - Containerized deployment to Azure Container Apps
- 🎯 **Natural Language** - Query databases using conversational AI
- 🚀 **Easy Deployment** - One-click Azure deployment with complete infrastructure **[Coming Soon]**

## Components

The system consists of three main components:

1. **AI Foundry Agent** (Client): Authenticates to the Azure MCP Server using its Managed Identity.  

2. **Azure MCP PostgreSQL Server** (Server): Runs in Azure Container Apps (ACA), using ACA Managed Identity for PostgreSQL access.

3. **PostgreSQL Database** (Target): Azure Database for PostgreSQL Flexible Server with Entra ID authentication enabled.

**Identity Separation**: Two separate managed identities are used - the client MI (AI Foundry) authenticates to the MCP Server, while the MCP Server uses its own ACA MI to access PostgreSQL, ensuring proper security isolation.

## Prerequisites

- [Azure CLI](https://docs.microsoft.com/en-us/cli/azure/install-azure-cli)  
- [Docker Desktop](https://www.docker.com/products/docker-desktop)  
- [PostgreSQL Client](https://www.postgresql.org/download/)  
- [Azure Database for PostgreSQL Flexible Server](https://learn.microsoft.com/en-us/azure/postgresql/flexible-server/overview)

## Quick Start

### Deploy MCP Server via Azure Button (Recommended)

**Prerequisites Check**: Ensure you have an Azure PostgreSQL Flexible Server with Entra ID authentication enabled.

[![Deploy to Azure](https://aka.ms/deploytoazurebutton)](https://portal.azure.com/#create/Microsoft.Template/uri/https%3A%2F%2Fraw.githubusercontent.deploy-all-resources.json)

### Deploy to Azure via azd up
Deploy the complete infrastructure with a single script:
```bash
azd up
```
**What gets deployed:** Azure Container Apps, Managed Identity, Entra ID App Registration with full RBAC setup.

### Deploy manually
In case azd up or one click deploy failed. You can set up manually. In the [detailed Setup](#detailed-setup) sections

### 🌐 Test MCP server
Test the MCP immediately using the web interface:

**Deployed UI:** [URL]

The UI allows you to:

* Check server health status
* List available MCP tools
* Test tools with interactive parameter input
* View formatted JSON responses
* Explore all MCP tools

### Add Azure Postgres MCP URI to AI Foundry

**Via Azure AI Foundry UI:**

In AI Foundry , go to `/build/tools -> connect a tool -> custom tab -> MCP and you can select "project managed identity" `

![Connect via Entra](images/AI_Foundry_Entra_Connect.png)

Give the agent instrucitons:

```
You are a helpful agent that can use MCP tools to assist users. Use the available MCP tools to answer questions and perform tasks.
"parameters":      
  {
        "database": "<DATABASE_NAME>",
        "resource-group": "<RESOURCE_GROUP>",
        "server": "<SERVER_NAME>",
        "subscription": "<SUBSCRIPTION_ID>",
        "table": "<TABLE_NAME>",
        "user": "<ACA_MI_DISPLAY_NAME>",       
  },
"learn": true
```

Test MCP server in AI Foundry Playground using natural language queries:

```
List all tables in my PostgreSQL database
```

```
Show me the latest 10 records from the orders table
```

```
What's the schema of the customers table?
```

**Via AI Foundry SDK:**

In your SDK code, add the following MCP config to test

``` python
mcp_tool_config = {
    "type": "mcp",
    "server_url": <mcp_server_url>,
    "server_label": <mcp_server_label>,
    "server_authentication": {
        "type": "connection",
        "connection_name": <connection_name>,
    }
}

mcp_tool_resources = {
    "mcp": [
        {
            "server_label": <mcp_server_label>,
            "require_approval": "never"
        }
    ]
}
```

[Full SDK sample](client/agents_mcp_sample.py) in the the client folder 

## Detailed Setup

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

## Setting Up with Azure AI Foundry
### Step 1: Create AI Foundry Connection [TBD]
Use the REST API to create a connections

>[!IMPORTANT] Only works in UAE North Region

<details>
<summary>Creating connection with REST API</summary>
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
</details>


In AI Foundry , go to `/build/tools -> connect a tool -> custom tab -> MCP and you can select "project managed identity" `

![Connect via Entra](images/AI_Foundry_Entra_Connect.png)


### Step 2: (Client) Configure AI Foundry Connection

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

### Step 3: Test in AI Foundry

Test your MCP server connection in AI Foundry Playground using natural language queries:

```
List all tables in my PostgreSQL database
```
```
Show me the latest 10 records from the orders table
```
```
What's the schema of the customers table?
```

> **Note**: The MCP server provides secure access to PostgreSQL data through conversational AI interfaces.


## Example Queries

#### Basic Database Operations
```
List all tables in the database
```
```
Show the schema for the 'customers' table  
```
```
Get the first 10 rows from the 'orders' table
```
```
Count total records in the 'products' table
```

#### Data Analysis
```
Find customers who placed orders in the last 30 days
```
```
Show me the top 5 best-selling products by quantity
```
```
Calculate average order value by customer segment
```
```
Analyze sales trends by month for this year
```

#### Schema Exploration
```
What tables are available in this database?
```
```
Describe the relationship between orders and customers tables
```
```
Show me all foreign key constraints in the database
```
```
Find tables that contain customer information
```


## Configuration

### Environment Variables

#### Client Configuration (.env file)
| Variable | Required | Description | Example |
|----------|----------|-------------|---------|
| `PROJECT_ENDPOINT` | Yes | AI Foundry project endpoint | `https://example-endpoint.services.ai.azure.com/api/projects/example-project` |
| `MODEL_DEPLOYMENT_NAME` | Yes | AI model deployment name | `gpt-4o` |
| `MCP_SERVER_URL` | Yes | MCP server endpoint URL | `https://example-mcp-server.azurecontainerapps.io` |
| `MCP_SERVER_LABEL` | Yes | Label for the MCP server | `azure-postgres-mcp` |
| `AZURE_OPENAI_API_KEY` | Yes* | Azure OpenAI API key | `your-azure-openai-api-key` |
| `AZURE_OPENAI_ENDPOINT` | Yes* | Azure OpenAI service endpoint | `https://example-openai-endpoint.openai.azure.com/` |
| `AZURE_OPENAI_API_VERSION` | Yes* | Azure OpenAI API version | `2024-02-01` |

*Either use API key or managed identity authentication

#### Sample .env file
Check [.env.example](client/.env.example)

### Authentication & Security

#### Azure Deployment
Uses managed identity with these permissions:
- **PostgreSQL Database Contributor** role on the target PostgreSQL server
- **Entra ID Authentication** for secure database access

## Troubleshooting

### Health Check
```bash
# Check MCP server status
curl https://your-mcp-server.azurecontainerapps.io/health
```

### Common Issues

#### Authentication Errors
- **Error**: `Unauthorized` or `Forbidden`
- **Solution**: Verify managed identity configuration and PostgreSQL access permissions

#### Connection Issues
- **Error**: `Connection timeout` or `Cannot connect to server`
- **Solution**: Check PostgreSQL firewall rules and network configuration

#### Permission Errors
- **Error**: `Permission denied for relation`
- **Solution**: Ensure the managed identity has appropriate database permissions

### Debug Mode

#### View Logs
```bash
# Stream Container Apps logs
az containerapp logs tail --name your-mcp-server --resource-group your-resource-group

# Check deployment status
az containerapp show --name your-mcp-server --resource-group your-resource-group
```

## Security Considerations

⚠️ **IMPORTANT SECURITY NOTICE**

This MCP server uses Entra ID and Managed Identity for secure PostgreSQL access:

### Data Access and Exposure
- **Any data accessible to this MCP server can potentially be exposed to connected AI agents**
- The MCP server can execute SQL queries on accessible databases and tables
- Connected agents may request and receive data through natural language queries

### Security Features
- ✅ **Managed Identity**: No credentials stored in container images
- ✅ **Entra ID Authentication**: Secure database authentication
- ✅ **HTTPS-only**: All external traffic uses TLS encryption
- ✅ **Network Isolation**: Container Apps with restricted ingress
- ✅ **RBAC**: Role-based access control for database operations

### Access Control Requirements
- **Grant database permissions ONLY to specific schemas and tables** needed for AI agents
- Use principle of least privilege - don't grant broad database access
- Regularly review and audit permissions granted to the MCP server's identity
- Consider using dedicated databases or schemas for AI agent access

**Recommendation**: Start with a dedicated test database containing only non-sensitive sample data.

## Appendix

### AI Foundry Project Managed Identity Authentication Flow [Needs to be updated]

For detailed information about how AI Foundry projects will authenticate to Azure MCP servers using managed identity, including SDK usage patterns.

### Technical Details
The Azure Postgres MCP server is a subset of the [Azure MCP Server](https://github.com/microsoft/mcp/tree/main/servers/Azure.Mcp.Server).

### Architecture Diagram

<details>
<summary>Architecture diagram</summary>

![Architecture Diagram](images/arch_flow_chart.png)

</details>

## Additional Resources

- **[Azure Container Apps Documentation](https://docs.microsoft.com/azure/container-apps/)**
- **[Azure MCP Server](https://learn.microsoft.com/en-us/azure/developer/azure-mcp-server/)**
- **[Azure Database for PostgreSQL Documentation](https://docs.microsoft.com/azure/postgresql/)**
- **[Model Context Protocol Specification](https://spec.modelcontextprotocol.io/)**
- **[AI Foundry Documentation](https://docs.microsoft.com/azure/ai-foundry/)**


## Contributing

### Development Workflow
1. **Fork and clone** the repository
2. **Create feature branch** from `main`
3. **Test locally** using Docker
4. **Deploy to test environment**
5. **Submit pull request** with comprehensive testing

If you want to contribute to the Azure MCP server wich includes teh Azure Postgres MCP follow the [Contribution Guide](https://github.com/microsoft/mcp/blob/main/CONTRIBUTING.md)

## Support

- **Health**: `GET /health` endpoint for server status
- **Issues**: GitHub Issues with logs and configuration details
- **Monitoring**: Azure Container Apps logs and Application Insights

## Troubleshooting

MCP not reading  tables that exist.
```
GRANT SELECT ON my_table TO "azure-mcp-postgres-server";
```