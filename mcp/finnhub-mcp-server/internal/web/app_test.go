package web_test

import (
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
	"time"

	"finnhub-mcp-server/internal/finnhub"
	"finnhub-mcp-server/internal/mcpserver"
	"finnhub-mcp-server/internal/web"
)

func TestRegisterRoutesServesHTMLAndCatalogAPI(t *testing.T) {
	mux := http.NewServeMux()
	web.RegisterRoutes(mux, web.Options{
		BasePath: "/app",
		MCPPath:  "/mcp",
		Catalog:  newTestCatalog(),
	})

	htmlReq := httptest.NewRequest(http.MethodGet, "/app?tool=finnhub_symbol_search&missing=q", nil)
	htmlResp := httptest.NewRecorder()
	mux.ServeHTTP(htmlResp, htmlReq)
	if htmlResp.Code != http.StatusOK {
		t.Fatalf("GET /app returned %d", htmlResp.Code)
	}
	if !strings.Contains(htmlResp.Body.String(), "Finnhub MCP Web App") {
		t.Fatalf("unexpected web app HTML: %s", htmlResp.Body.String())
	}

	apiReq := httptest.NewRequest(http.MethodGet, "/app/api/tools?q=quote", nil)
	apiResp := httptest.NewRecorder()
	mux.ServeHTTP(apiResp, apiReq)
	if apiResp.Code != http.StatusOK {
		t.Fatalf("GET /app/api/tools returned %d", apiResp.Code)
	}
	if !strings.Contains(apiResp.Body.String(), "finnhub_quote") {
		t.Fatalf("unexpected API response: %s", apiResp.Body.String())
	}
}

func newTestCatalog() *mcpserver.Catalog {
	client := finnhub.NewClient("https://example.invalid", "test-token", "test-agent", time.Second)
	app := mcpserver.NewApplication(client, mcpserver.ApplicationOptions{})
	return app.Catalog()
}
