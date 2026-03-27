package web

import (
	"embed"
	"encoding/json"
	"fmt"
	"html/template"
	"net/http"
	"strings"

	"finnhub-mcp-server/internal/mcpserver"
)

//go:embed static/index.html
var assets embed.FS

// Options contains the runtime values required by the browser-based tool picker.
type Options struct {
	BasePath string
	MCPPath  string
	Catalog  *mcpserver.Catalog
}

// RegisterRoutes exposes the HTML application and its JSON helper endpoints.
func RegisterRoutes(mux *http.ServeMux, options Options) {
	basePath := normalizeBasePath(options.BasePath)
	mux.HandleFunc(basePath, serveIndex(options))
	mux.HandleFunc(basePath+"/", serveIndex(options))
	mux.HandleFunc(basePath+"/api/tools", serveToolCatalog(options))
	mux.HandleFunc(basePath+"/api/tools/", serveToolDetails(options))
}

func serveIndex(options Options) http.HandlerFunc {
	page := template.Must(template.ParseFS(assets, "static/index.html"))

	type pageData struct {
		BasePath string
		MCPPath  string
		Title    string
	}

	return func(w http.ResponseWriter, r *http.Request) {
		if r.Method != http.MethodGet {
			http.Error(w, "method not allowed", http.StatusMethodNotAllowed)
			return
		}
		w.Header().Set("Content-Type", "text/html; charset=utf-8")
		if err := page.Execute(w, pageData{
			BasePath: normalizeBasePath(options.BasePath),
			MCPPath:  options.MCPPath,
			Title:    "Finnhub MCP Web App",
		}); err != nil {
			http.Error(w, err.Error(), http.StatusInternalServerError)
		}
	}
}

func serveToolCatalog(options Options) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		if r.Method != http.MethodGet {
			http.Error(w, "method not allowed", http.StatusMethodNotAllowed)
			return
		}

		query := strings.TrimSpace(r.URL.Query().Get("q"))
		group := strings.TrimSpace(r.URL.Query().Get("group"))
		items := options.Catalog.Search(query, group, nil, 0)

		writeJSON(w, http.StatusOK, map[string]any{
			"basePath": normalizeBasePath(options.BasePath),
			"mcpPath":  options.MCPPath,
			"groups":   options.Catalog.Groups(),
			"count":    len(items),
			"tools":    items,
		})
	}
}

func serveToolDetails(options Options) http.HandlerFunc {
	prefix := normalizeBasePath(options.BasePath) + "/api/tools/"

	return func(w http.ResponseWriter, r *http.Request) {
		if r.Method != http.MethodGet {
			http.Error(w, "method not allowed", http.StatusMethodNotAllowed)
			return
		}
		name := strings.TrimSpace(strings.TrimPrefix(r.URL.Path, prefix))
		if name == "" || name == r.URL.Path {
			http.NotFound(w, r)
			return
		}
		item, found := options.Catalog.Find(name)
		if !found {
			writeJSON(w, http.StatusNotFound, map[string]any{
				"error": fmt.Sprintf("tool %q was not found", name),
			})
			return
		}
		writeJSON(w, http.StatusOK, item)
	}
}

func writeJSON(w http.ResponseWriter, status int, payload any) {
	w.Header().Set("Content-Type", "application/json; charset=utf-8")
	w.WriteHeader(status)
	encoder := json.NewEncoder(w)
	encoder.SetIndent("", "  ")
	_ = encoder.Encode(payload)
}

func normalizeBasePath(path string) string {
	path = strings.TrimSpace(path)
	if path == "" {
		return "/app"
	}
	if !strings.HasPrefix(path, "/") {
		path = "/" + path
	}
	if path != "/" {
		path = strings.TrimRight(path, "/")
	}
	return path
}
