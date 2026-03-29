package main

import (
	"context"
	"encoding/json"
	"errors"
	"flag"
	"fmt"
	"log/slog"
	"net/http"
	"os"
	"strings"
	"time"

	"finnhub-mcp-server/internal/config"
	"finnhub-mcp-server/internal/finnhub"
	"finnhub-mcp-server/internal/mcpserver"
	"finnhub-mcp-server/internal/web"

	"github.com/modelcontextprotocol/go-sdk/mcp"
)

const (
	transportStdio = "stdio"
	transportHTTP  = "http"
)

// main selects the transport, loads runtime configuration, and starts the
// Finnhub MCP server.
//
// Supported modes:
//   - stdio: preferred for desktop MCP clients.
//   - http: streamable HTTP transport plus a browser tool picker page.
func main() {
	transportMode := flag.String("transport", transportStdio, "transport mode: stdio or http")
	httpAddressOverride := flag.String("http-addr", "", "override FINNHUB_HTTP_ADDR when -transport=http")
	flag.Parse()

	if err := run(*transportMode, *httpAddressOverride); err != nil {
		fmt.Fprintf(os.Stderr, "error: %v\n", err)
		os.Exit(1)
	}
}

func run(transportMode, httpAddressOverride string) error {
	cfg, err := config.LoadFromEnv()
	if err != nil {
		return err
	}
	if strings.TrimSpace(httpAddressOverride) != "" {
		cfg.HTTPAddress = strings.TrimSpace(httpAddressOverride)
	}

	logger := newLogger()
	finnhubClient := finnhub.NewClient(cfg.BaseURL, cfg.APIKey, cfg.UserAgent, cfg.RequestTimeout)
	publicWebBaseURL := cfg.PublicWebBaseURL
	if publicWebBaseURL == "" {
		publicWebBaseURL = cfg.WebAppPath
	}
	app := mcpserver.NewApplication(finnhubClient, mcpserver.ApplicationOptions{
		PublicWebBaseURL: publicWebBaseURL,
	})
	server := app.NewServer(logger)

	switch strings.ToLower(strings.TrimSpace(transportMode)) {
	case "", transportStdio:
		return runStdio(server, cfg.EnableRPCLogs)
	case transportHTTP:
		return runHTTP(server, app, cfg, logger)
	default:
		return fmt.Errorf("unsupported transport %q, expected %q or %q", transportMode, transportStdio, transportHTTP)
	}
}

func runStdio(server *mcp.Server, enableRPCLogs bool) error {
	var transport mcp.Transport = &mcp.StdioTransport{}
	if enableRPCLogs {
		transport = &mcp.LoggingTransport{Transport: transport, Writer: os.Stderr}
	}
	return server.Run(context.Background(), transport)
}

func runHTTP(server *mcp.Server, app *mcpserver.Application, cfg config.Config, logger *slog.Logger) error {
	mux := http.NewServeMux()

	mux.HandleFunc("/healthz", func(w http.ResponseWriter, _ *http.Request) {
		writeJSON(w, http.StatusOK, map[string]any{
			"status": "ok",
			"name":   "finnhub-mcp-server",
		})
	})

	httpOptions := &mcp.StreamableHTTPOptions{
		// Prefer the default SSE-capable response mode. Inventory discovers this
		// server through AgentGateway, and JSON-only streamable responses caused
		// the follow-up initialized notification to arrive after the session had
		// already expired.
		SessionTimeout: 30 * time.Minute,
		Logger:         logger,
	}
	mux.Handle(cfg.MCPPath, newAgentGatewayCompatibleStreamableHandler(func(*http.Request) *mcp.Server {
		return server
	}, httpOptions))

	web.RegisterRoutes(mux, web.Options{
		BasePath: cfg.WebAppPath,
		MCPPath:  cfg.MCPPath,
		Catalog:  app.Catalog(),
	})

	mux.HandleFunc("/", func(w http.ResponseWriter, r *http.Request) {
		if r.URL.Path != "/" {
			http.NotFound(w, r)
			return
		}
		http.Redirect(w, r, cfg.WebAppPath, http.StatusTemporaryRedirect)
	})

	httpServer := &http.Server{
		Addr:              cfg.HTTPAddress,
		Handler:           requestLoggingMiddleware(logger, mux),
		ReadHeaderTimeout: 10 * time.Second,
		// Streamable HTTP clients keep a hanging GET open for server events.
		// A short HTTP idle timeout closes that stream before the MCP session is
		// done, which breaks follow-up initialized/tools calls through
		// AgentGateway and Inventory discovery.
		IdleTimeout: 0,
	}

	logger.Info("starting streamable HTTP server", "addr", cfg.HTTPAddress, "mcpPath", cfg.MCPPath, "webAppPath", cfg.WebAppPath)
	err := httpServer.ListenAndServe()
	if errors.Is(err, http.ErrServerClosed) {
		return nil
	}
	return err
}

func requestLoggingMiddleware(logger *slog.Logger, next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		start := time.Now()
		rw := &statusWriter{ResponseWriter: w, status: http.StatusOK}
		next.ServeHTTP(rw, r)
		logger.Info("http request",
			"method", r.Method,
			"path", r.URL.Path,
			"status", rw.status,
			"duration", time.Since(start).String(),
		)
	})
}

func writeJSON(w http.ResponseWriter, status int, payload any) {
	w.Header().Set("Content-Type", "application/json; charset=utf-8")
	w.WriteHeader(status)
	encoder := json.NewEncoder(w)
	encoder.SetIndent("", "  ")
	if err := encoder.Encode(payload); err != nil {
		http.Error(w, err.Error(), http.StatusInternalServerError)
	}
}

type statusWriter struct {
	http.ResponseWriter
	status int
}

func (w *statusWriter) WriteHeader(status int) {
	w.status = status
	w.ResponseWriter.WriteHeader(status)
}

func newLogger() *slog.Logger {
	return slog.New(slog.NewTextHandler(os.Stderr, &slog.HandlerOptions{Level: slog.LevelInfo}))
}
