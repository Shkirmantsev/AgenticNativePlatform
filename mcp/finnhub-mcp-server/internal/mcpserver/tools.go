package mcpserver

import (
	"context"
	"encoding/json"
	"fmt"
	"sort"
	"strings"
	"time"

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

	message := fmt.Sprintf("Provide the missing inputs for %s.", endpoint.ToolName)

	if supportsFormElicitation(request) {
		elicitResult, err := request.Session.Elicit(ctx, &mcp.ElicitParams{
			Mode:    "form",
			Message: message,
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

	if supportsURLElicitation(request) {
		elicitResult, err := request.Session.Elicit(ctx, &mcp.ElicitParams{
			Mode:          "url",
			Message:       message,
			URL:           a.buildElicitationURL(endpoint, arguments, missingProperties, message),
			ElicitationID: fmt.Sprintf("%s-%d", endpoint.ToolName, time.Now().UnixNano()),
		})
		if err != nil {
			return nil, fmt.Errorf("url elicitation failed for %s: %w", endpoint.ToolName, err)
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
		Description: "List generated Finnhub tools that match a natural-language request, domain, or explicit tool-name shortlist. Use this when you need to browse available capabilities before choosing a concrete endpoint tool.",
		InputSchema: map[string]any{
			"type":                 "object",
			"additionalProperties": false,
			"properties": map[string]any{
				"query": map[string]any{"type": "string", "description": "Free-text search query. This can be a user request such as 'latest quote for Apple' or 'find upcoming earnings'."},
				"group": map[string]any{"type": "string", "description": "Optional domain filter such as Market, Company, Calendar, Forex, Crypto, Alternative Data, General, or Economic."},
				"limit": map[string]any{"type": "integer", "description": "Maximum number of tools to return. Use a smaller value when you want a short shortlist for planning.", "default": 25},
				"names": map[string]any{
					"type":        "array",
					"description": "Optional explicit tool names to include. Useful when you already have a shortlist and want richer metadata back.",
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
		Description: "Return one Finnhub tool with detailed metadata for natural-language use: schema, required and optional arguments, usage guidance, example prompts, and example arguments.",
		InputSchema: map[string]any{
			"type":                 "object",
			"additionalProperties": false,
			"required":             []string{"toolName"},
			"properties": map[string]any{
				"toolName": map[string]any{"type": "string", "description": "Exact tool name from the Finnhub catalog, for example finnhub_quote."},
			},
		},
		Annotations: &mcp.ToolAnnotations{Title: "Get Tool Details", ReadOnlyHint: true, IdempotentHint: true, OpenWorldHint: boolPtr(false), DestructiveHint: boolPtr(false)},
	}
}

func catalogMatchToolsTool() *mcp.Tool {
	return &mcp.Tool{
		Name:        "catalog_match_tools",
		Title:       "Match Tools To Goal",
		Description: "Turn an ambiguous natural-language finance question into a concrete Finnhub plan: recommended tools, likely call order, clarification questions, and candidate parameters. When the client supports sampling, the response can include a model-written clarification plan.",
		InputSchema: map[string]any{
			"type":                 "object",
			"additionalProperties": false,
			"required":             []string{"goal"},
			"properties": map[string]any{
				"goal":           map[string]any{"type": "string", "description": "The user goal or question in natural language. Example: 'Compare Nvidia earnings and recent company news'."},
				"context":        map[string]any{"type": "string", "description": "Optional extra context, ambiguity, or instructions. Example: 'User said Apple but did not provide a ticker'."},
				"knownInputs":    map[string]any{"type": "object", "description": "Optional known user inputs or constraints that can be reused in candidate tool arguments, such as symbol, exchange, from, to, category, or region.", "additionalProperties": true},
				"limit":          map[string]any{"type": "integer", "description": "Maximum number of matching tools to include in the plan.", "default": 5},
				"preferSampling": map[string]any{"type": "boolean", "description": "When true, attempt MCP sampling if the client supports it. Disable this if you want purely deterministic planning output.", "default": true},
				"group":          map[string]any{"type": "string", "description": "Optional domain filter when the request is already scoped, for example Company, Market, Forex, or Crypto."},
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
	contextText := strings.TrimSpace(toString(arguments["context"]))
	knownInputs := objectArg(arguments["knownInputs"])
	limit := intArg(arguments["limit"], 5)
	group := toString(arguments["group"])
	preferSampling := boolArg(arguments["preferSampling"], true)

	items := a.catalog.Search(goal, group, nil, limit)
	clarificationPlan := buildClarificationPlan(goal, contextText, knownInputs, items)
	advisorText := deterministicCatalogAdvice(goal, contextText, clarificationPlan)
	usedSampling := false
	if preferSampling && supportsSampling(request) && request.Session != nil {
		if sampled, sampleErr := a.sampleCatalogAdvice(ctx, request, goal, contextText, clarificationPlan); sampleErr == nil && strings.TrimSpace(sampled) != "" {
			advisorText = sampled
			usedSampling = true
		}
	}

	structured := map[string]any{
		"goal":              goal,
		"context":           contextText,
		"knownInputs":       knownInputs,
		"usedSampling":      usedSampling,
		"recommendation":    advisorText,
		"clarificationPlan": clarificationPlan,
		"tools":             items,
	}
	return &mcp.CallToolResult{
		Content: []mcp.Content{
			&mcp.TextContent{Text: advisorText + "\n\n" + jsonText(structured)},
		},
		StructuredContent: structured,
	}, nil
}

// sampleCatalogAdvice optionally asks the MCP client to draft a short natural
// language clarification plan over the deterministic tool shortlist.
func (a *Application) sampleCatalogAdvice(ctx context.Context, request *mcp.CallToolRequest, goal, contextText string, plan map[string]any) (string, error) {
	payload := map[string]any{
		"goal":    goal,
		"context": contextText,
		"plan":    plan,
	}
	result, err := request.Session.CreateMessage(ctx, &mcp.CreateMessageParams{
		MaxTokens:    600,
		Temperature:  0.2,
		SystemPrompt: "You are helping clarify how to use Finnhub MCP tools for an ambiguous user request. Explain what should be clarified from the user, which tools should be called in which order, and which candidate parameters should be tried first. Keep it concise and action-oriented.",
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
			return deterministicCatalogAdvice(goal, contextText, plan), nil
		}
		return string(body), nil
	}
}

func deterministicCatalogAdvice(goal, contextText string, plan map[string]any) string {
	tools, _ := plan["tools"].([]CatalogItem)
	if len(tools) == 0 {
		return fmt.Sprintf("No generated Finnhub tools matched the goal %q. Use catalog_list_tools to inspect the full catalog.", goal)
	}

	builder := strings.Builder{}
	builder.WriteString(fmt.Sprintf("Recommended Finnhub workflow for goal %q.", goal))
	if contextText != "" {
		builder.WriteString(" Context: ")
		builder.WriteString(contextText)
		builder.WriteString(".")
	}

	if questions, ok := plan["clarificationQuestions"].([]string); ok && len(questions) > 0 {
		builder.WriteString(" Clarify first: ")
		for index, question := range questions {
			if index > 0 {
				builder.WriteString(" ")
			}
			builder.WriteString(fmt.Sprintf("%d) %s.", index+1, question))
		}
	}

	if steps, ok := plan["sequence"].([]map[string]any); ok && len(steps) > 0 {
		builder.WriteString(" Call sequence: ")
		for index, step := range steps {
			if index > 0 {
				builder.WriteString(" ")
			}
			builder.WriteString(fmt.Sprintf(
				"%d) %s with %s.",
				index+1,
				toString(step["toolName"]),
				jsonText(step["candidateArguments"]),
			))
		}
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

func buildClarificationPlan(goal, contextText string, knownInputs map[string]any, items []CatalogItem) map[string]any {
	questions := make([]string, 0)
	sequence := make([]map[string]any, 0, len(items))

	for _, item := range items {
		candidateArguments := mergeCandidateArguments(item, knownInputs)
		for _, question := range clarificationQuestions(item, knownInputs) {
			if !containsString(questions, question) {
				questions = append(questions, question)
			}
		}
		sequence = append(sequence, map[string]any{
			"toolName":           item.ToolName,
			"title":              item.Title,
			"why":                item.Summary,
			"candidateArguments": candidateArguments,
		})
	}

	return map[string]any{
		"goal":                   goal,
		"context":                contextText,
		"knownInputs":            knownInputs,
		"clarificationQuestions": questions,
		"sequence":               sequence,
		"toolNames":              joinToolNames(items),
		"tools":                  items,
	}
}

func mergeCandidateArguments(item CatalogItem, knownInputs map[string]any) map[string]any {
	candidateArguments := make(map[string]any, len(item.ExampleArguments)+len(knownInputs))
	for key, value := range item.ExampleArguments {
		candidateArguments[key] = value
	}

	properties, _ := item.InputSchema["properties"].(map[string]any)
	for key, value := range knownInputs {
		if len(properties) == 0 {
			candidateArguments[key] = value
			continue
		}
		if _, ok := properties[key]; ok {
			candidateArguments[key] = value
		}
	}

	return candidateArguments
}

func clarificationQuestions(item CatalogItem, knownInputs map[string]any) []string {
	questions := make([]string, 0)
	properties, _ := item.InputSchema["properties"].(map[string]any)

	requiredNames := stringList(item.InputSchema["required"])
	for _, name := range requiredNames {
		if !isMissing(knownInputs[name]) {
			continue
		}
		description := schemaDescription(properties, name)
		if description == "" {
			description = name
		}
		questions = append(questions, fmt.Sprintf("What should %s be for %s?", description, item.ToolName))
	}

	for key := range item.ExampleArguments {
		if !isMissing(knownInputs[key]) {
			continue
		}
		description := schemaDescription(properties, key)
		if description == "" {
			description = key
		}
		questions = append(questions, fmt.Sprintf("Should %s be set explicitly for %s?", description, item.ToolName))
	}

	return questions
}

func stringList(value any) []string {
	switch typed := value.(type) {
	case nil:
		return nil
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

func schemaDescription(properties map[string]any, key string) string {
	property, ok := properties[key].(map[string]any)
	if !ok {
		return ""
	}
	return strings.TrimSpace(toString(property["description"]))
}

func objectArg(value any) map[string]any {
	switch typed := value.(type) {
	case nil:
		return map[string]any{}
	case map[string]any:
		result := make(map[string]any, len(typed))
		for key, value := range typed {
			result[key] = value
		}
		return result
	default:
		return map[string]any{}
	}
}

func containsString(values []string, target string) bool {
	for _, value := range values {
		if value == target {
			return true
		}
	}
	return false
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
