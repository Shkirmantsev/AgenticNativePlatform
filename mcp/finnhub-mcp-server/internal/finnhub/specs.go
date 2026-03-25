package finnhub

import (
	"sort"
	"strings"
)

// ParameterSpec describes one tool input argument derived from the Finnhub API schema.
type ParameterSpec struct {
	Name        string
	Location    string
	Type        string
	Description string
	Required    bool
	Enum        []string
	Default     any
	Example     any
}

// EndpointSpec describes one Finnhub REST endpoint that is exposed as an MCP tool.
type EndpointSpec struct {
	ToolName     string
	OperationID  string
	Title        string
	Summary      string
	Description  string
	Path         string
	Method       string
	Group        string
	FreeTier     string
	Parameters   []ParameterSpec
	AtLeastOneOf []string
}

// InputSchema converts the endpoint definition into an MCP-compatible JSON schema.
func (e EndpointSpec) InputSchema() map[string]any {
	properties := make(map[string]any, len(e.Parameters))
	required := make([]string, 0, len(e.Parameters))

	for _, parameter := range e.Parameters {
		property := map[string]any{
			"type":        jsonSchemaType(parameter.Type),
			"description": parameter.Description,
		}
		if len(parameter.Enum) > 0 {
			property["enum"] = parameter.Enum
		}
		if parameter.Default != nil {
			property["default"] = parameter.Default
		}
		if parameter.Example != nil {
			property["examples"] = []any{parameter.Example}
		}
		properties[parameter.Name] = property
		if parameter.Required {
			required = append(required, parameter.Name)
		}
	}

	schema := map[string]any{
		"type":                 "object",
		"additionalProperties": false,
		"properties":           properties,
	}
	if len(required) > 0 {
		schema["required"] = required
	}
	if len(e.AtLeastOneOf) > 0 {
		anyOf := make([]any, 0, len(e.AtLeastOneOf))
		for _, name := range e.AtLeastOneOf {
			anyOf = append(anyOf, map[string]any{"required": []string{name}})
		}
		schema["anyOf"] = anyOf
	}
	return schema
}

// ExampleArguments returns a stable example payload for the endpoint.
func (e EndpointSpec) ExampleArguments() map[string]any {
	example := make(map[string]any, len(e.Parameters))
	for _, parameter := range e.Parameters {
		if parameter.Example != nil {
			example[parameter.Name] = parameter.Example
			continue
		}
		if parameter.Default != nil {
			example[parameter.Name] = parameter.Default
		}
	}
	return example
}

// RequiredParameterNames returns all directly required parameters.
func (e EndpointSpec) RequiredParameterNames() []string {
	result := make([]string, 0, len(e.Parameters))
	for _, parameter := range e.Parameters {
		if parameter.Required {
			result = append(result, parameter.Name)
		}
	}
	return result
}

// FindEndpointByToolName returns the matching endpoint and true when found.
func FindEndpointByToolName(name string) (EndpointSpec, bool) {
	for _, spec := range FreeEndpointSpecs {
		if spec.ToolName == name {
			return spec, true
		}
	}
	return EndpointSpec{}, false
}

// ToolNames returns the list of all generated tool names in sorted order.
func ToolNames() []string {
	names := make([]string, 0, len(FreeEndpointSpecs))
	for _, spec := range FreeEndpointSpecs {
		names = append(names, spec.ToolName)
	}
	sort.Strings(names)
	return names
}

// Groups returns the sorted unique group names used by the endpoint catalog.
func Groups() []string {
	set := make(map[string]struct{})
	for _, spec := range FreeEndpointSpecs {
		set[spec.Group] = struct{}{}
	}
	groups := make([]string, 0, len(set))
	for group := range set {
		groups = append(groups, group)
	}
	sort.Strings(groups)
	return groups
}

func jsonSchemaType(valueType string) string {
	switch strings.ToLower(valueType) {
	case "integer", "number", "boolean", "string":
		return strings.ToLower(valueType)
	default:
		return "string"
	}
}

