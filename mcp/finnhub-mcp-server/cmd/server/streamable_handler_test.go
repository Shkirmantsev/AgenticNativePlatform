package main

import (
	"context"
	"io"
	"log/slog"
	"net/http"
	"net/http/httptest"
	"net/url"
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

func (fakeMarketDataClient) Get(_ context.Context, endpointPath string, query map[string]string) (*finnhub.Response, error) {
	return &finnhub.Response{
		StatusCode: 200,
		Data: map[string]any{
			"path":  endpointPath,
			"query": query,
		},
	}, nil
}
