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
		Instructions: "Use catalog_list_tools or catalog_match_tools to discover the best Finnhub tools before calling endpoint tools directly. Endpoint tools support elicitation for missing required inputs when the client allows it.",
	})

	a.registerEndpointTools(server)
	a.registerCatalogTools(server)
	a.registerPrompts(server)
	a.registerResources(server)
	return server
}