// FreeEndpointSpecs contains all REST operations from the provided Finnhub swagger
// that do not declare premium access in the upstream schema.
var FreeEndpointSpecs = []EndpointSpec{
	{
		ToolName:     "finnhub_symbol_search",
		OperationID:  "symbol-search",
		Title:        "Global Stocks Search",
		Summary:      "Symbol Lookup",
		Description:  "Search for best-matching symbols based on your query. You can input anything from symbol, security's name to ISIN and Cusip.",
		Path:         "/search",
		Method:       "GET",
		Group:        "Market",
		FreeTier:     "",
		AtLeastOneOf: nil,
		Parameters: []ParameterSpec{
			{
				Name:        "q",
				Location:    "query",
				Type:        "string",
				Description: "Query text can be symbol, name, isin, or cusip.",
				Required:    true,
				Enum:        nil,
				Default:     nil,
				Example:     "AAPL",
			},
			{
				Name:        "exchange",
				Location:    "query",
				Type:        "string",
				Description: "Exchange limit.",
				Required:    false,
				Enum:        nil,
				Default:     nil,
				Example:     "US",
			},
		},
	},
	{
		ToolName:     "finnhub_stock_symbols",
		OperationID:  "stock-symbols",
		Title:        "Stock Symbols By Exchange",
		Summary:      "Stock Symbol",
		Description:  "List supported stocks. We use the following symbology to identify stocks on Finnhub Exchange_Ticker.Exchange_Code. A list of supported exchange codes can be found here.",
		Path:         "/stock/symbol",
		Method:       "GET",
		Group:        "General",
		FreeTier:     "",
		AtLeastOneOf: nil,
		Parameters: []ParameterSpec{
			{
				Name:        "exchange",
				Location:    "query",
				Type:        "string",
				Description: "Exchange you want to get the list of symbols from. List of exchange codes can be found here.",
				Required:    true,
				Enum:        nil,
				Default:     nil,
				Example:     "US",
			},
			{
				Name:        "mic",
				Location:    "query",
				Type:        "string",
				Description: "Filter by MIC code.",
				Required:    false,
				Enum:        nil,
				Default:     nil,
				Example:     "XNAS",
			},
			{
				Name:        "securityType",
				Location:    "query",
				Type:        "string",
				Description: "Filter by security type used by OpenFigi standard.",
				Required:    false,
				Enum:        nil,
				Default:     nil,
				Example:     "Common Stock",
			},
			{
				Name:        "currency",
				Location:    "query",
				Type:        "string",
				Description: "Filter by currency.",
				Required:    false,
				Enum:        nil,
				Default:     nil,
				Example:     "USD",
			},
		},
	},
	{
		ToolName:     "finnhub_market_status",
		OperationID:  "market-status",
		Title:        "Global Market Status API",
		Summary:      "Market Status",
		Description:  "Get current market status for global exchanges (whether exchanges are open or close).",
		Path:         "/stock/market-status",
		Method:       "GET",
		Group:        "Market",
		FreeTier:     "",
		AtLeastOneOf: nil,
		Parameters: []ParameterSpec{
			{
				Name:        "exchange",
				Location:    "query",
				Type:        "string",
				Description: "Exchange code.",
				Required:    true,
				Enum:        nil,
				Default:     nil,
				Example:     "US",
			},
		},
	},
	{
		ToolName:     "finnhub_market_holiday",
		OperationID:  "market-holiday",
		Title:        "Global Stock Market Holiday API",
		Summary:      "Market Holiday",
		Description:  "Get a list of holidays for global exchanges.",
		Path:         "/stock/market-holiday",
		Method:       "GET",
		Group:        "Market",
		FreeTier:     "",
		AtLeastOneOf: nil,
		Parameters: []ParameterSpec{
			{
				Name:        "exchange",
				Location:    "query",
				Type:        "string",
				Description: "Exchange code.",
				Required:    true,
				Enum:        nil,
				Default:     nil,
				Example:     "US",
			},
		},
	},
	{
		ToolName:     "finnhub_company_profile2",
		OperationID:  "company-profile2",
		Title:        "Global Company Profile 2",
		Summary:      "Company Profile 2",
		Description:  "Get general information of a company. You can query by symbol, ISIN or CUSIP. This is the free version of Company Profile.",
		Path:         "/stock/profile2",
		Method:       "GET",
		Group:        "Company",
		FreeTier:     "",
		AtLeastOneOf: []string{"symbol", "isin", "cusip"},
		Parameters: []ParameterSpec{
			{
				Name:        "symbol",
				Location:    "query",
				Type:        "string",
				Description: "Symbol of the company: AAPL e.g.",
				Required:    false,
				Enum:        nil,
				Default:     nil,
				Example:     "AAPL",
			},
			{
				Name:        "isin",
				Location:    "query",
				Type:        "string",
				Description: "ISIN",
				Required:    false,
				Enum:        nil,
				Default:     nil,
				Example:     "US0378331005",
			},
			{
				Name:        "cusip",
				Location:    "query",
				Type:        "string",
				Description: "CUSIP",
				Required:    false,
				Enum:        nil,
				Default:     nil,
				Example:     "037833100",
			},
		},
	},
	{
		ToolName:     "finnhub_market_news",
		OperationID:  "market-news",
		Title:        "Real-time Market News API",
		Summary:      "Market News",
		Description:  "Get latest market news.",
		Path:         "/news",
		Method:       "GET",
		Group:        "Market",
		FreeTier:     "",
		AtLeastOneOf: nil,
		Parameters: []ParameterSpec{
			{
				Name:        "category",
				Location:    "query",
				Type:        "string",
				Description: "This parameter can be 1 of the following values general, forex, crypto, merger.",
				Required:    true,
				Enum:        []string{"general", "forex", "crypto", "merger"},
				Default:     nil,
				Example:     "general",
			},
			{
				Name:        "minId",
				Location:    "query",
				Type:        "integer",
				Description: "Use this field to get only news after this ID. Default to 0",
				Required:    false,
				Enum:        nil,
				Default:     nil,
				Example:     0,
			},
		},
	},
	{
		ToolName:     "finnhub_company_news",
		OperationID:  "company-news",
		Title:        "Real-time Global Company News API",
		Summary:      "Company News",
		Description:  "List latest company news by symbol. This endpoint is only available for North American companies.",
		Path:         "/company-news",
		Method:       "GET",
		Group:        "Company",
		FreeTier:     "1 year of historical news and new updates",
		AtLeastOneOf: nil,
		Parameters: []ParameterSpec{
			{
				Name:        "symbol",
				Location:    "query",
				Type:        "string",
				Description: "Company symbol.",
				Required:    true,
				Enum:        nil,
				Default:     nil,
				Example:     "AAPL",
			},
			{
				Name:        "from",
				Location:    "query",
				Type:        "string",
				Description: "From date YYYY-MM-DD.",
				Required:    true,
				Enum:        nil,
				Default:     nil,
				Example:     "2025-01-01",
			},
			{
				Name:        "to",
				Location:    "query",
				Type:        "string",
				Description: "To date YYYY-MM-DD.",
				Required:    true,
				Enum:        nil,
				Default:     nil,
				Example:     "2025-01-31",
			},
		},
	},
	{
		ToolName:     "finnhub_company_peers",
		OperationID:  "company-peers",
		Title:        "Company Peers",
		Summary:      "Peers",
		Description:  "Get company peers. Return a list of peers operating in the same country and sector/industry.",
		Path:         "/stock/peers",
		Method:       "GET",
		Group:        "Company",
		FreeTier:     "",
		AtLeastOneOf: nil,
		Parameters: []ParameterSpec{
			{
				Name:        "symbol",
				Location:    "query",
				Type:        "string",
				Description: "Symbol of the company: AAPL.",
				Required:    true,
				Enum:        nil,
				Default:     nil,
				Example:     "AAPL",
			},
			{
				Name:        "grouping",
				Location:    "query",
				Type:        "string",
				Description: "Specify the grouping criteria for choosing peers.Supporter values: sector, industry, subIndustry. Default to subIndustry.",
				Required:    false,
				Enum:        []string{"sector", "industry", "subIndustry"},
				Default:     nil,
				Example:     "subIndustry",
			},
		},
	},
	{
		ToolName:     "finnhub_company_basic_financials",
		OperationID:  "company-basic-financials",
		Title:        "Global Company Basic Financials | P/E, EPS, Market cap, Shares Outstanding",
		Summary:      "Basic Financials",
		Description:  "Get company basic financials such as margin, P/E ratio, 52-week high/low etc.",
		Path:         "/stock/metric",
		Method:       "GET",
		Group:        "Company",
		FreeTier:     "",
		AtLeastOneOf: nil,
		Parameters: []ParameterSpec{
			{
				Name:        "symbol",
				Location:    "query",
				Type:        "string",
				Description: "Symbol of the company: AAPL.",
				Required:    true,
				Enum:        nil,
				Default:     nil,
				Example:     "MSFT",
			},
			{
				Name:        "metric",
				Location:    "query",
				Type:        "string",
				Description: "Metric type. Can be 1 of the following values all",
				Required:    true,
				Enum:        []string{"all"},
				Default:     "all",
				Example:     "all",
			},
		},
	},
	{
		ToolName:     "finnhub_insider_transactions",
		OperationID:  "insider-transactions",
		Title:        "Insider Transactions",
		Summary:      "Insider Transactions",
		Description:  "Company insider transactions data sourced from Form 3,4,5, SEDI and relevant companies' filings. This endpoint covers US, UK, Canada, Australia, India, and all major EU markets. Limit to 100 transactions per API call.",
		Path:         "/stock/insider-transactions",
		Method:       "GET",
		Group:        "Company",
		FreeTier:     "",
		AtLeastOneOf: nil,
		Parameters: []ParameterSpec{
			{
				Name:        "symbol",
				Location:    "query",
				Type:        "string",
				Description: "Symbol of the company: AAPL. Leave this param blank to get the latest transactions.",
				Required:    true,
				Enum:        nil,
				Default:     nil,
				Example:     "AAPL",
			},
			{
				Name:        "from",
				Location:    "query",
				Type:        "string",
				Description: "From date: 2020-03-15.",
				Required:    false,
				Enum:        nil,
				Default:     nil,
				Example:     "2025-01-01",
			},
			{
				Name:        "to",
				Location:    "query",
				Type:        "string",
				Description: "To date: 2020-03-16.",
				Required:    false,
				Enum:        nil,
				Default:     nil,
				Example:     "2025-01-31",
			},
		},
	},
	{
		ToolName:     "finnhub_insider_sentiment",
		OperationID:  "insider-sentiment",
		Title:        "Insider Sentiment API",
		Summary:      "Insider Sentiment",
		Description:  "Get insider sentiment data for US companies calculated using method discussed here. The MSPR ranges from -100 for the most negative to 100 for the most positive which can signal price changes in the coming 30-90 days.",
		Path:         "/stock/insider-sentiment",
		Method:       "GET",
		Group:        "Company",
		FreeTier:     "",
		AtLeastOneOf: nil,
		Parameters: []ParameterSpec{
			{
				Name:        "symbol",
				Location:    "query",
				Type:        "string",
				Description: "Symbol of the company: AAPL.",
				Required:    true,
				Enum:        nil,
				Default:     nil,
				Example:     "AAPL",
			},
			{
				Name:        "from",
				Location:    "query",
				Type:        "string",
				Description: "From date: 2020-03-15.",
				Required:    true,
				Enum:        nil,
				Default:     nil,
				Example:     "2025-01-01",
			},
			{
				Name:        "to",
				Location:    "query",
				Type:        "string",
				Description: "To date: 2020-03-16.",
				Required:    true,
				Enum:        nil,
				Default:     nil,
				Example:     "2025-01-31",
			},
		},
	},
	{
		ToolName:     "finnhub_financials_reported",
		OperationID:  "financials-reported",
		Title:        "Financials As Reported | Stock API",
		Summary:      "Financials As Reported",
		Description:  "Get financials as reported. This data is available for bulk download on Kaggle SEC Financials database.",
		Path:         "/stock/financials-reported",
		Method:       "GET",
		Group:        "Company",
		FreeTier:     "",
		AtLeastOneOf: nil,
		Parameters: []ParameterSpec{
			{
				Name:        "symbol",
				Location:    "query",
				Type:        "string",
				Description: "Symbol.",
				Required:    false,
				Enum:        nil,
				Default:     nil,
				Example:     "AAPL",
			},
			{
				Name:        "cik",
				Location:    "query",
				Type:        "string",
				Description: "CIK.",
				Required:    false,
				Enum:        nil,
				Default:     nil,
				Example:     "0000320193",
			},
			{
				Name:        "accessNumber",
				Location:    "query",
				Type:        "string",
				Description: "Access number of a specific report you want to retrieve financials from.",
				Required:    false,
				Enum:        nil,
				Default:     nil,
				Example:     "0000320193-24-000123",
			},
			{
				Name:        "freq",
				Location:    "query",
				Type:        "string",
				Description: "Frequency. Can be either annual or quarterly. Default to annual.",
				Required:    false,
				Enum:        []string{"annual", "quarterly"},
				Default:     "annual",
				Example:     "annual",
			},
			{
				Name:        "from",
				Location:    "query",
				Type:        "string",
				Description: "From date YYYY-MM-DD. Filter for endDate.",
				Required:    false,
				Enum:        nil,
				Default:     nil,
				Example:     "2025-01-01",
			},
			{
				Name:        "to",
				Location:    "query",
				Type:        "string",
				Description: "To date YYYY-MM-DD. Filter for endDate.",
				Required:    false,
				Enum:        nil,
				Default:     nil,
				Example:     "2025-01-31",
			},
		},
	},
	{
		ToolName:     "finnhub_filings",
		OperationID:  "filings",
		Title:        "Real-time SEC Filings API",
		Summary:      "SEC Filings",
		Description:  "List company's filing. Limit to 250 documents at a time. This data is available for bulk download on Kaggle SEC Filings database.",
		Path:         "/stock/filings",
		Method:       "GET",
		Group:        "Company",
		FreeTier:     "",
		AtLeastOneOf: nil,
		Parameters: []ParameterSpec{
			{
				Name:        "symbol",
				Location:    "query",
				Type:        "string",
				Description: "Symbol. Leave symbol,cik and accessNumber empty to list latest filings.",
				Required:    false,
				Enum:        nil,
				Default:     nil,
				Example:     "AAPL",
			},
			{
				Name:        "cik",
				Location:    "query",
				Type:        "string",
				Description: "CIK.",
				Required:    false,
				Enum:        nil,
				Default:     nil,
				Example:     "0000320193",
			},
			{
				Name:        "accessNumber",
				Location:    "query",
				Type:        "string",
				Description: "Access number of a specific report you want to retrieve data from.",
				Required:    false,
				Enum:        nil,
				Default:     nil,
				Example:     "0000320193-24-000123",
			},
			{
				Name:        "form",
				Location:    "query",
				Type:        "string",
				Description: "Filter by form. You can use this value NT 10-K to find non-timely filings for a company.",
				Required:    false,
				Enum:        nil,
				Default:     nil,
				Example:     "10-K",
			},
			{
				Name:        "from",
				Location:    "query",
				Type:        "string",
				Description: "From date: 2023-03-15.",
				Required:    false,
				Enum:        nil,
				Default:     nil,
				Example:     "2025-01-01",
			},
			{
				Name:        "to",
				Location:    "query",
				Type:        "string",
				Description: "To date: 2023-03-16.",
				Required:    false,
				Enum:        nil,
				Default:     nil,
				Example:     "2025-01-31",
			},
		},
	},
	{
		ToolName:     "finnhub_ipo_calendar",
		OperationID:  "ipo-calendar",
		Title:        "IPO Calendar API",
		Summary:      "IPO Calendar",
		Description:  "Get recent and upcoming IPO.",
		Path:         "/calendar/ipo",
		Method:       "GET",
		Group:        "Calendar",
		FreeTier:     "",
		AtLeastOneOf: nil,
		Parameters: []ParameterSpec{
			{
				Name:        "from",
				Location:    "query",
				Type:        "string",
				Description: "From date: 2020-03-15.",
				Required:    true,
				Enum:        nil,
				Default:     nil,
				Example:     "2025-01-01",
			},
			{
				Name:        "to",
				Location:    "query",
				Type:        "string",
				Description: "To date: 2020-03-16.",
				Required:    true,
				Enum:        nil,
				Default:     nil,
				Example:     "2025-01-31",
			},
		},
	},
	{
		ToolName:     "finnhub_recommendation_trends",
		OperationID:  "recommendation-trends",
		Title:        "Analysts Recommendation Trends",
		Summary:      "Recommendation Trends",
		Description:  "Get latest analyst recommendation trends for a company.",
		Path:         "/stock/recommendation",
		Method:       "GET",
		Group:        "Company",
		FreeTier:     "",
		AtLeastOneOf: nil,
		Parameters: []ParameterSpec{
			{
				Name:        "symbol",
				Location:    "query",
				Type:        "string",
				Description: "Symbol of the company: AAPL.",
				Required:    true,
				Enum:        nil,
				Default:     nil,
				Example:     "AAPL",
			},
		},
	},
	{
		ToolName:     "finnhub_company_earnings",
		OperationID:  "company-earnings",
		Title:        "Global Company EPS Surprises",
		Summary:      "Earnings Surprises",
		Description:  "Get company historical quarterly earnings surprise going back to 2000.",
		Path:         "/stock/earnings",
		Method:       "GET",
		Group:        "Company",
		FreeTier:     "Last 4 quarters",
		AtLeastOneOf: nil,
		Parameters: []ParameterSpec{
			{
				Name:        "symbol",
				Location:    "query",
				Type:        "string",
				Description: "Symbol of the company: AAPL.",
				Required:    true,
				Enum:        nil,
				Default:     nil,
				Example:     "AAPL",
			},
			{
				Name:        "limit",
				Location:    "query",
				Type:        "integer",
				Description: "Limit number of period returned. Leave blank to get the full history.",
				Required:    false,
				Enum:        nil,
				Default:     nil,
				Example:     4,
			},
		},
	},
	{
		ToolName:     "finnhub_earnings_calendar",
		OperationID:  "earnings-calendar",
		Title:        "Earnings Calendar API | Finnhub Stock API",
		Summary:      "Earnings Calendar",
		Description:  "Get historical and coming earnings release. EPS and Revenue in this endpoint are non-GAAP, which means they are adjusted to exclude some one-time or unusual items. This is the same data investors usually react to and talked about on the media. Estimates are sourced from both sell-side and buy-sid...",
		Path:         "/calendar/earnings",
		Method:       "GET",
		Group:        "Calendar",
		FreeTier:     "1 month of historical earnings and new updates",
		AtLeastOneOf: nil,
		Parameters: []ParameterSpec{
			{
				Name:        "from",
				Location:    "query",
				Type:        "string",
				Description: "From date: 2020-03-15.",
				Required:    false,
				Enum:        nil,
				Default:     nil,
				Example:     "2025-01-01",
			},
			{
				Name:        "to",
				Location:    "query",
				Type:        "string",
				Description: "To date: 2020-03-16.",
				Required:    false,
				Enum:        nil,
				Default:     nil,
				Example:     "2025-01-31",
			},
			{
				Name:        "symbol",
				Location:    "query",
				Type:        "string",
				Description: "Filter by symbol: AAPL.",
				Required:    false,
				Enum:        nil,
				Default:     nil,
				Example:     "AAPL",
			},
			{
				Name:        "international",
				Location:    "query",
				Type:        "boolean",
				Description: "Set to true to include international markets. Default value is false",
				Required:    false,
				Enum:        nil,
				Default:     false,
				Example:     false,
			},
		},
	},
	{
		ToolName:     "finnhub_quote",
		OperationID:  "quote",
		Title:        "Global Stocks, Forex, Crypto price",
		Summary:      "Quote",
		Description:  "Get real-time quote data for US stocks. Constant polling is not recommended. Use websocket if you need real-time updates.Real-time stock prices for international markets are supported for Enterprise clients via our partner's feed. Contact Us to learn more.",
		Path:         "/quote",
		Method:       "GET",
		Group:        "Market",
		FreeTier:     "",
		AtLeastOneOf: nil,
		Parameters: []ParameterSpec{
			{
				Name:        "symbol",
				Location:    "query",
				Type:        "string",
				Description: "Symbol",
				Required:    true,
				Enum:        nil,
				Default:     nil,
				Example:     "AAPL",
			},
		},
	},
	{
		ToolName:     "finnhub_forex_exchanges",
		OperationID:  "forex-exchanges",
		Title:        "List Forex Exchanges",
		Summary:      "Forex Exchanges",
		Description:  "List supported forex exchanges",
		Path:         "/forex/exchange",
		Method:       "GET",
		Group:        "Forex",
		FreeTier:     "",
		AtLeastOneOf: nil,
		Parameters:   []ParameterSpec{},
	},
	{
		ToolName:     "finnhub_forex_symbols",
		OperationID:  "forex-symbols",
		Title:        "Forex Symbols By Exchange",
		Summary:      "Forex Symbol",
		Description:  "List supported forex symbols.",
		Path:         "/forex/symbol",
		Method:       "GET",
		Group:        "Forex",
		FreeTier:     "",
		AtLeastOneOf: nil,
		Parameters: []ParameterSpec{
			{
				Name:        "exchange",
				Location:    "query",
				Type:        "string",
				Description: "Exchange you want to get the list of symbols from.",
				Required:    true,
				Enum:        nil,
				Default:     nil,
				Example:     "OANDA",
			},
		},
	},
	{
		ToolName:     "finnhub_crypto_exchanges",
		OperationID:  "crypto-exchanges",
		Title:        "Crypto Exchanges",
		Summary:      "Crypto Exchanges",
		Description:  "List supported crypto exchanges",
		Path:         "/crypto/exchange",
		Method:       "GET",
		Group:        "Crypto",
		FreeTier:     "",
		AtLeastOneOf: nil,
		Parameters:   []ParameterSpec{},
	},
	{
		ToolName:     "finnhub_crypto_symbols",
		OperationID:  "crypto-symbols",
		Title:        "Crypto Symbols By Exchange",
		Summary:      "Crypto Symbol",
		Description:  "List supported crypto symbols by exchange",
		Path:         "/crypto/symbol",
		Method:       "GET",
		Group:        "Crypto",
		FreeTier:     "",
		AtLeastOneOf: nil,
		Parameters: []ParameterSpec{
			{
				Name:        "exchange",
				Location:    "query",
				Type:        "string",
				Description: "Exchange you want to get the list of symbols from.",
				Required:    true,
				Enum:        nil,
				Default:     nil,
				Example:     "BINANCE",
			},
		},
	},
	{
		ToolName:     "finnhub_covid_19",
		OperationID:  "covid-19",
		Title:        "Real-time COVID-19 data API",
		Summary:      "COVID-19",
		Description:  "Get real-time updates on the number of COVID-19 (Corona virus) cases in the US with a state-by-state breakdown. Data is sourced from CDC and reputable sources. You can also access this API here",
		Path:         "/covid19/us",
		Method:       "GET",
		Group:        "Alternative Data",
		FreeTier:     "",
		AtLeastOneOf: nil,
		Parameters:   []ParameterSpec{},
	},
	{
		ToolName:     "finnhub_fda_committee_meeting_calendar",
		OperationID:  "fda-committee-meeting-calendar",
		Title:        "FDA Calendar | Finnhub",
		Summary:      "FDA Committee Meeting Calendar",
		Description:  "FDA's advisory committees are established to provide functions which support the agency's mission of protecting and promoting the public health, while meeting the requirements set forth in the Federal Advisory Committee Act. Committees are either mandated by statute or established at the discreti...",
		Path:         "/fda-advisory-committee-calendar",
		Method:       "GET",
		Group:        "Alternative Data",
		FreeTier:     "",
		AtLeastOneOf: nil,
		Parameters:   []ParameterSpec{},
	},
	{
		ToolName:     "finnhub_stock_uspto_patent",
		OperationID:  "stock-uspto-patent",
		Title:        "USPTO Patents",
		Summary:      "USPTO Patents",
		Description:  "List USPTO patents for companies. Limit to 250 records per API call.",
		Path:         "/stock/uspto-patent",
		Method:       "GET",
		Group:        "Alternative Data",
		FreeTier:     "",
		AtLeastOneOf: nil,
		Parameters: []ParameterSpec{
			{
				Name:        "symbol",
				Location:    "query",
				Type:        "string",
				Description: "Symbol.",
				Required:    true,
				Enum:        nil,
				Default:     nil,
				Example:     "AAPL",
			},
			{
				Name:        "from",
				Location:    "query",
				Type:        "string",
				Description: "From date YYYY-MM-DD.",
				Required:    true,
				Enum:        nil,
				Default:     nil,
				Example:     "2025-01-01",
			},
			{
				Name:        "to",
				Location:    "query",
				Type:        "string",
				Description: "To date YYYY-MM-DD.",
				Required:    true,
				Enum:        nil,
				Default:     nil,
				Example:     "2025-01-31",
			},
		},
	},
	{
		ToolName:     "finnhub_stock_visa_application",
		OperationID:  "stock-visa-application",
		Title:        "H1-B Visa Application API for public companies",
		Summary:      "H1-B Visa Application",
		Description:  "Get a list of H1-B and Permanent visa applications for companies from the DOL. The data is updated quarterly.",
		Path:         "/stock/visa-application",
		Method:       "GET",
		Group:        "Alternative Data",
		FreeTier:     "",
		AtLeastOneOf: nil,
		Parameters: []ParameterSpec{
			{
				Name:        "symbol",
				Location:    "query",
				Type:        "string",
				Description: "Symbol.",
				Required:    true,
				Enum:        nil,
				Default:     nil,
				Example:     "AAPL",
			},
			{
				Name:        "from",
				Location:    "query",
				Type:        "string",
				Description: "From date YYYY-MM-DD. Filter on the beginDate column.",
				Required:    true,
				Enum:        nil,
				Default:     nil,
				Example:     "2025-01-01",
			},
			{
				Name:        "to",
				Location:    "query",
				Type:        "string",
				Description: "To date YYYY-MM-DD. Filter on the beginDate column.",
				Required:    true,
				Enum:        nil,
				Default:     nil,
				Example:     "2025-01-31",
			},
		},
	},
	{
		ToolName:     "finnhub_stock_lobbying",
		OperationID:  "stock-lobbying",
		Title:        "Senate and House lobbying data from public companies",
		Summary:      "Senate Lobbying",
		Description:  "Get a list of reported lobbying activities in the Senate and the House.",
		Path:         "/stock/lobbying",
		Method:       "GET",
		Group:        "Alternative Data",
		FreeTier:     "",
		AtLeastOneOf: nil,
		Parameters: []ParameterSpec{
			{
				Name:        "symbol",
				Location:    "query",
				Type:        "string",
				Description: "Symbol.",
				Required:    true,
				Enum:        nil,
				Default:     nil,
				Example:     "AAPL",
			},
			{
				Name:        "from",
				Location:    "query",
				Type:        "string",
				Description: "From date YYYY-MM-DD.",
				Required:    true,
				Enum:        nil,
				Default:     nil,
				Example:     "2025-01-01",
			},
			{
				Name:        "to",
				Location:    "query",
				Type:        "string",
				Description: "To date YYYY-MM-DD.",
				Required:    true,
				Enum:        nil,
				Default:     nil,
				Example:     "2025-01-31",
			},
		},
	},
	{
		ToolName:     "finnhub_stock_usa_spending",
		OperationID:  "stock-usa-spending",
		Title:        "USA Spending | Government contracts API",
		Summary:      "USA Spending",
		Description:  "Get a list of government's spending activities from USASpending dataset for public companies. This dataset can help you identify companies that win big government contracts which is extremely important for industries such as Defense, Aerospace, and Education. Only recent data is available via the...",
		Path:         "/stock/usa-spending",
		Method:       "GET",
		Group:        "Alternative Data",
		FreeTier:     "",
		AtLeastOneOf: nil,
		Parameters: []ParameterSpec{
			{
				Name:        "symbol",
				Location:    "query",
				Type:        "string",
				Description: "Symbol.",
				Required:    true,
				Enum:        nil,
				Default:     nil,
				Example:     "AAPL",
			},
			{
				Name:        "from",
				Location:    "query",
				Type:        "string",
				Description: "From date YYYY-MM-DD. Filter for actionDate",
				Required:    true,
				Enum:        nil,
				Default:     nil,
				Example:     "2025-01-01",
			},
			{
				Name:        "to",
				Location:    "query",
				Type:        "string",
				Description: "To date YYYY-MM-DD. Filter for actionDate",
				Required:    true,
				Enum:        nil,
				Default:     nil,
				Example:     "2025-01-31",
			},
		},
	},
	{
		ToolName:     "finnhub_country",
		OperationID:  "country",
		Title:        "Country List",
		Summary:      "Country Metadata",
		Description:  "List all countries and metadata.",
		Path:         "/country",
		Method:       "GET",
		Group:        "Metadata",
		FreeTier:     "",
		AtLeastOneOf: nil,
		Parameters:   []ParameterSpec{},
	},
}
