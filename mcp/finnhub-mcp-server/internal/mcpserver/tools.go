package mcpserver

import (
	"context"
	"encoding/json"
	"fmt"
	"sort"
	"strings"

	"finnhub-mcp-server/internal/finnhub"

	"github.com/modelcontextprotocol/go-sdk/mcp"
)

// registerEndpointTools converts each swagger-derived free Finnhub endpoint into
// one MCP tool.
func (a *Application) registerEndpointTools(server *mcp.Server) {
	for _, endpoint := range finnhub.FreeEndpointSpecs {
		endpoint := endpoint
		server.AddTool(&mcp.Tool{
			Name:        endpoint.ToolName,
			Title:       endpoint.Title,
			Description: endpoint.Description,
			InputSchema: endpoint.InputSchema(),
			Annotations: &mcp.ToolAnnotations{
				Title:           endpoint.Title,
				ReadOnlyHint:    true,
				IdempotentHint:  true,
				OpenWorldHint:   boolPtr(true),
				DestructiveHint: boolPtr(false),
			},
		}, a.buildEndpointHandler(endpoint))
	}
}

// buildEndpointHandler performs input collection, remote request execution,
// and uniform result shaping for one generated endpoint tool.
func (a *Application) buildEndpointHandler(endpoint finnhub.EndpointSpec) mcp.ToolHandler {
	return func(ctx context.Context, request *mcp.CallToolRequest) (*mcp.CallToolResult, error) {
		arguments, err := parseArguments(request.Params.Arguments)
		if err != nil {
			return toolErrorResult(fmt.Errorf("invalid arguments for %s: %w", endpoint.ToolName, err)), nil
		}

		if arguments, err = a.fillMissingArguments(ctx, request, endpoint, arguments); err != nil {
			return toolErrorResult(err), nil
		}

		query := toStringMap(arguments)
		response, err := a.client.Get(ctx, endpoint.Path, query)
		if err != nil {
			return a.remoteErrorToResult(endpoint, query, err), nil
		}

		structured := map[string]any{
			"tool":        endpoint.ToolName,
			"operationId": endpoint.OperationID,
			"title":       endpoint.Title,
			"group":       endpoint.Group,
			"request": map[string]any{
				"path":   endpoint.Path,
				"method": endpoint.Method,
				"query":  query,
			},
			"response": response.Data,
		}
		if endpoint.FreeTier != "" {
			structured["freeTier"] = endpoint.FreeTier
		}

		return &mcp.CallToolResult{
			Content:           []mcp.Content{&mcp.TextContent{Text: jsonText(structured)}},
			StructuredContent: structured,
		}, nil
	}
}

// remoteErrorToResult keeps remote transport errors visible to the model as
// tool results instead of protocol-level failures.
func (a *Application) remoteErrorToResult(endpoint finnhub.EndpointSpec, query map[string]string, err error) *mcp.CallToolResult {
	structured := map[string]any{
		"tool":        endpoint.ToolName,
		"operationId": endpoint.OperationID,
		"request": map[string]any{
			"path":   endpoint.Path,
			"method": endpoint.Method,
			"query":  query,
		},
		"error": err.Error(),
	}
	if remote, ok := err.(*finnhub.RemoteError); ok {
		structured["statusCode"] = remote.StatusCode
		if remote.RetryAfter != "" {
			structured["retryAfter"] = remote.RetryAfter
		}
	}
	result := &mcp.CallToolResult{StructuredContent: structured}
	result.SetError(err)
	return result
}

