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
	RequiredArgs     []string       `json:"requiredArgs,omitempty"`
	OptionalArgs     []string       `json:"optionalArgs,omitempty"`
	AtLeastOneOf     []string       `json:"atLeastOneOf,omitempty"`
	UsageGuidance    string         `json:"usageGuidance"`
	ExamplePrompts   []string       `json:"examplePrompts,omitempty"`
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
	requiredArgs, optionalArgs := parameterNames(endpoint)
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
		RequiredArgs:     requiredArgs,
		OptionalArgs:     optionalArgs,
		AtLeastOneOf:     append([]string(nil), endpoint.AtLeastOneOf...),
		UsageGuidance:    buildUsageGuidance(endpoint, requiredArgs, optionalArgs),
		ExamplePrompts:   buildExamplePrompts(endpoint),
		PromptHint:       buildPromptHint(endpoint),
		EndpointPath:     endpoint.Path,
		Method:           endpoint.Method,
	}
}

func buildPromptHint(endpoint finnhub.EndpointSpec) string {
	requiredArgs, optionalArgs := parameterNames(endpoint)
	hint := fmt.Sprintf("Use %s when a user asks for %s.", endpoint.ToolName, strings.ToLower(trimSentence(endpoint.Description)))
	if len(requiredArgs) > 0 {
		hint += " Required arguments: " + strings.Join(requiredArgs, ", ") + "."
	}
	if len(endpoint.AtLeastOneOf) > 0 {
		hint += " At least one of " + strings.Join(endpoint.AtLeastOneOf, ", ") + " must be supplied."
	}
	if len(optionalArgs) > 0 {
		hint += " Helpful optional arguments: " + strings.Join(optionalArgs, ", ") + "."
	}
	exampleArgs := compactJSON(endpoint.ExampleArguments())
	if exampleArgs != "" && exampleArgs != "{}" {
		hint += " Example arguments: " + exampleArgs + "."
	}
	if endpoint.FreeTier != "" {
		hint += " Free-tier note: " + endpoint.FreeTier + "."
	}
	return hint
}

func buildUsageGuidance(endpoint finnhub.EndpointSpec, requiredArgs, optionalArgs []string) string {
	parts := []string{
		fmt.Sprintf("Start with %s when the user asks for %s.", endpoint.ToolName, strings.ToLower(trimSentence(endpoint.Description))),
	}
	if len(requiredArgs) > 0 {
		parts = append(parts, "Collect required inputs first: "+strings.Join(requiredArgs, ", ")+".")
	}
	if len(endpoint.AtLeastOneOf) > 0 {
		parts = append(parts, "If the user has not provided an identifier yet, collect at least one of "+strings.Join(endpoint.AtLeastOneOf, ", ")+".")
	}
	if len(optionalArgs) > 0 {
		parts = append(parts, "Use optional arguments when the user asks for narrower scope or filtering: "+strings.Join(optionalArgs, ", ")+".")
	}
	if exampleArgs := compactJSON(endpoint.ExampleArguments()); exampleArgs != "" && exampleArgs != "{}" {
		parts = append(parts, "A safe starter payload is "+exampleArgs+".")
	}
	return strings.Join(parts, " ")
}

func buildExamplePrompts(endpoint finnhub.EndpointSpec) []string {
	exampleArgs := endpoint.ExampleArguments()
	symbol := exampleString(exampleArgs, "symbol")
	query := exampleString(exampleArgs, "q")
	exchange := exampleString(exampleArgs, "exchange")
	from := exampleString(exampleArgs, "from")
	to := exampleString(exampleArgs, "to")

	switch {
	case symbol != "":
		return []string{
			fmt.Sprintf("Get %s for %s.", strings.ToLower(trimSentence(endpoint.Title)), symbol),
			fmt.Sprintf("Use Finnhub to show %s for %s.", strings.ToLower(trimSentence(endpoint.Summary)), symbol),
		}
	case query != "":
		return []string{
			fmt.Sprintf("Find the best matching symbol for %s.", query),
			fmt.Sprintf("Search Finnhub for %s.", query),
		}
	case exchange != "":
		return []string{
			fmt.Sprintf("List %s for exchange %s.", strings.ToLower(trimSentence(endpoint.Title)), exchange),
			fmt.Sprintf("Show the Finnhub %s data for %s.", strings.ToLower(trimSentence(endpoint.Summary)), exchange),
		}
	case from != "" || to != "":
		rangeText := strings.Trim(strings.Join([]string{from, to}, " to "), " to")
		if rangeText == "" {
			rangeText = "the requested date range"
		}
		return []string{
			fmt.Sprintf("Get %s for %s.", strings.ToLower(trimSentence(endpoint.Title)), rangeText),
			fmt.Sprintf("Use Finnhub to inspect %s for %s.", strings.ToLower(trimSentence(endpoint.Summary)), rangeText),
		}
	default:
		return []string{
			fmt.Sprintf("Use Finnhub to get %s.", strings.ToLower(trimSentence(endpoint.Title))),
			fmt.Sprintf("Which Finnhub tool should I use for %s?", strings.ToLower(trimSentence(endpoint.Summary))),
		}
	}
}

func exampleString(arguments map[string]any, key string) string {
	value, ok := arguments[key]
	if !ok || value == nil {
		return ""
	}
	return strings.TrimSpace(fmt.Sprint(value))
}

func parameterNames(endpoint finnhub.EndpointSpec) ([]string, []string) {
	required := make([]string, 0, len(endpoint.Parameters))
	optional := make([]string, 0, len(endpoint.Parameters))
	for _, parameter := range endpoint.Parameters {
		if parameter.Required {
			required = append(required, parameter.Name)
			continue
		}
		optional = append(optional, parameter.Name)
	}
	return required, optional
}

func trimSentence(value string) string {
	return strings.TrimSpace(strings.TrimSuffix(value, "."))
}

func compactJSON(value any) string {
	body, err := json.Marshal(value)
	if err != nil {
		return ""
	}
	return string(body)
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
