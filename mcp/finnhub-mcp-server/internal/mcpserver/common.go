package mcpserver

import (
	"bytes"
	"encoding/json"
	"fmt"
	"sort"
	"strconv"
	"strings"

	"github.com/modelcontextprotocol/go-sdk/mcp"
)

func boolPtr(value bool) *bool {
	return &value
}

func parseArguments(raw json.RawMessage) (map[string]any, error) {
	if len(bytes.TrimSpace(raw)) == 0 || string(bytes.TrimSpace(raw)) == "null" {
		return map[string]any{}, nil
	}
	arguments := make(map[string]any)
	if err := json.Unmarshal(raw, &arguments); err != nil {
		return nil, err
	}
	return arguments, nil
}

func toStringMap(arguments map[string]any) map[string]string {
	result := make(map[string]string, len(arguments))
	for key, value := range arguments {
		stringValue := toString(value)
		if strings.TrimSpace(stringValue) != "" {
			result[key] = stringValue
		}
	}
	return result
}

func toString(value any) string {
	switch typed := value.(type) {
	case nil:
		return ""
	case string:
		return typed
	case bool:
		return strconv.FormatBool(typed)
	case float64:
		if typed == float64(int64(typed)) {
			return strconv.FormatInt(int64(typed), 10)
		}
		return strconv.FormatFloat(typed, 'f', -1, 64)
	case int:
		return strconv.Itoa(typed)
	case int64:
		return strconv.FormatInt(typed, 10)
	case json.Number:
		return typed.String()
	default:
		return fmt.Sprint(value)
	}
}

func toolErrorResult(err error) *mcp.CallToolResult {
	result := &mcp.CallToolResult{}
	result.SetError(err)
	return result
}

func jsonText(value any) string {
	body, err := json.MarshalIndent(value, "", "  ")
	if err != nil {
		return fmt.Sprintf("%v", value)
	}
	return string(body)
}

func supportsElicitation(request *mcp.CallToolRequest) bool {
	if request == nil || request.Session == nil {
		return false
	}
	params := request.Session.InitializeParams()
	return params != nil && params.Capabilities != nil && params.Capabilities.Elicitation != nil
}

func supportsSampling(request *mcp.CallToolRequest) bool {
	if request == nil || request.Session == nil {
		return false
	}
	params := request.Session.InitializeParams()
	return params != nil && params.Capabilities != nil && params.Capabilities.Sampling != nil
}

func sortedKeys(values map[string]any) []string {
	keys := make([]string, 0, len(values))
	for key := range values {
		keys = append(keys, key)
	}
	sort.Strings(keys)
	return keys
}
