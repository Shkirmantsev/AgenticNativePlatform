package config

import (
	"fmt"
	"os"
	"strconv"
	"strings"
	"time"
)

const (
	defaultHTTPAddress = ":8080"
	defaultMCPPath     = "/mcp"
	defaultWebAppPath  = "/app"
	defaultBaseURL     = "https://finnhub.io/api/v1"
	defaultUserAgent   = "finnhub-mcp-server/1.0"
	defaultTimeout     = 20 * time.Second
)

// Config stores all runtime configuration for the MCP server.
//
// The server supports both stdio and HTTP transports. When HTTP mode is used,
// the MCP protocol is served on MCPPath and the human-friendly tool browser is
// served on WebAppPath.
type Config struct {
	APIKey           string
	BaseURL          string
	UserAgent        string
	HTTPAddress      string
	MCPPath          string
	WebAppPath       string
	PublicWebBaseURL string
	RequestTimeout   time.Duration
	EnableRPCLogs    bool
}

// LoadFromEnv builds a Config from environment variables.
//
// Required:
//   - FINNHUB_API_TOKEN
//
// Optional:
//   - FINNHUB_BASE_URL
//   - FINNHUB_USER_AGENT
//   - FINNHUB_REQUEST_TIMEOUT_SECONDS
//   - FINNHUB_MCP_PATH
//   - FINNHUB_WEB_APP_PATH
//   - FINNHUB_PUBLIC_WEB_BASE_URL
//   - FINNHUB_HTTP_ADDR
//   - FINNHUB_ENABLE_RPC_LOGS
func LoadFromEnv() (Config, error) {
	timeoutSeconds := readInt("FINNHUB_REQUEST_TIMEOUT_SECONDS", int(defaultTimeout/time.Second))
	cfg := Config{
		APIKey:           strings.TrimSpace(os.Getenv("FINNHUB_API_TOKEN")),
		BaseURL:          readString("FINNHUB_BASE_URL", defaultBaseURL),
		UserAgent:        readString("FINNHUB_USER_AGENT", defaultUserAgent),
		HTTPAddress:      readString("FINNHUB_HTTP_ADDR", defaultHTTPAddress),
		MCPPath:          normalizePath(readString("FINNHUB_MCP_PATH", defaultMCPPath)),
		WebAppPath:       normalizePath(readString("FINNHUB_WEB_APP_PATH", defaultWebAppPath)),
		PublicWebBaseURL: normalizeBaseURL(readString("FINNHUB_PUBLIC_WEB_BASE_URL", "")),
		RequestTimeout:   time.Duration(timeoutSeconds) * time.Second,
		EnableRPCLogs:    readBool("FINNHUB_ENABLE_RPC_LOGS", false),
	}

	if cfg.APIKey == "" {
		return Config{}, fmt.Errorf("FINNHUB_API_TOKEN is required")
	}
	if cfg.MCPPath == cfg.WebAppPath {
		return Config{}, fmt.Errorf("FINNHUB_MCP_PATH and FINNHUB_WEB_APP_PATH must be different")
	}
	return cfg, nil
}

func readString(key, fallback string) string {
	value := strings.TrimSpace(os.Getenv(key))
	if value == "" {
		return fallback
	}
	return value
}

func readInt(key string, fallback int) int {
	raw := strings.TrimSpace(os.Getenv(key))
	if raw == "" {
		return fallback
	}
	value, err := strconv.Atoi(raw)
	if err != nil || value <= 0 {
		return fallback
	}
	return value
}

func readBool(key string, fallback bool) bool {
	raw := strings.TrimSpace(os.Getenv(key))
	if raw == "" {
		return fallback
	}
	value, err := strconv.ParseBool(raw)
	if err != nil {
		return fallback
	}
	return value
}

func normalizePath(path string) string {
	path = strings.TrimSpace(path)
	if path == "" {
		return "/"
	}
	if !strings.HasPrefix(path, "/") {
		path = "/" + path
	}
	if path != "/" {
		path = strings.TrimRight(path, "/")
	}
	return path
}

func normalizeBaseURL(value string) string {
	value = strings.TrimSpace(value)
	if value == "" {
		return ""
	}
	return strings.TrimRight(value, "/")
}
