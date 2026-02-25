# Azure MCP PostgreSQL Server Demo

This is a demo repo that will show you how to setup the **Azure Database for Postgres MCP server** that enables AI agents to interact with Azure PostgreSQL databases through natural language queries. Supports SQL operations, schema discovery, and data analysis with enterprise-grade security.

This server is a part of the **[Azure MCP Server](https://learn.microsoft.com/en-us/azure/developer/azure-mcp-server/)**. This repo will show you how to enable the Postgres specific features and how to connect it to your **Foundry** project via MCP

## Features

- 🔍 **SQL Operations** - Execute queries, manage data, perform analytics
- 📊 **Schema Discovery** - Automatic table and column analysis
- 🔐 **Enterprise Security** - Azure managed identity and Entra ID authentication  
- 🎯 **Natural Language** - Query databases using conversational AI
- 🚀 **Easy Deployment** - One-click Azure deployment with complete infrastructure

## Components

The system consists of three main components:

1. **Foundry Agent** (Client): Authenticates to the Azure MCP Server using its Managed Identity.  

2. **Azure MCP PostgreSQL Server** (Server): Runs in Azure Container Apps (ACA), using ACA Managed Identity for PostgreSQL access.

3. **PostgreSQL Database** (Target): Azure Database for PostgreSQL Flexible Server with Entra ID authentication enabled.

**Identity Separation**: Two separate managed identities are used - the client MI (Foundry) authenticates to the MCP Server, while the MCP Server uses its own ACA MI to access PostgreSQL, ensuring proper security isolation.

## Prerequisites

- [Azure CLI](https://docs.microsoft.com/en-us/cli/azure/install-azure-cli)  
- [PostgreSQL Client](https://www.postgresql.org/download/)  
- [Azure Database for PostgreSQL Flexible Server](https://learn.microsoft.com/en-us/azure/postgresql/flexible-server/overview)

## Quick start deployment

Deploy the complete Azure MCP PostgreSQL Server infrastructure by using Azure Developer CLI (azd):

### Step 1: Deploy with azd up
The fastest way to get started is by using the automated deployment script. 

1. First, clone [the repo](https://github.com/Azure-Samples/azure-postgres-mcp-demo):

    ```bash
    # Clone the repository
    git clone https://github.com/Azure-Samples/azure-postgres-mcp-demo
    cd azure-postgres-mcp-demo
    ```

2. Open [infra/main.parameters.json](/infra/main.parameters.json) and update these 2 values 
   
    | Parameter              | Description                                                                             |
    | ---------------------- | --------------------------------------------------------------------------------------- |
    | `postgresResourceId`   | Resource ID of the Azure Database for PostgreSQL Flexible Server you want to connect to |
    | `aifProjectResourceId` | Resource ID of the Azure Foundry project you want to use                             |

    a. Update the [`postgresResourceId`](https://github.com/Azure-Samples/azure-postgres-mcp-demo/blob/1f94c56bdd8ab4b383fdfc8eac23b05db2c4b09f/infra/main.parameters.json#L17) variable to match the Postgres DB you want to access. 
    
    ```json
    "postgresResourceId": {
      "value": "/subscriptions/<subscription-id>/resourceGroups/<postgres-resource-group>/providers/Microsoft.DBforPostgreSQL/flexibleServers/<postgres-server-name>"
    }
    ```
    > Find your **Azure Database for PostgreSQL** Resource ID in your Azure portal.  **JSON View** → **Resource ID**:
    ![Screenshot of Azure details page.](images/azure_json_view.png)

    b. Update the [`aifProjectResourceId`](https://github.com/Azure-Samples/azure-postgres-mcp-demo/blob/1f94c56bdd8ab4b383fdfc8eac23b05db2c4b09f/infra/main.parameters.json#L20) variable to match the Foundry project resource you want to use
    ```json
    "aifProjectResourceId": {
      "value": "/subscriptions/<subscription-id>/resourceGroups/<aifoundry-resource-group>/providers/Microsoft.CognitiveServices/accounts/<aifoundry-resource-name>/projects/<aifoundry-project-name>"
    }
    ```
    > Find your **Foundry project** Resource ID in your Azure portal.  **JSON View** → **Resource ID**:
    ![Screenshot of Azure details page.](images/azure_json_view_aif.png)

3. Log into Azure CLI and Azure Developer CLI with the appropriate Azure account/subscription before deploying the MCP server
   
   ```bash
    az login
   ```
   ```bash
   azd auth login
   ```

4. Create a new azd environment and deploy. Make sure you are in the main directory (`azure-postgres-mcp-demo`):

    ```bash
    azd env new
    ```
    ```bash
    azd up
    ```

    The deployment **usually takes 1-2 mins**. After deployment completes, azd will output the MCP server URL + Managed Identity info you'll use in the next steps.

This deployment creates:
- Azure Container App running the MCP server with Managed Identity (Reader access to your PostgreSQL server)
- Entra ID App Registration for MCP server authentication
- Entra ID Role assignment for Foundry to authenticate to the MCP server

![Screenshot of Azure Portal components](images/azure-portal-resources.png)


### Step 2: Configure database access
1. Connect to your PostgreSQL server using `psql` or your preferred PostgreSQL client:

    Set the following environment variables by copying and pasting the lines below into your bash terminal (WSL, Azure Cloud Shell, etc.). Find details for your connection in the **Connect** Tab in your Postgres Resource in the Azure Portal:
   
   ![Connect Tab](images/azure-postgres-connect.png)

   ```bash
   export PGHOST=<your-database-host-name>
   export PGUSER=<your-admin-username>
   export PGPORT=5432
   export PGDATABASE=<your-database-name>
   export PGPASSWORD="$(az account get-access-token --resource https://ossrdbms-aad.database.windows.net --query accessToken --output tsv)" 
   ```

   Then run:
   ```bash
   psql
   ```

   Alternatively, you can connect via the [PostgreSQL VS Code Extension](https://learn.microsoft.com/en-us/azure/postgresql/extensions/vs-code-extension/quickstart-connect#add-a-connection-to-postgresql)

   > **Note:** If you use the PostgreSQL VS Code Extension, make sure to authenticate using **Entra ID** to your database before running any of the following SQL commands.

2. Create the database principal for the MCP server's managed identity, only run this command in the **default postgres database**, the command is only allowed in this database:

    ```sql
    SELECT * FROM pgaadauth_create_principal('<CONTAINER_APP_IDENTITY_NAME>', false, false);
    ```

    Replace `<CONTAINER_APP_IDENTITY_NAME>` (e.g., `azmcp-postgres-server-nc3im7asyw`).

    >  **Note:** Use `azd env get-values` command to find the `CONTAINER_APP_IDENTITY_NAME` value, or any other enviromental variable.

3. If you add new tables to your database, you will have to grant the MCP server permissions to the new tables. Make sure you run this command in the **correct database** your tables are located in.
   
   ```sql
   GRANT SELECT ON my_table TO "<CONTAINER_APP_IDENTITY_NAME>";
   ```

    For all tables
    ```sql
    -- Grant SELECT on all existing tables
    GRANT SELECT ON ALL TABLES IN SCHEMA public TO "<CONTAINER_APP_IDENTITY_NAME>";

    -- Grant SELECT on all future tables
    ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT SELECT ON TABLES TO "<CONTAINER_APP_IDENTITY_NAME>";
    ```
    > Note: if you have tables in a schema other than "public" run these two same commands again, but with your additional schema names.  For example:

    For all tables, in an additonal schema
    ```sql
    -- Grant SELECT on all existing tables
    GRANT SELECT ON ALL TABLES IN SCHEMA test_case_schema TO "<CONTAINER_APP_IDENTITY_NAME>";

    -- Grant SELECT on all future tables
    ALTER DEFAULT PRIVILEGES IN SCHEMA test_case_schema GRANT SELECT ON TABLES TO "<CONTAINER_APP_IDENTITY_NAME>";
    ```


## Configure Foundry integration

After you deploy your MCP server, connect it to the Foundry:

### Connect via Foundry portal

1. Go to the [Azure Portal](https://portal.azure.com)
1. Navigate to your Azure Foundry instance
1. Click "Go to Foundry portal" button
1. In the Foundry portal, go to **Start building** → **Create agent**  
1. Name your agent something like `postgres-mcp-agent`
1. In the Tools section, select the **Add** → **Add a new tool**  
1. Select the **Catalog** tab 
1. Choose **Azure Database for PostgreSQL** as the tool and click **Create** ![Find Postgres Tool](images/ai-foundry-add-postgres-db-mcp.png)
1. Click **Connect tool with endpoint**
1. Enter the `CONTAINER_APP_URL` value as the Remote MCP Server endpoint. This is value is from the output of the `azd env get-values` command. 
1. Select **Microsoft Entra** → **Project Managed Identity**  as the authentication method ![Connect via Entra](images/ai-foundry-postgres-tool-catalog.png)
1. Enter the value of the <entra-app-client-id> enviromental variable as the audience. This is value from the output of the `azd env get-values`command. 

>  **Note:** Remember, use `azd env get-values` command to find the `ENTRA_APP_CLIENT_ID` value and `CONTAINER_APP_URL`

1. Click "Save" button to save your progress on the agent creation
1. Add instructions to your agent. ![Agent Instructions](images/agent_instructions_playground.png)
   
    Give the agent instructions:

    ```
    You are a helpful agent that can use MCP tools to assist users. Use the available MCP tools to answer questions and perform tasks.
    "parameters":      
      {
            "database": "<DATABASE_NAME>",
            "resource-group": "<RESOURCE_GROUP>",
            "server": "<SERVER_NAME>",
            "subscription": "<SUBSCRIPTION_ID>",
            "table": "<TABLE_NAME>",
            "user": "<CONTAINER_APP_NAME>",       
      }
    ```
1. **Important:** Click "Save" button again, to save your progress on the agent creation

> **Note:** The resource group is the one which contains your Azure PostgreSQL database.  If you deployed the MCP Server container apps into a different resource group, that is fine.  For the above, still use the name of the resource group which contains your Azure PostgreSQL database.

> **Note:** There is a single field for "table" in these instructions.  If you chose to allow permissions on all tables, this will be ignored and you will gain access to all tables in the schema you granted permissions on.

### Test the integration

After you connect, test your MCP integration with natural language queries.

You can discover tables.

```copilot-prompt
List all tables in my PostgreSQL database
```

You can retrieve records with natural language.

```copilot-prompt
Show me the latest 10 records from the orders table
```

```copilot-prompt
Find customers who placed orders in the last 30 days
```

You can do vector search and specify example queries to improve accuracy.

```copilot-prompt
Do a vector search for "product for customer that love to hike"

This is an example of a vector search.

`SELECT id, name, price, embedding <=> azure_openai.create_embeddings(
'text-embedding-3-small',
'query example'
)::vector AS similarity
FROM public.products
ORDER BY similarity
LIMIT 10;
```

The AI agent automatically translates these requests into appropriate database operations through the MCP server.

### Connect via Azure Foundry SDK

For programmatic access, use the following MCP configuration in your Python code:

1. Create a `.env` file from the [`.env.example`](client/.env.example):
   ```
   cd client
   cp .env.example .env
   ```

2. Update all the value to run your agent. All values can be found in your Foundry Project.

    | Variable Name | Example Value | Description |
    |---------------|---------------|-------------|
    | `PROJECT_ENDPOINT` | `https://example-endpoint.services.ai.azure.com/api/projects/example-project` | Foundry project endpoint |
    | `MODEL_DEPLOYMENT_NAME` | `example-model` | Name of the deployed AI model |
    | `MCP_SERVER_URL` | `https://example-mcp-server.azurecontainerapps.io` | MCP server endpoint URL |
    | `MCP_SERVER_LABEL` | `example-label` | Label for the MCP server |
    | `AZURE_OPENAI_API_KEY` | `your-azure-openai-api-key` | Azure OpenAI service API key |
    | `AZURE_OPENAI_ENDPOINT` | `https://example-openai-endpoint.openai.azure.com/` | Azure OpenAI service endpoint |
    | `AZURE_OPENAI_API_VERSION` | `your-api-version` | API version for Azure OpenAI |
    | `AZURE_SUBSCRIPTION_ID` | `your-azure-subscription-id` | Azure subscription identifier |
    | `CONNECTION_NAME` | `your-connection-name` | Name for the database connection |
    | `POSTGRES_SERVER` | `your-postgres-server` | PostgreSQL server name |
    | `POSTGRES_DATABASE` | `your-postgres-database` | PostgreSQL database name |
    | `POSTGRES_TABLE` | `your-postgres-table` | Target PostgreSQL table |
    | `POSTGRES_USER` | `your-postgres-user` | PostgreSQL user for authentication, use CONTAINER_APP_NAME here|
    | `AZURE_RESOURCE_GROUP` | `your-azure-resource-group` | Azure resource group name |

[Full SDK sample](client/agents_mcp_sample.py) in the the client folder 

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
ping https://your-mcp-server.azurecontainerapps.io
```

If MCP is up and running: 

```
64 bytes from X.XXX.XXX.X: icmp_seq=0 ttl=108 time=92.748 ms
```

If MCP is *not running*:
```
ping: cannot resolve https://your-mcp-server.azurecontainerapps.io: Unknown host
```
You will need to re-run `azd up`.

### Common Issues

#### Cannot validate Microsoft Entra ID ... name isn't unique in the tenant
- **Error**: Someone in your tenant already deployed a Postgres MCP server with the name `azure-mcp-postgres-server`
    ```sql
    postgres=> SELECT * FROM pgaadauth_create_principal('azure-mcp-postgres-server', false, false);
    ERROR:  Cannot validate Microsoft Entra ID user "azure-mcp-postgres-server" because its name isn't unique in the tenant.
    Make sure it's correct and retry.
    CONTEXT:  SQL statement "SECURITY LABEL for "pgaadauth" on role "azure-mcp-postgres-server" is 'aadauth'"
    PL/pgSQL function pgaadauth_create_principal(text,boolean,boolean) line 23 at EXECUTE
    ```
- **Solution**: Update the acaName in [infra/main.parameter.json](https://github.com/Azure-Samples/azure-postgres-mcp-demo/blob/89c6f3692dca0b7b70267c55ba12f2b96b90448e/infra/main.parameters.json#L12) to a different name, and rerun deployment with `azd up`
  
#### Authentication Errors
- **Error**: `Unauthorized` or `Forbidden`
- **Solution**: Verify managed identity configuration and PostgreSQL access permissions

#### Connection Issues
- **Error**: `Connection timeout` or `Cannot connect to server`
- **Solution**: Check PostgreSQL firewall rules and network configuration

#### Permission Errors
- **Error**: `Permission denied for relation`
- **Solution**: Ensure the managed identity has appropriate database permissions

```sql
GRANT SELECT ON my_table TO "<CONTAINER_APP_NAME>";
```

### Debug Mode

#### View Logs
```bash
# Stream Container Apps logs
az containerapp logs show -n your-mcp-container-name -g your-resource-group

# Check deployment status
az containerapp show -n your-mcp-container-name -g your-resource-group
```

## Security Considerations

⚠️ **IMPORTANT SECURITY NOTICE**

This MCP server uses Entra ID and Managed Identity for secure PostgreSQL access:

### Data Access and Exposure
- **Any data accessible to this MCP server can potentially be exposed to connected AI agents**
- The MCP server can execute SQL queries on accessible databases and tables
- Connected agents may request and receive data through natural language queries

### Security features
You can use the following [security features](security-overview.md#access-control) to protect your data:

- **Managed Identity**: No credentials stored in container images.
- **Microsoft Entra ID Authentication**: Secure database authentication.
- **RBAC**: Role-based access control for database operations.
- **Row Level Security**: Fine-grained access control at the row level.

### Best practices
- **Grant database permissions ONLY to specific schemas and tables** needed for AI agents
- Use principle of least privilege - don't grant broad database access
- Regularly review and audit permissions granted to the MCP server's identity
- Consider using dedicated databases or schemas for AI agent access
- Start with a dedicated test database containing only non-sensitive sample data.

## Appendix

### Foundry Project Managed Identity Authentication Flow [Needs to be updated]

For detailed information about how Foundry projects will authenticate to Azure MCP servers using managed identity, including SDK usage patterns.

### Technical Details
The Azure Postgres MCP server is a subset of the [Azure MCP Server](https://github.com/microsoft/mcp/tree/main/servers/Azure.Mcp.Server).

## Additional Resources

- **[Azure Container Apps Documentation](https://docs.microsoft.com/azure/container-apps/)**
- **[Azure MCP Server](https://learn.microsoft.com/en-us/azure/developer/azure-mcp-server/)**
- **[Azure Database for PostgreSQL Documentation](https://docs.microsoft.com/azure/postgresql/)**
- **[Model Context Protocol Specification](https://spec.modelcontextprotocol.io/)**
- **[Foundry Documentation](https://docs.microsoft.com/azure/ai-foundry/)**


## Contributing

### Development Workflow
1. **Fork and clone** the repository
2. **Create feature branch** from `main`
3. **Deploy to test environment**
4. **Submit pull request** with comprehensive testing

If you want to contribute to the Azure MCP server wich includes teh Azure Postgres MCP follow the [Contribution Guide](https://github.com/microsoft/mcp/blob/main/CONTRIBUTING.md)

## Support

- **Issues**: GitHub Issues with logs and configuration details
- **Monitoring**: Azure Container Apps logs and Application Insights