// fillMissingArguments asks the client for missing required fields via MCP
// elicitation when available. If the client does not support elicitation, the
// returned error explains which arguments are still missing.
func (a *Application) fillMissingArguments(
	ctx context.Context,
	request *mcp.CallToolRequest,
	endpoint finnhub.EndpointSpec,
	arguments map[string]any,
) (map[string]any, error) {
	missingProperties, missingMessages := missingInputSchema(endpoint, arguments)
	if len(missingProperties) == 0 {
		return arguments, nil
	}

	if supportsElicitation(request) {
		elicitResult, err := request.Session.Elicit(ctx, &mcp.ElicitParams{
			Mode:    "form",
			Message: fmt.Sprintf("Provide the missing inputs for %s.", endpoint.ToolName),
			RequestedSchema: map[string]any{
				"type":                 "object",
				"additionalProperties": false,
				"properties":           missingProperties,
			},
		})
		if err != nil {
			return nil, fmt.Errorf("elicitation failed for %s: %w", endpoint.ToolName, err)
		}
		switch strings.ToLower(elicitResult.Action) {
		case "accept":
			for key, value := range elicitResult.Content {
				arguments[key] = value
			}
			missingProperties, missingMessages = missingInputSchema(endpoint, arguments)
			if len(missingProperties) == 0 {
				return arguments, nil
			}
		case "decline", "cancel":
			return nil, fmt.Errorf("required inputs were not provided for %s", endpoint.ToolName)
		}
	}

	return nil, fmt.Errorf(
		"missing required inputs for %s: %s. Example arguments: %s",
		endpoint.ToolName,
		strings.Join(missingMessages, "; "),
		jsonText(endpoint.ExampleArguments()),
	)
}

// missingInputSchema extracts only the currently missing fields so that the
// elicitation form stays small and focused.
func missingInputSchema(endpoint finnhub.EndpointSpec, arguments map[string]any) (map[string]any, []string) {
	missingProperties := make(map[string]any)
	messages := make([]string, 0)

	for _, parameter := range endpoint.Parameters {
		if parameter.Required && isMissing(arguments[parameter.Name]) {
			missingProperties[parameter.Name] = map[string]any{
				"type":        schemaType(parameter.Type),
				"description": parameter.Description,
			}
			messages = append(messages, parameter.Name+" is required")
		}
	}

	if len(endpoint.AtLeastOneOf) > 0 {
		present := false
		for _, name := range endpoint.AtLeastOneOf {
			if !isMissing(arguments[name]) {
				present = true
				break
			}
		}
		if !present {
			names := append([]string(nil), endpoint.AtLeastOneOf...)
			sort.Strings(names)
			messages = append(messages, "at least one of "+strings.Join(names, ", ")+" is required")
			for _, name := range names {
				parameter := parameterByName(endpoint, name)
				description := "alternative identifier"
				if parameter != nil && parameter.Description != "" {
					description = parameter.Description
				}
				missingProperties[name] = map[string]any{
					"type":        "string",
					"description": description,
				}
			}
		}
	}

	return missingProperties, messages
}

func isMissing(value any) bool {
	if value == nil {
		return true
	}
	switch typed := value.(type) {
	case string:
		return strings.TrimSpace(typed) == ""
	case []any:
		return len(typed) == 0
	default:
		return false
	}
}

func parameterByName(endpoint finnhub.EndpointSpec, name string) *finnhub.ParameterSpec {
	for _, parameter := range endpoint.Parameters {
		if parameter.Name == name {
			copyParameter := parameter
			return &copyParameter
		}
	}
	return nil
}

func schemaType(valueType string) string {
	switch strings.ToLower(valueType) {
	case "boolean", "integer", "number", "string":
		return strings.ToLower(valueType)
	default:
		return "string"
	}
}

func (a *Application) registerCatalogTools(server *mcp.Server) {
	server.AddTool(catalogListTool(), a.handleCatalogListTools)
	server.AddTool(catalogGetToolDetailsTool(), a.handleCatalogGetToolDetails)
	server.AddTool(catalogMatchToolsTool(), a.handleCatalogMatchTools)
}

func catalogListTool() *mcp.Tool {
	return &mcp.Tool{
		Name:        "catalog_list_tools",
		Title:       "List Finnhub Tools",
		Description: "List all available generated Finnhub tools, optionally filtered by query, group, or explicit tool names.",
		InputSchema: map[string]any{
			"type":                 "object",
			"additionalProperties": false,
			"properties": map[string]any{
				"query": map[string]any{"type": "string", "description": "Free-text search query over tool names and descriptions."},
				"group": map[string]any{"type": "string", "description": "Optional group filter such as Market, Company, Calendar, Forex, Crypto, Alternative Data or Metadata."},
				"limit": map[string]any{"type": "integer", "description": "Maximum number of tools to return.", "default": 25},
				"names": map[string]any{
					"type":        "array",
					"description": "Optional explicit tool names to include.",
					"items":       map[string]any{"type": "string"},
				},
			},
		},
		Annotations: &mcp.ToolAnnotations{Title: "List Finnhub Tools", ReadOnlyHint: true, IdempotentHint: true, OpenWorldHint: boolPtr(false), DestructiveHint: boolPtr(false)},
	}
}

