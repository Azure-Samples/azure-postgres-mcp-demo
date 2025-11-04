-- Grant Azure AD authentication to the principal 'azure-mcp-postgres-server'
SELECT * FROM pgaadauth_create_principal('azure-mcp-postgres-server', false, false);

-- Grant SELECT on all existing tables
GRANT SELECT ON ALL TABLES IN SCHEMA public TO "azure-mcp-postgres-server";

-- Grant SELECT on all future tables
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT SELECT ON TABLES TO "azure-mcp-postgres-server";
