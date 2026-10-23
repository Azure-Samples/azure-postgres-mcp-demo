import os
import sys
import time
import unittest
from pathlib import Path
from types import SimpleNamespace
from unittest.mock import AsyncMock, MagicMock, patch

import httpx
import jwt
from cryptography.hazmat.primitives.asymmetric import rsa
from mcp import ClientSession, StdioServerParameters
from mcp.client.stdio import stdio_client

from horizondb import Database, EntraVerifier, Settings, create_server

HOST = "example.rw.cluster.westus2.horizondb.azure.com"
TENANT = "00000000-0000-0000-0000-000000000001"
AUDIENCE = "00000000-0000-0000-0000-000000000002"


class SettingsTests(unittest.TestCase):
    def test_rejects_connection_string_injection_and_non_horizon_hosts(self):
        for host in ["localhost", "horizondb.azure.com", HOST + ":5432", HOST + ";user=admin",
                     "https://" + HOST, HOST + ".evil.example", HOST + ",localhost"]:
            with self.subTest(host=host), self.assertRaises(ValueError):
                Settings(host, "postgres", "reader")

    def test_requires_tls(self):
        for mode in ["disable", "allow", "prefer"]:
            with self.subTest(mode=mode), self.assertRaises(ValueError):
                Settings(HOST, "postgres", "reader", sslmode=mode)


class DatabaseTests(unittest.IsolatedAsyncioTestCase):
    async def test_rejects_writes_and_multiple_statements_before_connecting(self):
        database = Database(Settings(HOST, "postgres", "reader"))
        with patch("horizondb.psycopg.AsyncConnection.connect") as connect:
            for query in ["DELETE FROM products", "SET transaction_read_only=off",
                          "SELECT 1; SELECT 2", "BEGIN; SELECT 1; COMMIT", ""]:
                with self.subTest(query=query), self.assertRaises(ValueError):
                    await database.query(query)
            connect.assert_not_called()

    async def test_select_uses_readonly_tls_timeout_parameters_and_row_limit(self):
        database = Database(Settings(HOST, "postgres", "reader"))
        connection = AsyncMock()
        connection.__aenter__.return_value = connection
        cursor = AsyncMock()
        cursor.__aenter__.return_value = cursor
        connection.cursor = MagicMock(return_value=cursor)
        cursor.fetchmany.return_value = [{"value": n} for n in range(101)]
        with patch.object(database, "password", return_value="not-a-secret"), patch(
            "horizondb.psycopg.AsyncConnection.connect", new=AsyncMock(return_value=connection)
        ) as connect:
            result = await database.query("SELECT %s AS value", (42,))
        self.assertEqual(len(result["rows"]), 100)
        self.assertTrue(result["truncated"])
        connection.set_read_only.assert_awaited_once_with(True)
        cursor.execute.assert_awaited_once_with("SELECT %s AS value", (42,))
        self.assertEqual(connect.call_args.kwargs["sslmode"], "verify-full")
        self.assertIn("statement_timeout=15000", connect.call_args.kwargs["options"])
        self.assertEqual(connect.call_args.kwargs["host"], HOST)

    async def test_database_errors_are_not_reported_as_success(self):
        database = Database(Settings(HOST, "postgres", "reader"))
        with patch.object(database, "password", return_value="not-a-secret"), patch(
            "horizondb.psycopg.AsyncConnection.connect",
            new=AsyncMock(side_effect=ConnectionError("unreachable")),
        ), self.assertRaises(ConnectionError):
            await database.query("SELECT 1")


