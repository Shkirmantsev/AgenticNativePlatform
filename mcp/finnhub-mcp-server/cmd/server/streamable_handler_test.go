package main

import (
	"context"
	"encoding/json"
	"io"
	"log/slog"
	"net/http"
	"net/http/httptest"
	"net/url"
	"strings"
	"testing"
	"time"

	"finnhub-mcp-server/internal/finnhub"
	"finnhub-mcp-server/internal/mcpserver"

	"github.com/modelcontextprotocol/go-sdk/mcp"
)

func TestAgentGatewayCompatibleStreamableHandlerAllowsBufferingProxyConnect(t *testing.T) {
	t.Parallel()

	handler := newTestFinnhubHTTPHandler(t)
	origin := httptest.NewServer(handler)
	defer origin.Close()

	target, err := url.Parse(origin.URL)
	if err != nil {
		t.Fatalf("url.Parse(origin.URL): %v", err)
	}

	proxy := httptest.NewServer(newFirstBodyByteProxy(t, target))
	defer proxy.Close()

	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()

	client := mcp.NewClient(&mcp.Implementation{Name: "test-client", Version: "v0.0.1"}, nil)
	session, err := client.Connect(ctx, &mcp.StreamableClientTransport{
		Endpoint: proxy.URL,
	}, nil)
	if err != nil {
		t.Fatalf("client.Connect(): %v", err)
	}
	defer session.Close()

	tools, err := session.ListTools(ctx, nil)
	if err != nil {
		t.Fatalf("ListTools(): %v", err)
	}
	if len(tools.Tools) < 10 {
		t.Fatalf("expected many tools, got %d", len(tools.Tools))
	}
}

func TestAgentGatewayCompatibleStreamableHandlerPrimesUnknownSessionGET(t *testing.T) {
	t.Parallel()

	handler := newTestFinnhubHTTPHandler(t)
	req := httptest.NewRequest(http.MethodGet, "/mcp", nil)
	req.Header.Set("Accept", "text/event-stream")
	req.Header.Set(mcpSessionIDHeader, "agentgateway-rewritten-session")

	rec := httptest.NewRecorder()
	handler.ServeHTTP(rec, req)

	resp := rec.Result()
	if got := resp.StatusCode; got != http.StatusOK {
		t.Fatalf("expected 200, got %d", got)
	}
	if got := resp.Header.Get("Content-Type"); got != "text/event-stream" {
		t.Fatalf("expected text/event-stream, got %q", got)
	}
	if body := rec.Body.String(); !strings.HasPrefix(body, ": agentgateway-preamble\n\n") {
		t.Fatalf("expected SSE preamble body, got %q", body)
	}
}

func TestRequestLoggingMiddlewarePreservesFlushForInitialize(t *testing.T) {
	t.Parallel()

	handler := requestLoggingMiddleware(
		slog.New(slog.NewTextHandler(io.Discard, nil)),
		newTestFinnhubHTTPHandler(t),
	)

	body, err := json.Marshal(map[string]any{
		"jsonrpc": "2.0",
		"id":      1,
		"method":  "initialize",
		"params": map[string]any{
			"protocolVersion": "2025-03-26",
			"capabilities":    map[string]any{},
			"clientInfo": map[string]any{
				"name":    "test-client",
				"version": "v0.0.1",
			},
		},
	})
	if err != nil {
		t.Fatalf("json.Marshal(): %v", err)
	}

	req := httptest.NewRequest(http.MethodPost, "/mcp", strings.NewReader(string(body)))
	req.Header.Set("Content-Type", "application/json")
	req.Header.Set("Accept", "application/json, text/event-stream")

	rec := newFlushTrackingResponseRecorder()
	handler.ServeHTTP(rec, req)

	resp := rec.Result()
	if got := resp.StatusCode; got != http.StatusOK {
		t.Fatalf("expected 200, got %d", got)
	}
	if rec.flushCount == 0 {
		t.Fatalf("expected initialize response to flush the SSE body")
	}
	if body := rec.Body.String(); !strings.Contains(body, "result") {
		t.Fatalf("expected initialize response body, got %q", body)
	}
}

func newTestFinnhubHTTPHandler(t *testing.T) http.Handler {
	t.Helper()

	app := mcpserver.NewApplication(fakeMarketDataClient{}, mcpserver.ApplicationOptions{})
	server := app.NewServer(slog.New(slog.NewTextHandler(io.Discard, nil)))

	return newAgentGatewayCompatibleStreamableHandler(func(*http.Request) *mcp.Server {
		return server
	}, &mcp.StreamableHTTPOptions{
		SessionTimeout: 30 * time.Minute,
		Logger:         slog.New(slog.NewTextHandler(io.Discard, nil)),
	})
}

// newFirstBodyByteProxy mimics a buffering intermediary that does not release
// response headers until the upstream server produces body bytes.
func newFirstBodyByteProxy(t *testing.T, target *url.URL) http.Handler {
	t.Helper()

	transport := http.DefaultTransport
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		upstream := r.Clone(r.Context())
		upstream.URL.Scheme = target.Scheme
		upstream.URL.Host = target.Host
		upstream.RequestURI = ""
		upstream.Host = target.Host

		resp, err := transport.RoundTrip(upstream)
		if err != nil {
			http.Error(w, err.Error(), http.StatusBadGateway)
			return
		}
		defer resp.Body.Close()

		firstByte := make([]byte, 1)
		n, readErr := resp.Body.Read(firstByte)
		if readErr != nil && readErr != io.EOF {
			http.Error(w, readErr.Error(), http.StatusBadGateway)
			return
		}

		for key, values := range resp.Header {
			for _, value := range values {
				w.Header().Add(key, value)
			}
		}
		w.WriteHeader(resp.StatusCode)
		if n > 0 {
			if _, err := w.Write(firstByte[:n]); err != nil {
				return
			}
			if flusher, ok := w.(http.Flusher); ok {
				flusher.Flush()
			}
		}
		if readErr == io.EOF {
			return
		}
		_, _ = io.Copy(w, resp.Body)
	})
}

type fakeMarketDataClient struct{}

type flushTrackingResponseRecorder struct {
	*httptest.ResponseRecorder
	flushCount int
}

func newFlushTrackingResponseRecorder() *flushTrackingResponseRecorder {
	return &flushTrackingResponseRecorder{
		ResponseRecorder: httptest.NewRecorder(),
	}
}

func (r *flushTrackingResponseRecorder) Flush() {
	r.flushCount++
	r.ResponseRecorder.Flush()
}

func (fakeMarketDataClient) Get(_ context.Context, endpointPath string, query map[string]string) (*finnhub.Response, error) {
	return &finnhub.Response{
		StatusCode: 200,
		Data: map[string]any{
			"path":  endpointPath,
			"query": query,
		},
	}, nil
}