func catalogGetToolDetailsTool() *mcp.Tool {
	return &mcp.Tool{
		Name:        "catalog_get_tool_details",
		Title:       "Get Tool Details",
		Description: "Return one generated Finnhub tool with its schema, example arguments, and prompt-oriented usage hint.",
		InputSchema: map[string]any{
			"type":                 "object",
			"additionalProperties": false,
			"required":             []string{"toolName"},
			"properties": map[string]any{
				"toolName": map[string]any{"type": "string", "description": "Exact tool name, for example finnhub_quote."},
			},
		},
		Annotations: &mcp.ToolAnnotations{Title: "Get Tool Details", ReadOnlyHint: true, IdempotentHint: true, OpenWorldHint: boolPtr(false), DestructiveHint: boolPtr(false)},
	}
}

func catalogMatchToolsTool() *mcp.Tool {
	return &mcp.Tool{
		Name:        "catalog_match_tools",
		Title:       "Match Tools To Goal",
		Description: "Recommend the most relevant Finnhub tools for a user goal. When the client supports sampling, the response can include a model-written recommendation.",
		InputSchema: map[string]any{
			"type":                 "object",
			"additionalProperties": false,
			"required":             []string{"goal"},
			"properties": map[string]any{
				"goal":           map[string]any{"type": "string", "description": "What the user wants to achieve with Finnhub data."},
				"limit":          map[string]any{"type": "integer", "description": "Maximum number of matching tools.", "default": 5},
				"preferSampling": map[string]any{"type": "boolean", "description": "When true, attempt MCP sampling if the client supports it.", "default": true},
				"group":          map[string]any{"type": "string", "description": "Optional group filter."},
			},
		},
		Annotations: &mcp.ToolAnnotations{Title: "Match Tools To Goal", ReadOnlyHint: true, IdempotentHint: true, OpenWorldHint: boolPtr(false), DestructiveHint: boolPtr(false)},
	}
}

func (a *Application) handleCatalogListTools(_ context.Context, request *mcp.CallToolRequest) (*mcp.CallToolResult, error) {
	arguments, err := parseArguments(request.Params.Arguments)
	if err != nil {
		return toolErrorResult(fmt.Errorf("invalid catalog_list_tools arguments: %w", err)), nil
	}

	limit := intArg(arguments["limit"], 25)
	group := toString(arguments["group"])
	query := toString(arguments["query"])
	names := stringSliceArg(arguments["names"])
	items := a.catalog.Search(query, group, names, limit)

	structured := map[string]any{
		"count": len(items),
		"tools": items,
	}
	return &mcp.CallToolResult{
		Content:           []mcp.Content{&mcp.TextContent{Text: jsonText(structured)}},
		StructuredContent: structured,
	}, nil
}

func (a *Application) handleCatalogGetToolDetails(_ context.Context, request *mcp.CallToolRequest) (*mcp.CallToolResult, error) {
	arguments, err := parseArguments(request.Params.Arguments)
	if err != nil {
		return toolErrorResult(fmt.Errorf("invalid catalog_get_tool_details arguments: %w", err)), nil
	}
	toolName := strings.TrimSpace(toString(arguments["toolName"]))
	if toolName == "" {
		return toolErrorResult(fmt.Errorf("toolName is required")), nil
	}

	item, found := a.catalog.Find(toolName)
	if !found {
		return toolErrorResult(fmt.Errorf("unknown tool %q", toolName)), nil
	}
	return &mcp.CallToolResult{
		Content:           []mcp.Content{&mcp.TextContent{Text: jsonText(item)}},
		StructuredContent: item,
	}, nil
}

