package mcpserver

import (
	"encoding/json"
	"fmt"
	"sort"
	"strings"

	"finnhub-mcp-server/internal/finnhub"
)

// CatalogItem is the human-facing representation of one generated MCP tool.
type CatalogItem struct {
	ToolName         string         `json:"toolName"`
	OperationID      string         `json:"operationId"`
	Title            string         `json:"title"`
	Summary          string         `json:"summary"`
	Description      string         `json:"description"`
	Group            string         `json:"group"`
	FreeTier         string         `json:"freeTier,omitempty"`
	InputSchema      map[string]any `json:"inputSchema"`
	ExampleArguments map[string]any `json:"exampleArguments"`
	PromptHint       string         `json:"promptHint"`
	EndpointPath     string         `json:"endpointPath"`
	Method           string         `json:"method"`
}

// Catalog exposes the generated Finnhub tools in a format suitable for MCP
// tools, resources, prompts, and the web UI.
type Catalog struct {
	endpoints []finnhub.EndpointSpec
}

// NewCatalog creates a catalog backed by the generated endpoint list.
func NewCatalog() *Catalog {
	endpoints := make([]finnhub.EndpointSpec, len(finnhub.FreeEndpointSpecs))
	copy(endpoints, finnhub.FreeEndpointSpecs)
	return &Catalog{endpoints: endpoints}
}

// Items returns all tools in stable order.
func (c *Catalog) Items() []CatalogItem {
	items := make([]CatalogItem, 0, len(c.endpoints))
	for _, endpoint := range c.endpoints {
		items = append(items, newCatalogItem(endpoint))
	}
	sort.Slice(items, func(i, j int) bool {
		if items[i].Group == items[j].Group {
			return items[i].ToolName < items[j].ToolName
		}
		return items[i].Group < items[j].Group
	})
	return items
}

// Find returns one catalog item by tool name.
func (c *Catalog) Find(toolName string) (CatalogItem, bool) {
	endpoint, found := finnhub.FindEndpointByToolName(toolName)
	if !found {
		return CatalogItem{}, false
	}
	return newCatalogItem(endpoint), true
}

// Search filters the catalog by free-text query, group and explicit tool names.
func (c *Catalog) Search(query, group string, names []string, limit int) []CatalogItem {
	allowedNames := make(map[string]struct{})
	for _, name := range names {
		name = strings.TrimSpace(name)
		if name != "" {
			allowedNames[name] = struct{}{}
		}
	}

	queryTokens := tokenize(query)
	group = strings.TrimSpace(strings.ToLower(group))

	type rankedItem struct {
		item  CatalogItem
		score int
	}

	ranked := make([]rankedItem, 0, len(c.endpoints))
	for _, endpoint := range c.endpoints {
		item := newCatalogItem(endpoint)
		if group != "" && strings.ToLower(item.Group) != group {
			continue
		}
		if len(allowedNames) > 0 {
			if _, ok := allowedNames[item.ToolName]; !ok {
				continue
			}
		}
		score := rankCatalogItem(item, queryTokens)
		if len(queryTokens) > 0 && score == 0 {
			continue
		}
		ranked = append(ranked, rankedItem{item: item, score: score})
	}

	sort.Slice(ranked, func(i, j int) bool {
		if ranked[i].score == ranked[j].score {
			return ranked[i].item.ToolName < ranked[j].item.ToolName
		}
		return ranked[i].score > ranked[j].score
	})

	if limit > 0 && len(ranked) > limit {
		ranked = ranked[:limit]
	}

	result := make([]CatalogItem, 0, len(ranked))
	for _, item := range ranked {
		result = append(result, item.item)
	}
	return result
}

// JSON returns the complete catalog as pretty JSON.
func (c *Catalog) JSON() ([]byte, error) {
	payload := map[string]any{
		"groups": c.Groups(),
		"tools":  c.Items(),
	}
	return json.MarshalIndent(payload, "", "  ")
}

// Markdown renders the catalog as a compact operator-friendly Markdown document.
func (c *Catalog) Markdown() string {
	var b strings.Builder
	b.WriteString("# Finnhub MCP Tool Catalog\n\n")
	for _, group := range c.Groups() {
		b.WriteString("## " + group + "\n\n")
		for _, item := range c.Search("", group, nil, 0) {
			b.WriteString(fmt.Sprintf("- `%s` — %s\n", item.ToolName, item.Summary))
			b.WriteString(fmt.Sprintf("  - %s\n", item.Description))
			if item.FreeTier != "" {
				b.WriteString(fmt.Sprintf("  - Free tier note: %s\n", item.FreeTier))
			}
		}
		b.WriteString("\n")
	}
	return b.String()
}

// Groups returns the unique group names used by the catalog.
func (c *Catalog) Groups() []string {
	groups := finnhub.Groups()
	return append([]string(nil), groups...)
}

func newCatalogItem(endpoint finnhub.EndpointSpec) CatalogItem {
	return CatalogItem{
		ToolName:         endpoint.ToolName,
		OperationID:      endpoint.OperationID,
		Title:            endpoint.Title,
		Summary:          endpoint.Summary,
		Description:      endpoint.Description,
		Group:            endpoint.Group,
		FreeTier:         endpoint.FreeTier,
		InputSchema:      endpoint.InputSchema(),
		ExampleArguments: endpoint.ExampleArguments(),
		PromptHint:       buildPromptHint(endpoint),
		EndpointPath:     endpoint.Path,
		Method:           endpoint.Method,
	}
}

func buildPromptHint(endpoint finnhub.EndpointSpec) string {
	hint := fmt.Sprintf("Use %s when you need %s.", endpoint.ToolName, strings.ToLower(endpoint.Description))
	if endpoint.FreeTier != "" {
		hint += " Free-tier note: " + endpoint.FreeTier + "."
	}
	return hint
}

func rankCatalogItem(item CatalogItem, tokens []string) int {
	if len(tokens) == 0 {
		return 1
	}

	haystack := strings.ToLower(strings.Join([]string{
		item.ToolName,
		item.OperationID,
		item.Title,
		item.Summary,
		item.Description,
		item.Group,
	}, " "))

	score := 0
	for _, token := range tokens {
		switch {
		case strings.Contains(strings.ToLower(item.ToolName), token):
			score += 6
		case strings.Contains(strings.ToLower(item.Title), token):
			score += 5
		case strings.Contains(strings.ToLower(item.Summary), token):
			score += 4
		case strings.Contains(haystack, token):
			score += 2
		}
	}
	return score
}

func tokenize(value string) []string {
	value = strings.ToLower(strings.TrimSpace(value))
	if value == "" {
		return nil
	}
	fields := strings.FieldsFunc(value, func(r rune) bool {
		switch {
		case r >= 'a' && r <= 'z':
			return false
		case r >= '0' && r <= '9':
			return false
		default:
			return true
		}
	})
	return fields
}
