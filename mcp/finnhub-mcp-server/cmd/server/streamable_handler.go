package main

import (
	"io"
	"net/http"
	"strings"
	"sync"

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

	// knownSessions tracks session IDs returned during initialize so we only
	// pre-prime GET requests for sessions we issued ourselves.
	knownSessions sync.Map
}

func (h *agentGatewayCompatibleStreamableHandler) ServeHTTP(w http.ResponseWriter, r *http.Request) {
	sessionID := strings.TrimSpace(r.Header.Get(mcpSessionIDHeader))

	switch r.Method {
	case http.MethodPost:
		h.inner.ServeHTTP(&sessionTrackingResponseWriter{
			ResponseWriter: w,
			onSessionID:    h.rememberSessionID,
		}, r)
	case http.MethodDelete:
		h.inner.ServeHTTP(w, r)
		if sessionID != "" {
			h.knownSessions.Delete(sessionID)
		}
	case http.MethodGet:
		if sessionID != "" {
			if _, ok := h.knownSessions.Load(sessionID); ok {
				writeStandaloneSSEPreamble(w)
				h.inner.ServeHTTP(newStartedSSEStreamResponseWriter(w), r)
				return
			}
		}
		h.inner.ServeHTTP(w, r)
	default:
		h.inner.ServeHTTP(w, r)
	}
}

func (h *agentGatewayCompatibleStreamableHandler) rememberSessionID(sessionID string) {
	if sessionID == "" {
		return
	}
	h.knownSessions.Store(sessionID, struct{}{})
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

type sessionTrackingResponseWriter struct {
	http.ResponseWriter
	onSessionID func(string)
	wroteHeader bool
}

func (w *sessionTrackingResponseWriter) WriteHeader(statusCode int) {
	if !w.wroteHeader {
		w.captureSessionID()
		w.wroteHeader = true
	}
	w.ResponseWriter.WriteHeader(statusCode)
}

func (w *sessionTrackingResponseWriter) Write(p []byte) (int, error) {
	if !w.wroteHeader {
		w.WriteHeader(http.StatusOK)
	}
	return w.ResponseWriter.Write(p)
}

func (w *sessionTrackingResponseWriter) Flush() {
	if flusher, ok := w.ResponseWriter.(http.Flusher); ok {
		flusher.Flush()
	}
}

func (w *sessionTrackingResponseWriter) captureSessionID() {
	if w.onSessionID == nil {
		return
	}
	w.onSessionID(strings.TrimSpace(w.ResponseWriter.Header().Get(mcpSessionIDHeader)))
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