func (a *Application) handleCatalogMatchTools(ctx context.Context, request *mcp.CallToolRequest) (*mcp.CallToolResult, error) {
	arguments, err := parseArguments(request.Params.Arguments)
	if err != nil {
		return toolErrorResult(fmt.Errorf("invalid catalog_match_tools arguments: %w", err)), nil
	}

	goal := strings.TrimSpace(toString(arguments["goal"]))
	if goal == "" {
		return toolErrorResult(fmt.Errorf("goal is required")), nil
	}
	limit := intArg(arguments["limit"], 5)
	group := toString(arguments["group"])
	preferSampling := boolArg(arguments["preferSampling"], true)

	items := a.catalog.Search(goal, group, nil, limit)
	advisorText := deterministicCatalogAdvice(goal, items)
	usedSampling := false
	if preferSampling && supportsSampling(request) && request.Session != nil {
		if sampled, sampleErr := a.sampleCatalogAdvice(ctx, request, goal, items); sampleErr == nil && strings.TrimSpace(sampled) != "" {
			advisorText = sampled
			usedSampling = true
		}
	}

	structured := map[string]any{
		"goal":           goal,
		"usedSampling":   usedSampling,
		"recommendation": advisorText,
		"tools":          items,
	}
	return &mcp.CallToolResult{
		Content: []mcp.Content{
			&mcp.TextContent{Text: advisorText + "\n\n" + jsonText(structured)},
		},
		StructuredContent: structured,
	}, nil
}

// sampleCatalogAdvice optionally asks the MCP client to draft a short natural
// language recommendation over the deterministic tool shortlist.
func (a *Application) sampleCatalogAdvice(ctx context.Context, request *mcp.CallToolRequest, goal string, items []CatalogItem) (string, error) {
	payload := map[string]any{
		"goal":  goal,
		"tools": items,
	}
	result, err := request.Session.CreateMessage(ctx, &mcp.CreateMessageParams{
		MaxTokens:    400,
		Temperature:  0.2,
		SystemPrompt: "You are helping select the best Finnhub MCP tools. Explain which tools should be used first and why. Keep it concise and action-oriented.",
		Messages: []*mcp.SamplingMessage{
			{
				Role:    "user",
				Content: &mcp.TextContent{Text: jsonText(payload)},
			},
		},
	})
	if err != nil {
		return "", err
	}
	switch content := result.Content.(type) {
	case *mcp.TextContent:
		return content.Text, nil
	default:
		body, marshalErr := json.Marshal(content)
		if marshalErr != nil {
			return fmt.Sprintf("Selected tools: %s", joinToolNames(items)), nil
		}
		return string(body), nil
	}
}

func deterministicCatalogAdvice(goal string, items []CatalogItem) string {
	if len(items) == 0 {
		return fmt.Sprintf("No generated Finnhub tools matched the goal %q. Use catalog_list_tools to inspect the full catalog.", goal)
	}
	builder := strings.Builder{}
	builder.WriteString("Recommended tools")
	builder.WriteString(" for goal: ")
	builder.WriteString(goal)
	builder.WriteString(". ")
	for index, item := range items {
		if index > 0 {
			builder.WriteString(" ")
		}
		builder.WriteString(fmt.Sprintf("%d) %s — %s.", index+1, item.ToolName, item.Summary))
	}
	return builder.String()
}

func joinToolNames(items []CatalogItem) string {
	names := make([]string, 0, len(items))
	for _, item := range items {
		names = append(names, item.ToolName)
	}
	return strings.Join(names, ", ")
}

func intArg(value any, fallback int) int {
	switch typed := value.(type) {
	case nil:
		return fallback
	case float64:
		return int(typed)
	case int:
		return typed
	case json.Number:
		parsed, err := typed.Int64()
		if err != nil {
			return fallback
		}
		return int(parsed)
	default:
		return fallback
	}
}

func boolArg(value any, fallback bool) bool {
	switch typed := value.(type) {
	case nil:
		return fallback
	case bool:
		return typed
	case string:
		switch strings.ToLower(strings.TrimSpace(typed)) {
		case "true", "1", "yes", "y", "on":
			return true
		case "false", "0", "no", "n", "off":
			return false
		default:
			return fallback
		}
	default:
		return fallback
	}
}

func stringSliceArg(value any) []string {
	if value == nil {
		return nil
	}
	switch typed := value.(type) {
	case []string:
		return append([]string(nil), typed...)
	case []any:
		result := make([]string, 0, len(typed))
		for _, item := range typed {
			text := strings.TrimSpace(toString(item))
			if text != "" {
				result = append(result, text)
			}
		}
		return result
	default:
		text := strings.TrimSpace(toString(value))
		if text == "" {
			return nil
		}
		return []string{text}
	}
}
