package main

import (
	"io"
	"net/http"

	"github.com/modelcontextprotocol/go-sdk/mcp"
)

const mcpSessionIDHeader = "Mcp-Session-Id"

// newAgentGatewayCompatibleStreamableHandler wraps the Go SDK streamable HTTP
// handler so proxies that buffer until the first response bytes still see an
// immediately established standalone SSE stream.
func newAgentGatewayCompatibleStreamableHandler(getServer func(*http.Request) *mcp.Server, opts *mcp.StreamableHTTPOptions) http.Handler {
	return &agentGatewayCompatibleStreamableHandler{
		inner: mcp.NewStreamableHTTPHandler(getServer, opts),
	}
}

type agentGatewayCompatibleStreamableHandler struct {
	inner http.Handler
}

func (h *agentGatewayCompatibleStreamableHandler) ServeHTTP(w http.ResponseWriter, r *http.Request) {
	switch r.Method {
	case http.MethodPost:
		h.inner.ServeHTTP(w, r)
	case http.MethodDelete:
		h.inner.ServeHTTP(w, r)
	case http.MethodGet:
		// AgentGateway rewrites the public session identifier between the
		// initialize response and the hanging GET it opens for server events.
		// Matching GET requests against session IDs observed during initialize
		// therefore misses valid sessions and leaves the buffering proxy waiting
		// for the first body bytes forever. Prime every MCP GET stream instead.
		writeStandaloneSSEPreamble(w)
		h.inner.ServeHTTP(newStartedSSEStreamResponseWriter(w), r)
	default:
		h.inner.ServeHTTP(w, r)
	}
}

func writeStandaloneSSEPreamble(w http.ResponseWriter) {
	headers := w.Header()
	headers.Set("Cache-Control", "no-cache, no-transform")
	headers.Set("Content-Type", "text/event-stream")
	headers.Set("Connection", "keep-alive")
	w.WriteHeader(http.StatusOK)
	_, _ = io.WriteString(w, ": agentgateway-preamble\n\n")
	if flusher, ok := w.(http.Flusher); ok {
		flusher.Flush()
	}
}

type startedSSEStreamResponseWriter struct {
	http.ResponseWriter
	header http.Header
}

func newStartedSSEStreamResponseWriter(w http.ResponseWriter) *startedSSEStreamResponseWriter {
	return &startedSSEStreamResponseWriter{
		ResponseWriter: w,
		header:         make(http.Header),
	}
}

func (w *startedSSEStreamResponseWriter) Header() http.Header {
	return w.header
}

func (w *startedSSEStreamResponseWriter) WriteHeader(int) {}

func (w *startedSSEStreamResponseWriter) Write(p []byte) (int, error) {
	return w.ResponseWriter.Write(p)
}

func (w *startedSSEStreamResponseWriter) Flush() {
	if flusher, ok := w.ResponseWriter.(http.Flusher); ok {
		flusher.Flush()
	}
}
