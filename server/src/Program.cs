using Microsoft.AspNetCore.Authentication.JwtBearer;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.HttpOverrides;
using Microsoft.IdentityModel.Tokens;
using System.IdentityModel.Tokens.Jwt;
using ModelContextProtocol.AspNetCore;
using AzMcpPostgresServer;

var builder = WebApplication.CreateBuilder(args);

JwtSecurityTokenHandler.DefaultMapInboundClaims = false;

var azureAd = builder.Configuration.GetSection("AzureAd");
var tenantId = azureAd["TenantId"]!;
var clientId = azureAd["ClientId"]!;
var authority = $"https://login.microsoftonline.com/{tenantId}/v2.0";

builder.Services
    .AddAuthentication(JwtBearerDefaults.AuthenticationScheme)
    .AddJwtBearer(options =>
    {
        options.Authority = authority;

        options.TokenValidationParameters = new TokenValidationParameters
        {
            ValidateIssuer = true,
            ValidIssuer = authority,

            ValidateAudience = true,
            ValidAudiences = new[] { clientId, $"api://{clientId}" },

            ValidateLifetime = true,
            ValidateIssuerSigningKey = true,
            ClockSkew = TimeSpan.FromMinutes(2),
            RoleClaimType = "roles",
        };

        options.MapInboundClaims = false;
        options.RefreshOnIssuerKeyNotFound = true;
    });

builder.Services.AddAuthorization(options =>
{
    options.AddPolicy("McpToolExecutor", p => p.RequireRole("Mcp.Tool.Executor"));

    options.DefaultPolicy = new AuthorizationPolicyBuilder()
        .RequireAuthenticatedUser()
        .Build();
});

builder.Services.AddHttpContextAccessor();

// Add CORS support for browser requests
builder.Services.AddCors(options =>
{
    options.AddDefaultPolicy(policy =>
    {
        policy.AllowAnyOrigin()
              .AllowAnyMethod()
              .AllowAnyHeader();
    });
});

var downstreamMcpServer = DownstreamServer.Load();
ProxyMcpHandlers.Initialize(downstreamMcpServer);
ProxyMcpHandlers.DevBypassAuth = false;

builder.Services
    .AddMcpServer()
    .WithHttpTransport()
    .WithListToolsHandler(ProxyMcpHandlers.HandleListToolsAsync)
    .WithCallToolHandler(ProxyMcpHandlers.HandleCallToolAsync);

builder.Services.Configure<ForwardedHeadersOptions>(options =>
{
    options.ForwardedHeaders = ForwardedHeaders.XForwardedFor | ForwardedHeaders.XForwardedProto;
    options.KnownNetworks.Clear();
    options.KnownProxies.Clear();
});

var app = builder.Build();

// Enable CORS for browser requests
app.UseCors();

if (!ProxyMcpHandlers.DevBypassAuth)
{
    app.UseAuthentication();
    app.UseAuthorization();
}

var mcpEndpoints = app.MapMcp();
if (!ProxyMcpHandlers.DevBypassAuth)
{
    mcpEndpoints.RequireAuthorization();
}

app.Run();