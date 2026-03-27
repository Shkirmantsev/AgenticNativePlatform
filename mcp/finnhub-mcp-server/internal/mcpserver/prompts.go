package mcpserver

import (
	"context"
	"fmt"
	"strings"

	"github.com/modelcontextprotocol/go-sdk/mcp"
)

func (a *Application) registerPrompts(server *mcp.Server) {
	server.AddPrompt(&mcp.Prompt{
		Name:        "discover_finnhub_tools",
		Title:       "Discover Finnhub Tools",
		Description: "Turn a natural-language finance question into a concrete Finnhub tool plan: which tools to call, in what order, and which inputs are still missing.",
		Arguments: []*mcp.PromptArgument{
			{Name: "goal", Description: "User goal or question that needs Finnhub data.", Required: true},
			{Name: "context", Description: "Optional extra context, ambiguity, or known constraints from the user request.", Required: false},
		},
	}, a.handleDiscoverToolsPrompt)

	server.AddPrompt(&mcp.Prompt{
		Name:        "explain_finnhub_tool",
		Title:       "Explain One Finnhub Tool",
		Description: "Explain one Finnhub tool in natural language, including when to use it, what inputs it expects, and example prompts and payloads.",
		Arguments: []*mcp.PromptArgument{
			{Name: "toolName", Description: "Exact MCP tool name such as finnhub_quote.", Required: true},
		},
	}, a.handleExplainToolPrompt)
}

func (a *Application) handleDiscoverToolsPrompt(_ context.Context, request *mcp.GetPromptRequest) (*mcp.GetPromptResult, error) {
	goal := strings.TrimSpace(request.Params.Arguments["goal"])
	contextText := strings.TrimSpace(request.Params.Arguments["context"])
	searchText := strings.TrimSpace(strings.Join([]string{goal, contextText}, " "))
	matches := a.catalog.Search(searchText, "", nil, 8)
	catalogJSON := jsonText(map[string]any{"goal": goal, "context": contextText, "tools": matches})

	text := fmt.Sprintf("The user goal is: %s\nAdditional context: %s\n\nUse the following generated Finnhub tool catalog excerpt to decide which tools to call first, which arguments are still missing, how to clarify ambiguous wording, and what sequence makes sense. Prefer the minimal number of tools, keep the plan explicit, and reuse the example prompts and example arguments when they fit the request.\n\n%s", goal, defaultIfEmpty(contextText, "(none)"), catalogJSON)
	return &mcp.GetPromptResult{
		Description: "Prompt for selecting Finnhub tools and clarifying missing inputs for a user goal.",
		Messages: []*mcp.PromptMessage{
			{Role: "user", Content: &mcp.TextContent{Text: text}},
		},
	}, nil
}

func (a *Application) handleExplainToolPrompt(_ context.Context, request *mcp.GetPromptRequest) (*mcp.GetPromptResult, error) {
	toolName := strings.TrimSpace(request.Params.Arguments["toolName"])
	item, found := a.catalog.Find(toolName)
	if !found {
		return &mcp.GetPromptResult{
			Description: "Requested tool was not found.",
			Messages: []*mcp.PromptMessage{
				{Role: "user", Content: &mcp.TextContent{Text: fmt.Sprintf("Tool %q does not exist in this Finnhub MCP server. Use catalog_list_tools first.", toolName)}},
			},
		}, nil
	}

	text := fmt.Sprintf("Explain this tool in a concise operator-friendly way. Describe when to use it, which user phrases should map to it, which arguments are required, which are optional, how to clarify missing inputs, and show the example prompts and example payload.\n\n%s", jsonText(item))
	return &mcp.GetPromptResult{
		Description: "Prompt for explaining one Finnhub tool and how to call it from natural-language requests.",
		Messages: []*mcp.PromptMessage{
			{Role: "user", Content: &mcp.TextContent{Text: text}},
		},
	}, nil
}

func defaultIfEmpty(value, fallback string) string {
	if strings.TrimSpace(value) == "" {
		return fallback
	}
	return value
}
