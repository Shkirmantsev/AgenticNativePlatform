package mcpserver

import (
	"context"
	"strings"

	"finnhub-mcp-server/internal/finnhub"

	"github.com/modelcontextprotocol/go-sdk/mcp"
)

const (
	resourceCatalogJSON = "finnhub://catalog/tools.json"
	resourceCatalogMD   = "finnhub://catalog/tools.md"
	resourceSwaggerFree = "finnhub://catalog/free-endpoints.json"
)

func (a *Application) registerResources(server *mcp.Server) {
	server.AddResource(&mcp.Resource{
		URI:         resourceCatalogJSON,
		Name:        "finnhub-catalog-json",
		Title:       "Finnhub Tool Catalog (JSON)",
		Description: "Machine-readable catalog of all generated Finnhub tools, including natural-language usage guidance, example prompts, and example arguments.",
		MIMEType:    "application/json",
	}, a.handleCatalogJSONResource)

	server.AddResource(&mcp.Resource{
		URI:         resourceCatalogMD,
		Name:        "finnhub-catalog-markdown",
		Title:       "Finnhub Tool Catalog (Markdown)",
		Description: "Human-readable catalog of all generated Finnhub tools for operators and agents deciding how to answer a finance question.",
		MIMEType:    "text/markdown",
	}, a.handleCatalogMarkdownResource)

	server.AddResource(&mcp.Resource{
		URI:         resourceSwaggerFree,
		Name:        "finnhub-free-endpoints-json",
		Title:       "Free Finnhub Endpoints (JSON)",
		Description: "JSON catalog of the free endpoints derived from the supplied Finnhub swagger schema. Use this when you need the raw endpoint inventory instead of the human-friendly catalog view.",
		MIMEType:    "application/json",
	}, a.handleCatalogJSONResource)

	server.AddResourceTemplate(&mcp.ResourceTemplate{
		URITemplate: "finnhub://catalog/tool/{toolName}.json",
		Name:        "finnhub-tool-json-template",
		Title:       "One Finnhub Tool",
		Description: "Read one tool definition by tool name, including usage guidance, example prompts, and example arguments.",
		MIMEType:    "application/json",
	}, a.handleToolTemplateResource)
}

func (a *Application) handleCatalogJSONResource(_ context.Context, request *mcp.ReadResourceRequest) (*mcp.ReadResourceResult, error) {
	var text string
	switch request.Params.URI {
	case resourceSwaggerFree:
		text = jsonText(map[string]any{
			"count":     len(finnhub.FreeEndpointSpecs),
			"endpoints": finnhub.FreeEndpointSpecs,
		})
	default:
		payload, err := a.catalog.JSON()
		if err != nil {
			return nil, err
		}
		text = string(payload)
	}
	return &mcp.ReadResourceResult{
		Contents: []*mcp.ResourceContents{{
			URI:      request.Params.URI,
			MIMEType: "application/json",
			Text:     text,
		}},
	}, nil
}

func (a *Application) handleCatalogMarkdownResource(_ context.Context, request *mcp.ReadResourceRequest) (*mcp.ReadResourceResult, error) {
	return &mcp.ReadResourceResult{
		Contents: []*mcp.ResourceContents{{
			URI:      request.Params.URI,
			MIMEType: "text/markdown",
			Text:     a.catalog.Markdown(),
		}},
	}, nil
}

func (a *Application) handleToolTemplateResource(_ context.Context, request *mcp.ReadResourceRequest) (*mcp.ReadResourceResult, error) {
	const prefix = "finnhub://catalog/tool/"
	const suffix = ".json"
	uri := request.Params.URI
	if !strings.HasPrefix(uri, prefix) || !strings.HasSuffix(uri, suffix) {
		return nil, mcp.ResourceNotFoundError(uri)
	}
	toolName := strings.TrimSuffix(strings.TrimPrefix(uri, prefix), suffix)
	item, found := a.catalog.Find(toolName)
	if !found {
		return nil, mcp.ResourceNotFoundError(uri)
	}
	return &mcp.ReadResourceResult{
		Contents: []*mcp.ResourceContents{{
			URI:      uri,
			MIMEType: "application/json",
			Text:     jsonText(item),
		}},
	}, nil
}
