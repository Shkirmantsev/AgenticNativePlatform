package finnhub

import (
	"context"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"net/url"
	"strings"
	"time"
)

// Client is a thin production-friendly HTTP adapter over the Finnhub REST API.
//
// The implementation stays intentionally small and explicit because the MCP
// server only needs stable GET access for the free endpoints declared in the
// provided swagger schema.
type Client struct {
	baseURL    string
	apiKey     string
	userAgent  string
	httpClient *http.Client
}

// Response bundles both parsed JSON and transport metadata so that tools can
// return structured output without losing HTTP-level context.
type Response struct {
	StatusCode int
	Headers    http.Header
	Data       any
}

// NewClient creates a new Finnhub API client.
func NewClient(baseURL, apiKey, userAgent string, timeout time.Duration) *Client {
	return &Client{
		baseURL:   strings.TrimRight(baseURL, "/"),
		apiKey:    apiKey,
		userAgent: userAgent,
		httpClient: &http.Client{
			Timeout: timeout,
		},
	}
}

// Get executes one GET request against the remote Finnhub endpoint.
func (c *Client) Get(ctx context.Context, endpointPath string, query map[string]string) (*Response, error) {
	requestURL, err := url.Parse(c.baseURL + endpointPath)
	if err != nil {
		return nil, fmt.Errorf("build request url: %w", err)
	}

	values := requestURL.Query()
	for key, value := range query {
		if strings.TrimSpace(value) == "" {
			continue
		}
		values.Set(key, value)
	}
	requestURL.RawQuery = values.Encode()

	req, err := http.NewRequestWithContext(ctx, http.MethodGet, requestURL.String(), nil)
	if err != nil {
		return nil, fmt.Errorf("create request: %w", err)
	}
	req.Header.Set("Accept", "application/json")
	req.Header.Set("X-Finnhub-Token", c.apiKey)
	if strings.TrimSpace(c.userAgent) != "" {
		req.Header.Set("User-Agent", c.userAgent)
	}

	resp, err := c.httpClient.Do(req)
	if err != nil {
		return nil, fmt.Errorf("call finnhub: %w", err)
	}
	defer resp.Body.Close()

	body, err := io.ReadAll(io.LimitReader(resp.Body, 4<<20))
	if err != nil {
		return nil, fmt.Errorf("read finnhub response: %w", err)
	}

	if resp.StatusCode < 200 || resp.StatusCode >= 300 {
		return nil, newRemoteError(resp.StatusCode, body, resp.Header)
	}

	parsed, err := decodeBody(body)
	if err != nil {
		return nil, fmt.Errorf("decode finnhub response: %w", err)
	}

	return &Response{
		StatusCode: resp.StatusCode,
		Headers:    resp.Header.Clone(),
		Data:       parsed,
	}, nil
}

func decodeBody(body []byte) (any, error) {
	trimmed := strings.TrimSpace(string(body))
	if trimmed == "" {
		return map[string]any{}, nil
	}

	var parsed any
	if err := json.Unmarshal(body, &parsed); err != nil {
		return nil, err
	}
	return parsed, nil
}

// RemoteError is a domain-level error that keeps enough context to explain
// remote API failures back to the LLM and to operators.
type RemoteError struct {
	StatusCode  int
	BodyPreview string
	RetryAfter  string
}

func (e *RemoteError) Error() string {
	if e == nil {
		return ""
	}
	message := fmt.Sprintf("finnhub returned HTTP %d", e.StatusCode)
	if e.RetryAfter != "" {
		message += fmt.Sprintf(" (retry-after: %s)", e.RetryAfter)
	}
	if e.BodyPreview != "" {
		message += ": " + e.BodyPreview
	}
	return message
}

func newRemoteError(statusCode int, body []byte, headers http.Header) error {
	preview := strings.TrimSpace(string(body))
	preview = strings.ReplaceAll(preview, "\n", " ")
	preview = strings.Join(strings.Fields(preview), " ")
	if len(preview) > 350 {
		preview = preview[:347] + "..."
	}
	return &RemoteError{
		StatusCode:  statusCode,
		BodyPreview: preview,
		RetryAfter:  headers.Get("Retry-After"),
	}
}
