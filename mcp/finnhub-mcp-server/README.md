# finnhub-mcp-server

Production-oriented MCP server for the free Finnhub REST endpoints.

This refactored version is built around the provided Finnhub swagger schema and exposes every detected free endpoint as an MCP tool. It also adds:

- a generated tool catalog with schema and example arguments
- prompt helpers for tool discovery and explanation
- MCP resources for the catalog and free-endpoint inventory
- default elicitation for missing required parameters
- optional sampling-based tool recommendation
- a browser web app for browsing tools and preparing the next MCP tool call
- streamable HTTP mode and stdio mode
- health endpoint and structured HTTP logging

## What is exposed

### Endpoint tools

The server generates one MCP tool for each free endpoint discovered in the supplied swagger.

Examples:

- `finnhub_quote`
- `finnhub_symbol_search`
- `finnhub_company_news`
- `finnhub_company_profile2`
- `finnhub_stock_metric`
- `finnhub_stock_peers`
- `finnhub_calendar_earnings`
- `finnhub_country`

### Catalog tools

- `catalog_list_tools`
- `catalog_get_tool_details`
- `catalog_match_tools`

### Prompts

- `discover_finnhub_tools`
- `explain_finnhub_tool`

### Resources

- `finnhub://catalog/tools.json`
- `finnhub://catalog/tools.md`
- `finnhub://catalog/free-endpoints.json`
- `finnhub://catalog/tool/{toolName}.json`

## Runtime configuration

Required:

- `FINNHUB_API_TOKEN`

Optional:

- `FINNHUB_BASE_URL` default: `https://finnhub.io/api/v1`
- `FINNHUB_USER_AGENT` default: `finnhub-mcp-server/1.0`
- `FINNHUB_REQUEST_TIMEOUT_SECONDS` default: `20`
- `FINNHUB_MCP_PATH` default: `/mcp`
- `FINNHUB_WEB_APP_PATH` default: `/app`
- `FINNHUB_HTTP_ADDR` default: `:8080`
- `FINNHUB_ENABLE_RPC_LOGS` default: `false`

## Run in stdio mode

```bash
export FINNHUB_API_TOKEN='YOUR_TOKEN'
go run ./cmd/server -transport stdio
```

## Run in HTTP mode

```bash
export FINNHUB_API_TOKEN='YOUR_TOKEN'
go run ./cmd/server -transport http -http-addr :8080
```

Then open:

- MCP endpoint: `http://localhost:8080/mcp`
- web app: `http://localhost:8080/app`
- health: `http://localhost:8080/healthz`

## Docker build

```bash
docker build -t finnhub-mcp-server:0.1.0 .
```

## Browser web app

The web app is intentionally simple and operational:

- browse all tools grouped by domain
- search by tool name, title, summary, description
- inspect input schema and example arguments
- click a tool to select it for the next step
- fill known arguments in the form
- copy the generated MCP call JSON payload

## Design notes

### Why a thin custom Finnhub client

The project now uses a small explicit HTTP client instead of depending directly on a generated Swagger client wrapper in tool handlers. That keeps the MCP boundary easy to understand and makes error shaping, logging, and schema-driven tool generation more predictable.

### Elicitation behavior

When a user or model calls a tool without all required fields, the tool attempts MCP elicitation first. If the client does not support elicitation, the tool returns a clear tool-visible error describing the missing fields and an example argument payload.

### Sampling behavior

`catalog_match_tools` can ask the MCP client to draft a concise recommendation when the client supports sampling. If sampling is unavailable, the server falls back to deterministic ranking.

## Repository shape

```text
cmd/server/main.go                # entrypoint and transport setup
internal/config/config.go         # environment-driven config
internal/finnhub/client.go        # thin Finnhub HTTP adapter
internal/finnhub/specs.go         # generated free-endpoint specifications
internal/mcpserver/catalog.go     # human-facing tool catalog
internal/mcpserver/common.go      # shared MCP helpers
internal/mcpserver/prompts.go     # prompt registration
internal/mcpserver/resources.go   # resource registration
internal/mcpserver/server.go      # server assembly
internal/mcpserver/tools.go       # generated endpoint tools + catalog tools
internal/web/app.go               # HTTP handlers for the browser UI
internal/web/static/index.html    # standalone browser UI
```

## Important limitation

This repository was refactored against the current public MCP Go SDK API surface, but dependency download and full compile verification may still need to be executed in a network-enabled Go environment:

```bash
go mod tidy
go test ./...
```
