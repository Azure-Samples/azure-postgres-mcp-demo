FROM mcr.microsoft.com/dotnet/aspnet:8.0 AS base
WORKDIR /app
EXPOSE 8080
EXPOSE 8081

FROM mcr.microsoft.com/dotnet/sdk:8.0 AS build

ARG BUILD_CONFIGURATION=Release
WORKDIR /src
COPY ["server/src/AzMcpPostgresServer.csproj", "server/src/"]
RUN dotnet restore "server/src/AzMcpPostgresServer.csproj"
COPY . .
WORKDIR "/src/server/src"
RUN dotnet build "AzMcpPostgresServer.csproj" -c $BUILD_CONFIGURATION -o /app/build

FROM build AS publish
ARG BUILD_CONFIGURATION=Release
RUN dotnet publish "AzMcpPostgresServer.csproj" -c $BUILD_CONFIGURATION -o /app/publish /p:UseAppHost=false

FROM mcr.microsoft.com/dotnet/sdk:8.0 AS azmcp
ARG AZMCP_VERSION=0.8.0
WORKDIR /tmp/azmcp
RUN apt-get update --allow-releaseinfo-change || true \
	&& apt-get install -y --no-install-recommends --allow-unauthenticated curl ca-certificates tar \
	&& rm -rf /var/lib/apt/lists/* \
	&& curl -L -o azure-mcp.tgz https://github.com/microsoft/mcp/releases/download/Azure.Mcp.Server-${AZMCP_VERSION}/azure-mcp-linux-x64-${AZMCP_VERSION}.tgz \
	&& tar -xzf azure-mcp.tgz \
	&& chmod +x package/dist/azmcp

FROM base AS final
WORKDIR /app
COPY --from=publish /app/publish .
COPY --from=azmcp /tmp/azmcp/package/dist/azmcp /opt/azmcp/azmcp
COPY docker/entrypoint.sh ./entrypoint.sh
RUN chmod +x ./entrypoint.sh && chmod +x /opt/azmcp/azmcp

RUN adduser --disabled-password --gecos "" appuser && chown -R appuser /app
USER appuser

ENTRYPOINT ["./entrypoint.sh"]