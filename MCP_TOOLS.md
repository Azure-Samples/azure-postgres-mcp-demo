# Azure Postgres MCP Tools Documentation

This document provides examples of available MCP tools for Azure Postgres, their input schemas, expected output formats and example prompts.

---

## Table of Contents

- [Azure Postgres MCP Tools Documentation](#azure-postgres-mcp-tools-documentation)
  - [Table of Contents](#table-of-contents)
  - [Database](#database)
    - [Database: list databases](#database-list-databases)
    - [Database: execute database query](#database-execute-database-query)
  - [Table](#table)
    - [Table: list tables](#table-list-tables)
    - [Table: get table schema](#table-get-table-schema)
  - [Server](#server)
    - [Server: list servers](#server-list-servers)
    - [Server: get server configuration](#server-get-server-configuration)
    - [Server: get server parameter](#server-get-server-parameter)
    - [Server: set server parameter](#server-set-server-parameter)

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
    "resource-group": "<your-resource-group>",
    "server": "<your-postgres-server>",
    "subscription": "<your-subscription>"
  }
}
```
**Example Prompt**
```
List all databases on my postgres server

{
  "command": "postgres_list_databases",
  "user": "mcp-identity",
  "resource-group": "<your-resource-group>",
  "server": "<your-postgres-server>",
  "subscription": "<your-subscription>"
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
      "sample_database",
      "app_db",
      "analytics_db",
      "test_db"
    ]
  },
  "duration": 0
}
```


**Remote MCP Server URL**  
`Auto generate when user deploys`

[🔝 Back to Top](#table-of-contents)

---

### Database: execute database query

Description
- Executes an arbitrary SQL query against a specified database and returns the raw query results. This is the general-purpose tool for checks, diagnostics, running vector search SQL, or validating extensions.

**Caveat #1:** Queries that select custom vector types (for example `public.vector` or the `vector` type from `pgvector`) may not deserialize in the MCP transport; in those cases exclude the vector column or cast it to text. 


**Tool Input**
```json
{
  "command": "postgres_database_query",
  "intent": "check if pg_diskann extension is installed in database azure_maintenance",
  "parameters": {
    "database": "<your-database>",
    "query": "SELECT extname FROM pg_extension WHERE extname = 'pg_diskann'",
    "resource-group": "<your-resource-group>",
    "server": "<your-postgres-server>",
    "subscription": "<your-subscription>",
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
"database": "<your-database>",
"resource-group": "<your-resource-group>",
"server": "<your-postgres-server>",
"subscription": "<your-subscription-id>",
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
`Auto generate when user deploys`

**Permissions**
You can active READ-ONLY operation with RLS policies on Postgres to stop agent from write malicious code.

Example: 
```
Write a random row to a table in my Postgres Database

{
"command";"postgres_database_query"
"database": "<your-database>",
"resource-group": "<your-resource-group>",
"server": "<your-postgres-server>",
"subscription": "<your-subscription-id>",
"table": "documents_no_vector",
"user": "mcp-identity"
}
```

Will not run

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
    "database": "<your-database>",
    "resource-group": "<your-resource-group>",
    "server": "<your-postgres-server>",
    "subscription": "<your-subscription>",
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
Show me all tables in the database <your-database>

{
  "command": "postgres_list_tables",
  "database": "<your-database>",
  "resource-group": "<your-resource-group>",
  "server": "<your-postgres-server>",
  "subscription": "<your-subscription>",
  "user": "mcp-identity"
}
```

**Remote MCP Server URL**  
`Auto generate when user deploys`

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
  "intent": "retrieve schema for the 'documents' table in sample database",
  "parameters": {
    "database": "<your-database>",
    "table": "documents",
    "resource-group": "<your-resource-group>",
    "server": "<your-postgres-server>",
    "subscription": "<your-subscription>",
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
Get the schema for the documents table in <your-database>

{
  "command": "postgres_get_table_schema",
  "database": "<your-database>",
  "table": "documents",
  "resource-group": "<your-resource-group>",
  "server": "<your-postgres-server>",
  "subscription": "<your-subscription>",
  "user": "mcp-identity"
}
```

**Remote MCP Server URL**  
`Auto generate when user deploys`

[🔝 Back to Top](#table-of-contents)

---

## Server

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
    "subscription": "<your-subscription>",
    "resource-group": "<your-resource-group>"
  }
}
```

**Output Schemas**
```json
{
  "status": 200,
  "message": "Success",
  "results": {
    "Servers": ["sample-postgres-server", "pgserver01", "analytics-prod"]
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
  "resource-group": "<your-resource-group>",
  "subscription": "<your-subscription-id>"
}
```

**Remote MCP Server URL**  
`Auto generate when user deploys`

[🔝 Back to Top](#table-of-contents)

---

### Server: get server configuration

Description
- Retrieves high-level configuration information for a Postgres server (engine version, configured limits such as max_connections, timezone, and other server metadata). Useful for capacity planning and validating server capability before heavy queries or vector search workloads.

**Tool Input**
```json
{
  "command": "postgres_get_server_config",
  "intent": "retrieve configuration settings for server",
  "parameters": {
    "server": "<your-postgres-server>",
    "resource-group": "<your-resource-group>",
    "subscription": "<your-subscription>",
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
Show me the configuration for server <your-postgres-server>

{
  "command": "postgres_get_server_config",
  "server": "<your-postgres-server>",
  "resource-group": "<your-resource-group>",
  "subscription": "<your-subscription-id>",
  "user": "mcp-identity"
}
```

**Remote MCP Server URL**  
`Auto generate when user deploys`

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
  "intent": "get value of 'work_mem' parameter for server",
  "parameters": {
    "server": "<your-postgres-server>",
    "parameter": "work_mem",
    "resource-group": "<your-resource-group>",
    "subscription": "<your-subscription>",
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
Get the value of the work_mem parameter for server <your-postgres-server>

{
  "command": "postgres_get_server_parameter",
  "server": "<your-postgres-server>",
  "parameter": "work_mem",
  "resource-group": "<your-resource-group>",
  "subscription": "<your-subscription-id>",
  "user": "mcp-identity"
}
```

**Remote MCP Server URL**  
`Auto generate when user deploys`

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
  "intent": "set 'work_mem' parameter to 8MB for server",
  "parameters": {
    "server": "<your-postgres-server>",
    "parameter": "work_mem",
    "value": "8MB",
    "resource-group": "<your-resource-group>",
    "subscription": "<your-subscription>",
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
Set the work_mem parameter to 8MB for server <your-postgres-server>

{
  "command": "postgres_set_server_parameter",
  "server": "<your-postgres-server>",
  "parameter": "work_mem",
  "value": "8MB",
  "resource-group": "<your-resource-group>",
  "subscription": "<your-subscription-id>",
  "user": "mcp-identity"
}
```

**Permissions**
You can active READ-ONLY operation Azure RBAC.


**Remote MCP Server URL**  
`Auto generate when user deploys`

[🔝 Back to Top](#table-of-contents)
