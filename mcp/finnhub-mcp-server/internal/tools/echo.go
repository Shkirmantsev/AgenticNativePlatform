package tools

import (
	"context"

	"github.com/modelcontextprotocol/go-sdk/mcp"
)

func init() {
	registerTool(Echo())
}

type EchoParams struct {
	Message string `json:"message" description:"The message to echo."`
}

type EchoResult struct {
	Echo string `json:"echo" description:"The echoed message."`
}

func Echo() MCPTool[EchoParams, EchoResult] {
	return MCPTool[EchoParams, EchoResult]{
		Name:        "echo",
		Description: "Echoes a message back to the user.",
		Handler: func(ctx context.Context, req *mcp.CallToolRequest, params EchoParams) (*mcp.CallToolResult, EchoResult, error) {
			_ = ctx
			_ = req

			return nil, EchoResult{
				Echo: "Echo: " + params.Message,
			}, nil
		},
	}
}
