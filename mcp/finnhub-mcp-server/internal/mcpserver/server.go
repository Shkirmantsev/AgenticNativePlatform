package mcpserver

import (
	"log/slog"

	"finnhub-mcp-server/internal/finnhub"

	"github.com/modelcontextprotocol/go-sdk/mcp"
)

// Application wires together the Finnhub client, the generated endpoint catalog,
// and the MCP primitives exposed by the server.
type Application struct {
	catalog *Catalog
	client  *finnhub.Client
}

// NewApplication creates a reusable application instance.
func NewApplication(client *finnhub.Client) *Application {
	return &Application{
		catalog: NewCatalog(),
		client:  client,
	}
}

// Catalog exposes the catalog to the web UI layer.
func (a *Application) Catalog() *Catalog {
	return a.catalog
}

// NewServer builds a fully registered MCP server with a small amount of
// production-oriented metadata for clients.
func (a *Application) NewServer(logger *slog.Logger) *mcp.Server {
	server := mcp.NewServer(&mcp.Implementation{
		Name:    "finnhub-mcp-server",
		Version: "1.0.0",
	}, &mcp.ServerOptions{
		Logger:       logger,
		Instructions: "You are a Finnhub market-data tool server. Prefer catalog_match_tools when the user request is ambiguous, refers to a company name instead of a ticker, or needs a multi-step Finnhub workflow. Use catalog_get_tool_details when you need richer natural-language guidance for one specific tool. Call endpoint tools directly only after the required arguments are known. If required inputs are missing, endpoint tools support elicitation when the client allows it. Keep plans concrete: identify the likely tool order, the parameters still missing, and a safe starter payload for the next call.",
	})

	a.registerEndpointTools(server)
	a.registerCatalogTools(server)
	a.registerPrompts(server)
	a.registerResources(server)
	return server
}
