# HorizonDB MCP server

This optional backend connects directly to a fixed Azure HorizonDB endpoint over
PostgreSQL. The Azure MCP image used by the default sample has Flexible
Server-specific hostname validation and management APIs; changing only the
resource ID does not enable HorizonDB.

The HorizonDB backend exposes four tools: `postgres_list_databases`,
`postgres_table_list`, `postgres_table_schema_get`, and `postgres_database_query`.
It does not expose ARM server configuration, parameter updates, or SQL writes.
Connection settings are server-owned; agents cannot change the host, database,
or role through tool arguments.

## Run locally

Requires Python 3.12 and network access to the existing cluster.

```bash
python3.12 -m venv .venv
source .venv/bin/activate
pip install -r server/requirements.txt
export PGHOST="<cluster-read-write-hostname>.horizondb.azure.com"
export PGDATABASE="postgres"
export PGUSER="<database-role>"
az login
python server/horizondb.py
```

The default transport is stdio. Configure your MCP client to run this Python
script with the same environment. Use the **complete endpoint from the
HorizonDB Connect page**; do not append `.postgres.database.azure.com`.

Without `PGPASSWORD`, the server obtains renewable Microsoft Entra database
tokens through `DefaultAzureCredential`. The database must support Entra
authentication and the identity must have a database principal and grants.
An ARM Reader role alone does not grant SQL access.

If the cluster uses PostgreSQL password authentication, supply `PGPASSWORD`
through your local secret store or environment instead. Never put a password in
an agent prompt, tool arguments, committed JSON, or a container image.

TLS defaults to `PGSSLMODE=verify-full` with the system CA bundle. Set
`PGSSLROOTCERT` when using a different trust bundle. `verify-ca` is an explicit
compatibility option for endpoints whose certificate does not match the supplied
hostname: it validates the issuing CA but **not the hostname**. Prefer a corrected
endpoint/certificate and `verify-full`. `require` encrypts without verifying the
server certificate; plaintext modes are rejected.

## Deploy for Foundry

The existing Bicep deployment, Entra application role, and Foundry managed
identity assignment are reused. HTTP mode always requires a signed, unexpired
Entra bearer token from the configured tenant with the application audience and
`Mcp.Tools.ReadWrite.All` role. Missing authentication configuration prevents
startup; unauthenticated MCP requests receive HTTP 401.

1. Build and publish `server/Dockerfile` as a Linux AMD64 image to a registry
   accessible by Container Apps. For example:

   ```bash
   docker build --platform linux/amd64 -t ghcr.io/<owner>/horizondb-mcp:demo server
   docker push ghcr.io/<owner>/horizondb-mcp:demo
   ```

   This template expects an anonymously pullable image. Make this code-only image
   public, or configure private-registry authentication separately before using
   a private image. Never bake database credentials into it.

2. In `infra/main.parameters.json`, set `postgresResourceId` to the HorizonDB
   cluster resource ID and set `aifProjectResourceId` as in the existing quick
   start. Add this parameter alongside the existing parameters:

   ```json
   "horizonDB": {
     "value": {
       "image": "ghcr.io/<owner>/horizondb-mcp:demo",
       "host": "<actual-cluster-read-write-hostname>.horizondb.azure.com",
       "database": "postgres",
       "sslmode": "verify-full"
     }
   }
   ```

   Omitting `horizonDB` preserves the original Azure MCP deployment. For
   HorizonDB, the Flexible Server ARM Reader assignment is skipped because this
   backend uses SQL, not Flexible Server management APIs.

3. Run `azd up` using the existing quick-start instructions. By default, the
   outgoing database identity is the Container App's system-assigned managed
   identity, and the SQL role name defaults to `CONTAINER_APP_IDENTITY_NAME`.
   Create its database principal using the cluster's supported Entra setup and
   grant only the required database/schema/table privileges. To use an existing
   SQL role, set `horizonDB.value.user`.

   For a password-authenticated cluster, also provide the secure
   `horizonDBPassword` parameter through your deployment's secret handling.
   With azd, reference an environment variable rather than a literal:

   ```json
   "horizonDBPassword": {
     "value": "${HORIZONDB_PASSWORD}"
   }
   ```

   Set `HORIZONDB_PASSWORD` in the local azd environment from a secret source.
   The deployment stores it as a Container App secret and references that secret
   from `PGPASSWORD`; it is not an output.

4. Connect Foundry to the emitted `CONTAINER_APP_URL`, which includes `/mcp` for
   HorizonDB. Keep **Microsoft Entra / Project Managed Identity** authentication
   and the emitted `ENTRA_APP_CLIENT_ID` audience. Do not use anonymous HTTP.

For the existing Python Foundry client, set `MCP_SERVER_LABEL=horizondb`; its
HorizonDB instructions use the server-configured connection rather than Azure
Flexible Server parameters.

## Access boundaries

Use a dedicated, non-administrative reader role with `CONNECT`, schema `USAGE`,
and `SELECT` only on approved tables. Configure default privileges as the owner
that creates future tables, in the actual target database. Avoid granting broad
function execution or using an administrator identity.

Only one `SELECT` statement is accepted, including `WITH ... SELECT`. PostgreSQL
read-only transactions also reject writes nested inside CTEs and `SELECT INTO`.
Each request uses a new connection, a 15-second statement timeout, and returns
at most 100 rows with an explicit `truncated` flag.

This is not a SQL sandbox: functions can have non-database side effects, and a
reader can still run expensive queries. Database grants, function permissions,
network controls, and resource limits remain essential.

## Test

From the repository root:

```bash
python -m unittest discover -s server -p 'test_*.py' -v
python server/smoke_test.py
az bicep build --file infra/main.bicep --stdout > /tmp/template.json
```

The smoke test uses your exported `PG*` configuration and calls the real server
over MCP stdio. It checks live identity, transaction read-only state, database and
table discovery, column metadata, row truncation, pgvector cosine distance,
statement rejection, and database-level `SELECT INTO` rejection. It does not
change existing tables or data; the attempted probe is a session-local temporary
table and must be rejected.

### Live validation: October 23, 2026

The smoke test passed on the saved connection **HorizonDB-Ignite2026**, database
`postgres`, PostgreSQL 17.11 / Azure HorizonDB. Password authentication was used.
The endpoint's certificate did not match its read-write hostname; this run
explicitly used `verify-ca` with the local CA bundle, not the default
`verify-full`. No credentials, endpoints, or account identifiers are included
here.

The local suite covers signed-token validation, HTTP authentication rejection,
SQL filtering, connection settings, result truncation, error propagation, and
MCP discovery. Bicep compilation covers both deployment branches. A hosted
Container Apps / Foundry end-to-end deployment and managed-identity database
authentication were **not** validated by this local run.
