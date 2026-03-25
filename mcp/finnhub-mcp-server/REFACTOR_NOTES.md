# Refactor Notes

## What changed

The original project was still the default `kmcp` skeleton with a single example `echo` tool. The refactor replaces that shape with a schema-driven Finnhub MCP server.

## Main decisions

1. **Generate one MCP tool per free Finnhub endpoint** from the provided swagger.
2. **Keep the Finnhub access layer explicit** with a small HTTP client instead of mixing remote request logic into MCP handlers.
3. **Add a catalog layer** so tools, prompts, resources, and the web UI all reuse one consistent representation.
4. **Use elicitation by default** for missing required fields.
5. **Use sampling optionally** only where it adds value: tool recommendation for a user goal.
6. **Add a browser web app** that lets the operator choose a tool and prepare the next MCP request.

## Free endpoints mapped to MCP tools

- `/search`
- `/stock/symbol`
- `/stock/market-status`
- `/stock/market-holiday`
- `/stock/profile2`
- `/news`
- `/company-news`
- `/stock/peers`
- `/stock/metric`
- `/stock/insider-transactions`
- `/stock/insider-sentiment`
- `/stock/financials-reported`
- `/stock/filings`
- `/calendar/ipo`
- `/stock/recommendation`
- `/stock/earnings`
- `/calendar/earnings`
- `/quote`
- `/forex/exchange`
- `/forex/symbol`
- `/crypto/exchange`
- `/crypto/symbol`
- `/covid19/us`
- `/fda-advisory-committee-calendar`
- `/stock/uspto-patent`
- `/stock/visa-application`
- `/stock/lobbying`
- `/stock/usa-spending`
- `/country`

## Production-oriented additions

- runtime config via environment variables
- health endpoint
- streamable HTTP transport
- structured HTTP request logging
- remote error shaping with retry-after exposure
- generated catalog resources and prompts
- standalone browser UI

## Remaining step outside this sandbox

Run the usual dependency and compile checks in a network-enabled Go environment:

```bash
go mod tidy
go test ./...
```
