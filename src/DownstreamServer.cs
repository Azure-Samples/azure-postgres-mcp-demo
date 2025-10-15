using System.Text.Json;

namespace AzMcpPostgresServer;

internal sealed record DownstreamServer(string Name, string Url, string? Description)
{
	public static DownstreamServer Load()
	{
		var baseDir = AppContext.BaseDirectory;
		var path = Path.Combine(baseDir, "server.json");
		if (!File.Exists(path))
		{
			throw new InvalidOperationException($"Server definition file not found at '{path}'");
		}
		using var fs = File.OpenRead(path);
		using var doc = JsonDocument.Parse(fs);
		var root = doc.RootElement;
		if (root.ValueKind != JsonValueKind.Object)
		{
			throw new InvalidOperationException("Server definition must be a single JSON object.");
		}
		if (!root.TryGetProperty("name", out var nameEl) || string.IsNullOrWhiteSpace(nameEl.GetString()))
		{
			throw new InvalidOperationException("Server definition missing required 'name'.");
		}
		if (!root.TryGetProperty("url", out var urlEl) || string.IsNullOrWhiteSpace(urlEl.GetString()))
		{
			throw new InvalidOperationException("Server definition missing required 'url'.");
		}
		var name = nameEl.GetString()!;
		var url = urlEl.GetString()!;
		var desc = root.TryGetProperty("description", out var descEl) ? descEl.GetString() : null;
		return new DownstreamServer(name, url, desc);
	}
}
