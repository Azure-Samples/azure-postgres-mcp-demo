using System.Text.Json;
using System.Linq;
using ModelContextProtocol.Protocol;
using ModelContextProtocol.Server;
using ModelContextProtocol.Client;
using Microsoft.AspNetCore.Http;
using System.Security.Claims;

namespace AzMcpPostgresServer;

internal static class ProxyMcpHandlers
{
    // When true (dev only), authentication and role checks are skipped.
    public static bool DevBypassAuth { get; set; } = false;

    private static DownstreamServer? _server;
    private static IMcpClient? _client;               // Lazy remote MCP client
    private static readonly object _sync = new();      // Sync root for client init

    /// <summary>Configure the downstream server (call once during startup).</summary>
    public static void Initialize(DownstreamServer server) => _server = server;

    public static async ValueTask<ListToolsResult> HandleListToolsAsync(
        RequestContext<ListToolsRequestParams> request,
        CancellationToken cancellationToken)
    {
        EnsureReady();
        var user = GetUser(request);
        if (!DevBypassAuth)
        {
            EnsureAuthenticated(user);
        }

        var client = await EnsureClientAsync(cancellationToken).ConfigureAwait(false);
        var remoteTools = await client.ListToolsAsync(cancellationToken: cancellationToken).ConfigureAwait(false);
        return new ListToolsResult
        {
            Tools = remoteTools.Select(t => t.ProtocolTool).ToList()
        };
    }

    public static async ValueTask<CallToolResult> HandleCallToolAsync(
        RequestContext<CallToolRequestParams> request,
        CancellationToken cancellationToken)
    {
        EnsureReady();
        var user = GetUser(request);
        if (!DevBypassAuth)
        {
            EnsureAuthenticated(user);
            EnsureInRole(user, "Mcp.Tool.Executor");
        }

        if (request.Params is null)
        {
            throw new InvalidOperationException("Call parameters missing");
        }

        var client = await EnsureClientAsync(cancellationToken).ConfigureAwait(false);
        var name = request.Params.Name ?? throw new InvalidOperationException("Tool name required");

        var args = request.Params.Arguments;
        Dictionary<string, object?>? parameters = args?.ToDictionary(
            kvp => kvp.Key,
            kvp => (object?)kvp.Value,
            StringComparer.OrdinalIgnoreCase);

        return await client.CallToolAsync(name, parameters, cancellationToken: cancellationToken).ConfigureAwait(false);
    }

    private static async Task<IMcpClient> EnsureClientAsync(CancellationToken ct)
    {
        var existing = _client;
        if (existing != null) return existing;
        if (_server == null) throw new InvalidOperationException("Downstream server not configured");

        lock (_sync)
        {
            if (_client != null) return _client; // created while waiting for lock
        }

        var transport = new SseClientTransport(new SseClientTransportOptions
        {
            Endpoint = new Uri(_server.Url),
            TransportMode = HttpTransportMode.AutoDetect,
            Name = "aca-proxy"
        });

        var options = new McpClientOptions
        {
            ClientInfo = new Implementation { Name = "aca-proxy", Version = "1.0.0" },
            Capabilities = new ClientCapabilities()
        };

        var created = await McpClientFactory.CreateAsync(transport, options, loggerFactory: null, cancellationToken: ct).ConfigureAwait(false);
        lock (_sync)
        {
            _client ??= created;
            return _client;
        }
    }

    private static void EnsureReady()
    {
        if (_server is null)
        {
            throw new InvalidOperationException("ProxyMcpHandlers not initialized");
        }
    }

    private static ClaimsPrincipal? GetUser<T>(RequestContext<T> ctx)
    {
        var accessor = ctx.Services?.GetService(typeof(IHttpContextAccessor)) as IHttpContextAccessor;
        return accessor?.HttpContext?.User;
    }

    private static void EnsureAuthenticated(ClaimsPrincipal? user)
    {
        if (user?.Identity?.IsAuthenticated != true)
        {
            throw new UnauthorizedAccessException("Unauthorized");
        }
    }

    private static void EnsureInRole(ClaimsPrincipal? user, string role)
    {
        if (user is null || !user.IsInRole(role))
        {
            throw new InvalidOperationException("Forbidden: missing role");
        }
    }
}
