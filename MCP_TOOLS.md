# Azure Postgres MCP Tools Documentation

This document provides examples of available MCP tools for Azure Postgres, their input schemas, expected output formats and example prompts.

---

## Table of Contents

- [Database](#database)
  - [List databases](#database-list-databases)
  - [Execute database query](#database-execute-database-query)
- [Table](#table)
  - [List tables](#table-list-tables)
  - [Get table schema](#table-get-table-schema)
- [Server](#server)
  - [List servers](#server-list-servers)
  - [Get server configuration](#server-get-server-configuration)
  - [Get server parameter](#server-get-server-parameter)
  - [Set server parameter](#server-set-server-parameter)

---

## Database

### Database: list databases

Description
- Lists all databases on a specified Postgres server that the caller (user/principal) can access. Useful to discover which databases are available for MCP operations and to verify whether required extensions (for example pg_diskann or pgvector) are present. Returns a simple array of database names.

Notes: the caller's role and Azure RBAC may limit results; subscription and resource-group scope determine which servers are visible.

**Tool Input**
```json
{
  "command": "postgres_list_databases",
  "intent": "list all databases with pg_diskann extension installed for user",
  "parameters": {
    "user": "mcp-identity",
    "resource-group": "abeomor",
    "server": "diskannga",
    "subscription": "OrcasPM"
  }
}
```
**Example Prompt**
```
List all databases on my postgres server

{
  "command": "postgres_list_databases",
  "user": "mcp-identity",
  "resource-group": "abeomor",
  "server": "diskannga",
  "subscription": "OrcasPM"
}
```

**Output Schemas**
```json
{
  "status": 200,
  "message": "Success",
  "results": {
    "Databases": [
      "azure_maintenance",
      "postgres",
      "azure_sys",
      "build_2025",
      "nlweb_db",
      "cases",
      "cps",
      "copilot_test",
      "nlweb_db_2"
    ]
  },
  "duration": 0
}
```


**Remote MCP Server URL**  
`LOCAL, generate when user deploys`

[🔝 Back to Top](#table-of-contents)

---

### Database: execute database query

Description
- Executes an arbitrary SQL query against a specified database and returns the raw query results. This is the general-purpose tool for checks, diagnostics, running vector search SQL, or validating extensions.

Caveats #1: queries that select custom vector types (for example `public.vector` or the `vector` type from `pgvector`) may not deserialize in the MCP transport; in those cases exclude the vector column or cast it to text. 
Caveats #2: Ensure the caller has appropriate permissions and RLS policies won't block the query.

**Tool Input**
```json
{
  "command": "postgres_database_query",
  "intent": "check if pg_diskann extension is installed in database azure_maintenance",
  "parameters": {
    "database": "nlweb_db_2",
    "query": "SELECT extname FROM pg_extension WHERE extname = 'pg_diskann'",
    "resource-group": "abeomor",
    "server": "diskannga",
    "subscription": "OrcasPM",
    "user": "mcp-identity"
  }
}
```

**Output Schemas**
```json
{
  "status": 200,
  "message": "Success",
  "results": {
    "QueryResult": ["extname", "pg_diskann"]
  },
  "duration": 0
}
```

**Example Prompt**
```
Do a vector search for "Talks about AI" on my postgres database

{
"command";"postgres_database_query"
"database": "nlweb_db_2",
"resource-group": "abeomor",
"server": "diskannga",
"subscription": "5c5037e5-d3f1-4e7b-b3a9-f6bf94902b30",
"table": "documents",
"user": "mcp-identity"
}

this is a vector search example.
SELECT id, name, price, brand, embedding <=> azure_openai.create_embeddings(
'text-embedding-3-small',
'query example'
)::vector AS similarity
FROM public.products
ORDER BY similarity
LIMIT 10;
```


**Remote MCP Server URL**  
`LOCAL, generate when user deploys`

**Permissions**
You can active READ-ONLY operation with RLS policies on Postgres to stop agent from write malicious code.
![Postgres agent permission not granted](postgres_agent_permission_no_granted.png)

Example: 
Write a random row to the documents_no_vector table in my Postgres Database

{
"command";"postgres_database_query"
"database": "nlweb_db_2",
"resource-group": "abeomor",
"server": "diskannga",
"subscription": "5c5037e5-d3f1-4e7b-b3a9-f6bf94902b30",
"table": "documents_no_vector",
"user": "mcp-identity"
}

[🔝 Back to Top](#table-of-contents)

---

## Table

### Table: list tables

Description
- Returns a list of table names in the target database (typically scoped to the `public` schema unless otherwise specified). Use this to enumerate tables for downstream operations such as schema discovery or data queries.

Notes: results are filtered by the caller's database privileges; tables hidden by RLS or ownership restrictions may not be visible.

**Tool Input**
```json
{
  "command": "postgres_list_tables",
  "intent": "list all tables in the specified database",
  "parameters": {
    "database": "nlweb_db_2",
    "resource-group": "abeomor",
    "server": "diskannga",
    "subscription": "OrcasPM",
    "user": "mcp-identity"
  }
}
```

**Output Schemas**
```json
{
  "status": 200,
  "message": "Success",
  "results": {
    "Tables": ["users", "sessions", "events", "metrics"]
  },
  "duration": 0
}
```
**Example Prompt**
```
Show me all tables in the database nlweb_db_2

{
  "command": "postgres_list_tables",
  "database": "nlweb_db_2",
  "resource-group": "abeomor",
  "server": "diskannga",
  "subscription": "OrcasPM",
  "user": "mcp-identity"
}
```

**Remote MCP Server URL**  
`LOCAL, generate when user deploys`

[🔝 Back to Top](#table-of-contents)

---

### Table: get table schema

Description
- Inspects a table and returns an inferred schema: column names and types. For tables storing JSONB documents, this tool can optionally sample rows and report property frequency and inferred types for JSON properties.

Caveats: managed vector types or provider-specific types may be reported as USER-DEFINED; when inspecting large tables the tool samples a limited number of rows to infer JSON structure.

**Tool Input**
```json
{
  "command": "postgres_get_table_schema",
  "intent": "retrieve schema for the 'documents' table in nlweb_db_2",
  "parameters": {
    "database": "nlweb_db_2",
    "table": "documents",
    "resource-group": "abeomor",
    "server": "diskannga",
    "subscription": "OrcasPM",
    "user": "mcp-identity"
  }
}
```

**Output Schemas**
```json
{
  "status": 200,
  "message": "Success",
  "results": {
    "Schema": [
      {"column": "id", "type": "uuid"},
      {"column": "name", "type": "text"},
      {"column": "email", "type": "text"},
      {"column": "created_at", "type": "timestamp"}
    ]
  },
  "duration": 0
}
```
**Example Prompt**
```
Get the schema for the documents table in nlweb_db_2

{
  "command": "postgres_get_table_schema",
  "database": "nlweb_db_2",
  "table": "documents",
  "resource-group": "abeomor",
  "server": "diskannga",
  "subscription": "OrcasPM",
  "user": "mcp-identity"
}
```

**Remote MCP Server URL**  
`LOCAL, generate when user deploys`

[🔝 Back to Top](#table-of-contents)

---

## Server

## TODO-1: subscription has to be the ID and not the user friendly name
## TODO-2: memory spikes when doing server operations

### Server: list servers

Description
- Lists PostgreSQL server instances visible to the caller within the subscription and resource-group scope. Use this to discover available server endpoints before running server-level operations.

Notes: depending on the Azure API and credentials the subscription parameter should be the subscription ID for reliable results.

**Tool Input**
```json
{
  "command": "postgres_list_servers",
  "intent": "list all PostgreSQL servers available to the user",
  "parameters": {
    "user": "mcp-identity",
    "subscription": "OrcasPM",
    "resource-group": "abeomor"
  }
}
```

**Output Schemas**
```json
{
  "status": 200,
  "message": "Success",
  "results": {
    "Servers": ["diskannga", "pgserver01", "analytics-prod"]
  },
  "duration": 0
}
```
**Example Prompt**
```
List all PostgreSQL servers I have access to

{
  "command": "postgres_list_servers",
  "user": "mcp-identity",
  "resource-group": "abeomor",
  "subscription": "5c5037e5-d3f1-4e7b-b3a9-f6bf94902b30"
}
```

**Remote MCP Server URL**  
`LOCAL, generate when user deploys`

[🔝 Back to Top](#table-of-contents)

---

### Server: get server configuration

Description
- Retrieves high-level configuration information for a Postgres server (engine version, configured limits such as max_connections, timezone, and other server metadata). Useful for capacity planning and validating server capability before heavy queries or vector search workloads.

**Tool Input**
```json
{
  "command": "postgres_get_server_config",
  "intent": "retrieve configuration settings for server 'diskannga'",
  "parameters": {
    "server": "diskannga",
    "resource-group": "abeomor",
    "subscription": "OrcasPM",
    "user": "mcp-identity"
  }
}
```

**Output Schemas**
```json
{
  "status": 200,
  "message": "Success",
  "results": {
    "Configuration": {
      "version": "14",
      "max_connections": 100,
      "timezone": "UTC"
    }
  },
  "duration": 0
}
```
**Example Prompt**
```
Show me the configuration for server diskannga

{
  "command": "postgres_get_server_config",
  "server": "diskannga",
  "resource-group": "abeomor",
  "subscription": "5c5037e5-d3f1-4e7b-b3a9-f6bf94902b30",
  "user": "mcp-identity"
}
```

**Remote MCP Server URL**  
`LOCAL, generate when user deploys`

[🔝 Back to Top](#table-of-contents)

---

### Server: get server parameter

Description
- Fetches the current value for a specific server parameter (for example `work_mem` or `shared_buffers`). Use this for tuning and verification before and after parameter changes.

Notes: reading parameters is read-only but may require elevated privileges depending on server role mapping.

**Tool Input**
```json
{
  "command": "postgres_get_server_parameter",
  "intent": "get value of 'work_mem' parameter for server 'diskannga'",
  "parameters": {
    "server": "diskannga",
    "parameter": "work_mem",
    "resource-group": "abeomor",
    "subscription": "OrcasPM",
    "user": "mcp-identity"
  }
}
```

**Output Schemas**
```json
{
  "status": 200,
  "message": "Success",
  "results": {
    "Parameter": {
      "name": "work_mem",
      "value": "4MB"
    }
  },
  "duration": 0
}
```
**Example Prompt**
```
Get the value of the work_mem parameter for server diskannga

{
  "command": "postgres_get_server_parameter",
  "server": "diskannga",
  "parameter": "work_mem",
  "resource-group": "abeomor",
  "subscription": "5c5037e5-d3f1-4e7b-b3a9-f6bf94902b30",
  "user": "mcp-identity"
}
```

**Remote MCP Server URL**  
`LOCAL, generate when user deploys`

[🔝 Back to Top](#table-of-contents)

---

### Server: set server parameter
*NOTE: There will be an approval needed for this action. Sets a specific parameter of a PostgreSQL server to a certain value.*

Description
- Updates a server-level configuration parameter to a new value. This action typically requires administrative privileges and may trigger a server restart or rolling configuration change depending on the hosting SKU. The tool returns the old and new values when successful.

Warnings: changing server parameters can impact running workloads. Require explicit approval and validation steps before applying in production.

**Tool Input**
```json
{
  "command": "postgres_set_server_parameter",
  "intent": "set 'work_mem' parameter to 8MB for server 'diskannga'",
  "parameters": {
    "server": "diskannga",
    "parameter": "work_mem",
    "value": "8MB",
    "resource-group": "abeomor",
    "subscription": "OrcasPM",
    "user": "mcp-identity"
  }
}
```

**Output Schemas**
```json
{
  "status": 200,
  "message": "Parameter updated successfully",
  "results": {
    "Parameter": {
      "name": "work_mem",
      "old_value": "4MB",
      "new_value": "8MB"
    }
  },
  "duration": 0
}
```
**Example Prompt**
```
Set the work_mem parameter to 8MB for server diskannga

{
  "command": "postgres_set_server_parameter",
  "server": "diskannga",
  "parameter": "work_mem",
  "value": "8MB",
  "resource-group": "abeomor",
  "subscription": "5c5037e5-d3f1-4e7b-b3a9-f6bf94902b30",
  "user": "mcp-identity"
}
```

**Permissions**
You can active READ-ONLY operation Azure RBC.
![Azure agent permission not granted](azure_agent_permission_no_granted.png)

**Remote MCP Server URL**  
`LOCAL, generate when user deploys`

[🔝 Back to Top](#table-of-contents)

---

## Errors
```json
{
  "status":401,
  "message":"Authentication failed. Please run \u0027az login\u0027 to sign in to Azure. Details: The ChainedTokenCredential failed due to an unhandled exception: InteractiveBrowserCredential authentication failed: Persistence check failed. Inspect inner exception for details. To mitigate this issue, please refer to the troubleshooting guidelines here at https://aka.ms/azmcp/troubleshooting.",
  "results":
    {
      "message":"The ChainedTokenCredential failed due to an unhandled exception: InteractiveBrowserCredential authentication failed: Persistence check failed. Inspect inner exception for details",
      "stackTrace":null,
      "type":"AuthenticationFailedException"
      },
  "duration":0
  }
```