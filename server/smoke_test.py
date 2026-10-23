"""Read-only, live MCP protocol checks. Uses the same PG* environment as the server."""

import asyncio
import json
import os
import sys
from pathlib import Path

from mcp import ClientSession, StdioServerParameters
from mcp.client.stdio import stdio_client


async def main():
    parameters = StdioServerParameters(
        command=sys.executable,
        args=[str(Path(__file__).with_name("horizondb.py"))],
        env={**os.environ, "MCP_TRANSPORT": "stdio"},
    )
    async with stdio_client(parameters) as (read, write):
        async with ClientSession(read, write) as session:
            await session.initialize()

            async def call(name, arguments=None):
                response = await session.call_tool(name, arguments or {})
                if response.isError:
                    raise RuntimeError(f"{name} failed: {response.content}")
                return json.loads(response.content[0].text)

            identity = await call("postgres_database_query", {
                "query": "SELECT version() AS version, current_database() AS database, "
                         "current_user AS role, current_setting('transaction_read_only') AS read_only"
            })
            assert "Horizon" in identity["rows"][0]["version"], identity
            assert identity["rows"][0]["read_only"] == "on", identity
            print("PASS: HorizonDB identity and read-only transaction")
            await call("postgres_list_databases")
            print("PASS: database discovery")
            tables = await call("postgres_table_list")
            if tables["rows"]:
                table = tables["rows"][0]
                columns = await call("postgres_table_schema_get", {
                    "schema": table["table_schema"], "table": table["table_name"],
                })
                assert columns["rows"], columns
                print("PASS: table discovery and schema")
            else:
                raise RuntimeError("No accessible tables; schema discovery could not be verified.")
            bounded = await call("postgres_database_query", {
                "query": "SELECT generate_series(1, 101) AS n"
            })
            assert len(bounded["rows"]) == 100 and bounded["truncated"], bounded
            print("PASS: result limit and truncation")
            vector = await call("postgres_database_query", {
                "query": "SELECT '[1,0,0]'::vector <=> '[1,0,0]'::vector AS distance"
            })
            assert vector["rows"][0]["distance"] == 0, vector
            print("PASS: pgvector cosine-distance query")
            rejected = await session.call_tool("postgres_database_query", {
                "query": "SET transaction_read_only=off"
            })
            assert rejected.isError, rejected
            print("PASS: write/session-control statement rejected")
            rejected = await session.call_tool("postgres_database_query", {
                "query": "SELECT 1 AS value INTO TEMP mcp_readonly_probe"
            })
            assert rejected.isError and any(
                "read-only" in item.text for item in rejected.content if hasattr(item, "text")
            ), rejected
            print("PASS: SELECT INTO rejected by database read-only enforcement")
            print(json.dumps(identity, indent=2))


if __name__ == "__main__":
    asyncio.run(main())
