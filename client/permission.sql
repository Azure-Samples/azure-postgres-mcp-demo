-- Grant Azure AD authentication to the principal 'azure-mcp-postgres-server'
SELECT * FROM pgaadauth_create_principal('azure-mcp-postgres-server', false, false);

-- Grant SELECT on all existing tables
GRANT SELECT ON ALL TABLES IN SCHEMA public TO "azure-mcp-postgres-server";

-- Grant SELECT on all future tables
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT SELECT ON TABLES TO "azure-mcp-postgres-server";

-- Check permissions for Azure MCP principals
SELECT grantee, table_schema,table_name,privilege_type,is_grantable
FROM information_schema.table_privileges
WHERE grantee LIKE '%azure-mcp-postgres-server%'
ORDER BY grantee, table_schema, table_name, privilege_type;

-- Revoke permissions if needed
-- REVOKE SELECT ON ALL TABLES IN SCHEMA public FROM "azure-mcp-postgres-server";
-- DROP ROLE IF EXISTS "azure-mcp-postgres-server";