class AuthTests(unittest.IsolatedAsyncioTestCase):
    async def test_checks_signature_audience_tenant_issuer_and_application_role(self):
        verifier = EntraVerifier(TENANT, AUDIENCE)
        key = rsa.generate_private_key(public_exponent=65537, key_size=2048)
        claims = {
            "iss": f"https://login.microsoftonline.com/{TENANT}/v2.0",
            "tid": TENANT,
            "aud": AUDIENCE,
            "exp": int(time.time()) + 300,
            "azp": "foundry-project",
            "roles": ["Mcp.Tools.ReadWrite.All"],
        }
        with patch.object(verifier.keys, "get_signing_key_from_jwt", return_value=SimpleNamespace(key=key.public_key())):
            self.assertIsNotNone(await verifier.verify_token(jwt.encode(claims, key, algorithm="RS256")))
            for invalid in [
                dict(claims, roles=[]),
                dict(claims, roles="Mcp.Tools.ReadWrite.All"),
                dict(claims, iss="https://attacker.example"),
                dict(claims, tid="another-tenant"),
                dict(claims, aud="another-audience"),
                dict(claims, exp=int(time.time()) - 60),
            ]:
                self.assertIsNone(await verifier.verify_token(jwt.encode(invalid, key, algorithm="RS256")))
            self.assertIsNone(await verifier.verify_token(jwt.encode(claims, "x" * 32, algorithm="HS256")))

    async def test_http_accepts_signed_authorized_mcp_initialization(self):
        verifier = EntraVerifier(TENANT, AUDIENCE)
        key = rsa.generate_private_key(public_exponent=65537, key_size=2048)
        token = jwt.encode({
            "iss": f"https://sts.windows.net/{TENANT}/",
            "tid": TENANT,
            "aud": f"api://{AUDIENCE}",
            "exp": int(time.time()) + 300,
            "appid": "foundry-project",
            "roles": ["Mcp.Tools.ReadWrite.All"],
        }, key, algorithm="RS256")
        with patch.dict(os.environ, AZURE_TENANT_ID=TENANT, ENTRA_APP_CLIENT_ID=AUDIENCE), patch(
            "horizondb.EntraVerifier", return_value=verifier
        ):
            server = create_server(Settings(HOST, "postgres", "reader"), http=True)
            app = server.streamable_http_app()
        with patch.object(verifier.keys, "get_signing_key_from_jwt", return_value=SimpleNamespace(key=key.public_key())):
            async with server.session_manager.run():
                async with httpx.AsyncClient(
                    transport=httpx.ASGITransport(app=app), base_url="https://test"
                ) as client:
                    response = await client.post("/mcp", headers={
                        "Authorization": f"Bearer {token}",
                        "Accept": "application/json, text/event-stream",
                    }, json={
                        "jsonrpc": "2.0", "id": 1, "method": "initialize",
                        "params": {"protocolVersion": "2025-11-25", "capabilities": {},
                                   "clientInfo": {"name": "test", "version": "1.0"}},
                    })
        self.assertEqual(response.status_code, 200, response.text)
        self.assertIn("HorizonDB PostgreSQL", response.text)

    async def test_http_rejects_requests_without_a_bearer_token(self):
        with patch.dict(os.environ, AZURE_TENANT_ID=TENANT, ENTRA_APP_CLIENT_ID=AUDIENCE):
            app = create_server(Settings(HOST, "postgres", "reader"), http=True).streamable_http_app()
        async with httpx.AsyncClient(transport=httpx.ASGITransport(app=app), base_url="https://test") as client:
            response = await client.post("/mcp", json={})
        self.assertEqual(response.status_code, 401)

    def test_http_fails_closed_without_entra_configuration(self):
        with patch.dict(os.environ, {}, clear=True), self.assertRaises(KeyError):
            create_server(Settings(HOST, "postgres", "reader"), http=True)


class ProtocolTests(unittest.IsolatedAsyncioTestCase):
    async def test_stdio_discovery_and_rejected_query(self):
        parameters = StdioServerParameters(
            command=sys.executable,
            args=[str(Path(__file__).with_name("horizondb.py"))],
            env={"PGHOST": HOST, "PGDATABASE": "postgres", "PGUSER": "reader"},
        )
        async with stdio_client(parameters) as (read, write):
            async with ClientSession(read, write) as session:
                await session.initialize()
                tools = await session.list_tools()
                self.assertEqual(
                    {tool.name for tool in tools.tools},
                    {"postgres_database_query", "postgres_list_databases",
                     "postgres_table_list", "postgres_table_schema_get"},
                )
                response = await session.call_tool("postgres_database_query", {"query": "DROP TABLE products"})
                self.assertTrue(response.isError)


if __name__ == "__main__":
    unittest.main()
