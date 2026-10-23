"""Fixed-target, read-only PostgreSQL data-plane tools for Azure HorizonDB."""

import asyncio
import logging
import os
import re
import ssl
from dataclasses import dataclass

import jwt
import psycopg
from azure.identity import DefaultAzureCredential
from mcp.server.auth.provider import AccessToken, TokenVerifier
from mcp.server.auth.settings import AuthSettings
from mcp.server.fastmcp import FastMCP
from pglast import ast, parse_sql
from psycopg.rows import dict_row

logger = logging.getLogger(__name__)


@dataclass(frozen=True)
class Settings:
    host: str
    database: str
    user: str
    sslmode: str = "verify-full"
    sslrootcert: str = ssl.get_default_verify_paths().cafile or "/etc/ssl/certs/ca-certificates.crt"

    def __post_init__(self):
        if not re.fullmatch(r"[a-zA-Z0-9-]+(?:\.[a-zA-Z0-9-]+)*\.horizondb\.azure\.com", self.host):
            raise ValueError("PGHOST must be a HorizonDB DNS hostname, without a port or URL.")
        if not self.database or not self.user:
            raise ValueError("PGDATABASE and PGUSER are required.")
        if self.sslmode not in {"verify-full", "verify-ca", "require"}:
            raise ValueError("PGSSLMODE must enable TLS: verify-full, verify-ca, or require.")

    @classmethod
    def from_env(cls):
        return cls(
            host=os.environ["PGHOST"],
            database=os.environ["PGDATABASE"],
            user=os.environ["PGUSER"],
            sslmode=os.environ.get("PGSSLMODE", "verify-full"),
            sslrootcert=os.environ.get(
                "PGSSLROOTCERT", ssl.get_default_verify_paths().cafile or "/etc/ssl/certs/ca-certificates.crt"
            ),
        )


class Database:
    def __init__(self, settings: Settings):
        self.settings = settings
        self.credential = None

    def password(self):
        password = os.environ.get("PGPASSWORD")
        if password:
            return password
        if self.credential is None:
            self.credential = DefaultAzureCredential()
        return self.credential.get_token("https://ossrdbms-aad.database.windows.net/.default").token

    async def query(self, query: str, parameters=None):
        statements = parse_sql(query.replace("%s", "NULL") if parameters else query)
        if len(statements) != 1 or not isinstance(statements[0].stmt, ast.SelectStmt):
            raise ValueError("Only one SELECT statement is allowed, including SELECT with WITH.")
        password = await asyncio.to_thread(self.password)
        async with await psycopg.AsyncConnection.connect(
            host=self.settings.host,
            dbname=self.settings.database,
            user=self.settings.user,
            password=password,
            port=5432,
            sslmode=self.settings.sslmode,
            sslrootcert=self.settings.sslrootcert,
            connect_timeout=15,
            options="-c default_transaction_read_only=on -c statement_timeout=15000",
            row_factory=dict_row,
        ) as connection:
            await connection.set_read_only(True)
            async with connection.cursor() as cursor:
                await cursor.execute(query, parameters)
                rows = await cursor.fetchmany(101)
                return {"rows": rows[:100], "truncated": len(rows) > 100}


class EntraVerifier(TokenVerifier):
    def __init__(self, tenant: str, audience: str):
        if not re.fullmatch(r"[0-9a-fA-F-]{36}", tenant):
            raise ValueError("AZURE_TENANT_ID must be the tenant GUID.")
        self.tenant = tenant
        self.audience = audience
        self.keys = jwt.PyJWKClient(
            f"https://login.microsoftonline.com/{tenant}/discovery/v2.0/keys"
        )

    async def verify_token(self, token: str):
        try:
            key = await asyncio.to_thread(self.keys.get_signing_key_from_jwt, token)
            claims = jwt.decode(
                token,
                key.key,
                algorithms=["RS256"],
                audience=[self.audience, f"api://{self.audience}"],
                options={"require": ["exp", "iss", "aud", "tid"]},
            )
            if claims["iss"] not in {
                f"https://sts.windows.net/{self.tenant}/",
                f"https://login.microsoftonline.com/{self.tenant}/v2.0",
            } or claims["tid"] != self.tenant:
                return None
            roles = claims.get("roles", [])
            if not isinstance(roles, list) or "Mcp.Tools.ReadWrite.All" not in roles:
                return None
            return AccessToken(
                token=token,
                client_id=claims.get("azp") or claims.get("appid") or "",
                scopes=["Mcp.Tools.ReadWrite.All"],
                expires_at=claims["exp"],
            )
        except (jwt.PyJWTError, jwt.PyJWKClientError):
            logger.warning("Rejected invalid Microsoft Entra access token.")
            return None


def create_server(settings: Settings, *, http=False):
    database = Database(settings)
    auth = {}
    if http:
        tenant = os.environ["AZURE_TENANT_ID"]
        audience = os.environ["ENTRA_APP_CLIENT_ID"]
        auth = {
            "token_verifier": EntraVerifier(tenant, audience),
            "auth": AuthSettings(
                issuer_url=f"https://login.microsoftonline.com/{tenant}/v2.0",
                required_scopes=["Mcp.Tools.ReadWrite.All"],
                resource_server_url=None,
            ),
        }
    server = FastMCP(
        "HorizonDB PostgreSQL",
        host="0.0.0.0" if http else "127.0.0.1",
        port=8080,
        stateless_http=True,
        **auth,
    )

    @server.tool()
    async def postgres_database_query(query: str) -> dict:
        """Run one read-only SELECT on the configured HorizonDB database. Returns at most 100 rows.

        Connection details are fixed by the server, not supplied by the caller.
        Cast vector columns to text when selecting raw embeddings.
        """
        return await database.query(query)

    @server.tool()
    async def postgres_list_databases() -> dict:
        """List accessible non-template databases; queries still use the configured database."""
        return await database.query(
            "SELECT datname FROM pg_database WHERE NOT datistemplate "
            "AND has_database_privilege(datname, 'CONNECT') ORDER BY datname"
        )

    @server.tool()
    async def postgres_table_list() -> dict:
        """List tables and views visible to the configured database role."""
        return await database.query(
            "SELECT table_schema, table_name, table_type FROM information_schema.tables "
            "WHERE table_schema NOT IN ('pg_catalog', 'information_schema') "
            "ORDER BY table_schema, table_name"
        )

    @server.tool()
    async def postgres_table_schema_get(table: str, schema: str = "public") -> dict:
        """Describe accessible columns of a table in the configured database."""
        return await database.query(
            "SELECT column_name, data_type, udt_name, is_nullable "
            "FROM information_schema.columns WHERE table_schema = %s AND table_name = %s "
            "ORDER BY ordinal_position",
            (schema, table),
        )

    return server


if __name__ == "__main__":
    logging.basicConfig(level=logging.INFO)
    transport = os.environ.get("MCP_TRANSPORT", "stdio")
    if transport not in {"stdio", "streamable-http"}:
        raise ValueError("MCP_TRANSPORT must be stdio or streamable-http.")
    create_server(Settings.from_env(), http=transport == "streamable-http").run(transport=transport)
