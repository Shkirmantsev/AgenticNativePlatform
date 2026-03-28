package mcpserver

import (
	"context"
	"log/slog"
	"net/url"
	"strings"

	"finnhub-mcp-server/internal/finnhub"

	"github.com/modelcontextprotocol/go-sdk/mcp"
)

// ImplementationVersion is stamped at build time. Local `go run` / `go test`
// fall back to "dev" unless the linker overrides it.
var ImplementationVersion = "dev"

type ApplicationOptions struct {
	PublicWebBaseURL string
}

type MarketDataClient interface {
	Get(context.Context, string, map[string]string) (*finnhub.Response, error)
}

// Application wires together the Finnhub client, the generated endpoint catalog,
// and the MCP primitives exposed by the server.
type Application struct {
	catalog          *Catalog
	client           MarketDataClient
	publicWebBaseURL string
}

// NewApplication creates a reusable application instance.
func NewApplication(client MarketDataClient, options ApplicationOptions) *Application {
	return &Application{
		catalog:          NewCatalog(),
		client:           client,
		publicWebBaseURL: strings.TrimRight(strings.TrimSpace(options.PublicWebBaseURL), "/"),
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
		Version: ImplementationVersion,
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

func (a *Application) buildElicitationURL(endpoint finnhub.EndpointSpec, arguments map[string]any, missingProperties map[string]any, message string) string {
	baseURL := a.publicWebBaseURL
	if baseURL == "" {
		baseURL = "/app"
	}

	values := url.Values{}
	values.Set("tool", endpoint.ToolName)
	if strings.TrimSpace(message) != "" {
		values.Set("message", message)
	}
	if len(arguments) > 0 {
		values.Set("args", compactJSON(arguments))
	}
	for _, key := range sortedKeys(missingProperties) {
		values.Add("missing", key)
	}

	if strings.Contains(baseURL, "?") {
		return baseURL + "&" + values.Encode()
	}
	return baseURL + "?" + values.Encode()
}
