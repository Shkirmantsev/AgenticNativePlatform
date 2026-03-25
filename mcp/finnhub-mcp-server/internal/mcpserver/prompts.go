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
		Description: "Explain which generated Finnhub tools should be used for a goal and how to call them.",
		Arguments: []*mcp.PromptArgument{
			{Name: "goal", Description: "User goal or question that needs Finnhub data.", Required: true},
		},
	}, a.handleDiscoverToolsPrompt)

	server.AddPrompt(&mcp.Prompt{
		Name:        "explain_finnhub_tool",
		Title:       "Explain One Finnhub Tool",
		Description: "Return an operator-friendly explanation for one tool, including schema and example arguments.",
		Arguments: []*mcp.PromptArgument{
			{Name: "toolName", Description: "Exact MCP tool name such as finnhub_quote.", Required: true},
		},
	}, a.handleExplainToolPrompt)
}

func (a *Application) handleDiscoverToolsPrompt(_ context.Context, request *mcp.GetPromptRequest) (*mcp.GetPromptResult, error) {
	goal := strings.TrimSpace(request.Params.Arguments["goal"])
	matches := a.catalog.Search(goal, "", nil, 8)
	catalogJSON := jsonText(map[string]any{"goal": goal, "tools": matches})

	text := fmt.Sprintf("The user goal is: %s\n\nUse the following generated Finnhub tool catalog excerpt to decide which tools to call first, which arguments are still missing, and what order makes sense. Prefer the minimal number of tools.\n\n%s", goal, catalogJSON)
	return &mcp.GetPromptResult{
		Description: "Prompt for selecting Finnhub tools for a goal.",
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

	text := fmt.Sprintf("Explain this tool in a concise operator-friendly way. Describe when to use it, which arguments are required, which arguments are optional, and show the example payload.\n\n%s", jsonText(item))
	return &mcp.GetPromptResult{
		Description: "Prompt for explaining one Finnhub tool.",
		Messages: []*mcp.PromptMessage{
			{Role: "user", Content: &mcp.TextContent{Text: text}},
		},
	}, nil
}
