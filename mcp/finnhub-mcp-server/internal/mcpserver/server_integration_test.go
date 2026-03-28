package mcpserver

import (
	"context"
	"io"
	"log/slog"
	"strings"
	"testing"

	"finnhub-mcp-server/internal/finnhub"

	"github.com/modelcontextprotocol/go-sdk/mcp"
)

func TestServerExposesToolsPromptsResourcesAndWebRoutes(t *testing.T) {
	app, cleanup := newTestApplication(t, "")
	defer cleanup()

	session, sessionCleanup := newClientSession(t, app, nil)
	defer sessionCleanup()

	ctx := context.Background()

	tools, err := session.ListTools(ctx, nil)
	if err != nil {
		t.Fatalf("ListTools(): %v", err)
	}
	if len(tools.Tools) < 10 {
		t.Fatalf("expected many tools, got %d", len(tools.Tools))
	}

	prompt, err := session.GetPrompt(ctx, &mcp.GetPromptParams{
		Name:      "discover_finnhub_tools",
		Arguments: map[string]string{"goal": "latest quote for Apple"},
	})
	if err != nil {
		t.Fatalf("GetPrompt(): %v", err)
	}
	if len(prompt.Messages) == 0 {
		t.Fatal("expected prompt messages")
	}

	resource, err := session.ReadResource(ctx, &mcp.ReadResourceParams{URI: resourceCatalogJSON})
	if err != nil {
		t.Fatalf("ReadResource(): %v", err)
	}
	if len(resource.Contents) == 0 || !strings.Contains(resource.Contents[0].Text, "finnhub_quote") {
		t.Fatalf("unexpected resource contents: %#v", resource.Contents)
	}
}

func TestEndpointToolUsesFormElicitationForMissingInputs(t *testing.T) {
	app, cleanup := newTestApplication(t, "")
	defer cleanup()

	session, sessionCleanup := newClientSession(t, app, &mcp.ClientOptions{
		ElicitationHandler: func(context.Context, *mcp.ElicitRequest) (*mcp.ElicitResult, error) {
			return &mcp.ElicitResult{
				Action:  "accept",
				Content: map[string]any{"q": "AAPL"},
			}, nil
		},
	})
	defer sessionCleanup()

	result, err := session.CallTool(context.Background(), &mcp.CallToolParams{
		Name:      "finnhub_symbol_search",
		Arguments: map[string]any{},
	})
	if err != nil {
		t.Fatalf("CallTool(): %v", err)
	}

	structured := mustStructuredMap(t, result.StructuredContent)
	requestMap := mustStructuredMap(t, structured["request"])
	query := mustStructuredMap(t, requestMap["query"])
	if got := query["q"]; got != "AAPL" {
		t.Fatalf("expected q=AAPL after elicitation, got %#v", got)
	}
}

func TestEndpointToolUsesURLElicitationWhenFormModeIsUnavailable(t *testing.T) {
	app, cleanup := newTestApplication(t, "https://ui.example/finnhub/app")
	defer cleanup()

	session, sessionCleanup := newClientSession(t, app, &mcp.ClientOptions{
		Capabilities: &mcp.ClientCapabilities{
			Elicitation: &mcp.ElicitationCapabilities{
				URL: &mcp.URLElicitationCapabilities{},
			},
		},
		ElicitationHandler: func(_ context.Context, request *mcp.ElicitRequest) (*mcp.ElicitResult, error) {
			if request.Params.Mode != "url" {
				t.Fatalf("expected url elicitation mode, got %q", request.Params.Mode)
			}
			if !strings.Contains(request.Params.URL, "https://ui.example/finnhub/app?") {
				t.Fatalf("expected public web app URL, got %q", request.Params.URL)
			}
			if !strings.Contains(request.Params.URL, "tool=finnhub_symbol_search") {
				t.Fatalf("expected tool query parameter in URL, got %q", request.Params.URL)
			}
			return &mcp.ElicitResult{
				Action:  "accept",
				Content: map[string]any{"q": "MSFT"},
			}, nil
		},
	})
	defer sessionCleanup()

	result, err := session.CallTool(context.Background(), &mcp.CallToolParams{
		Name:      "finnhub_symbol_search",
		Arguments: map[string]any{},
	})
	if err != nil {
		t.Fatalf("CallTool(): %v", err)
	}

	structured := mustStructuredMap(t, result.StructuredContent)
	requestMap := mustStructuredMap(t, structured["request"])
	query := mustStructuredMap(t, requestMap["query"])
	if got := query["q"]; got != "MSFT" {
		t.Fatalf("expected q=MSFT after URL elicitation, got %#v", got)
	}
}

func TestCatalogMatchToolsUsesSamplingWhenSupported(t *testing.T) {
	app, cleanup := newTestApplication(t, "")
	defer cleanup()

	session, sessionCleanup := newClientSession(t, app, &mcp.ClientOptions{
		CreateMessageHandler: func(context.Context, *mcp.CreateMessageRequest) (*mcp.CreateMessageResult, error) {
			return &mcp.CreateMessageResult{
				Content: &mcp.TextContent{Text: "sampled recommendation"},
				Model:   "test-model",
				Role:    "assistant",
			}, nil
		},
	})
	defer sessionCleanup()

	result, err := session.CallTool(context.Background(), &mcp.CallToolParams{
		Name: "catalog_match_tools",
		Arguments: map[string]any{
			"goal":           "Compare Nvidia earnings with recent company news",
			"preferSampling": true,
		},
	})
	if err != nil {
		t.Fatalf("CallTool(): %v", err)
	}

	structured := mustStructuredMap(t, result.StructuredContent)
	if got := structured["usedSampling"]; got != true {
		t.Fatalf("expected usedSampling=true, got %#v", got)
	}
	if recommendation := structured["recommendation"]; recommendation != "sampled recommendation" {
		t.Fatalf("unexpected recommendation: %#v", recommendation)
	}
}

func newTestApplication(t *testing.T, publicWebBaseURL string) (*Application, func()) {
	t.Helper()

	client := fakeMarketDataClient{}
	app := NewApplication(client, ApplicationOptions{
		PublicWebBaseURL: publicWebBaseURL,
	})

	return app, func() {}
}

func newClientSession(t *testing.T, app *Application, options *mcp.ClientOptions) (*mcp.ClientSession, func()) {
	t.Helper()

	ctx := context.Background()
	clientTransport, serverTransport := mcp.NewInMemoryTransports()
	server := app.NewServer(slog.New(slog.NewTextHandler(io.Discard, nil)))

	serverSession, err := server.Connect(ctx, serverTransport, nil)
	if err != nil {
		t.Fatalf("server.Connect(): %v", err)
	}

	client := mcp.NewClient(&mcp.Implementation{Name: "test-client", Version: "v0.0.1"}, options)
	clientSession, err := client.Connect(ctx, clientTransport, nil)
	if err != nil {
		t.Fatalf("client.Connect(): %v", err)
	}

	return clientSession, func() {
		clientSession.Close()
		serverSession.Wait()
	}
}

func mustStructuredMap(t *testing.T, value any) map[string]any {
	t.Helper()

	result, ok := value.(map[string]any)
	if !ok {
		t.Fatalf("expected map[string]any, got %T", value)
	}
	return result
}

type fakeMarketDataClient struct{}

func (fakeMarketDataClient) Get(_ context.Context, endpointPath string, query map[string]string) (*finnhub.Response, error) {
	return &finnhub.Response{
		StatusCode: 200,
		Data: map[string]any{
			"path":  endpointPath,
			"query": query,
		},
	}, nil
}
