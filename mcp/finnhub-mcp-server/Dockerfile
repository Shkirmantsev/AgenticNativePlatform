FROM --platform=$BUILDPLATFORM golang:1.25.8-alpine AS builder

WORKDIR /src

COPY go.mod go.sum ./
RUN go mod download

COPY . .
ARG TARGETOS
ARG TARGETARCH
RUN CGO_ENABLED=0 GOOS=${TARGETOS} GOARCH=${TARGETARCH} go build -trimpath -ldflags='-s -w' -o /out/finnhub-mcp-server ./cmd/server

FROM alpine:3.21

RUN adduser -D -H -u 10001 appuser
WORKDIR /app

LABEL org.opencontainers.image.title="finnhub-mcp-server"
LABEL org.opencontainers.image.description="Finnhub MCP server for AgenticNativePlatform"
LABEL org.opencontainers.image.source="https://github.com/shkirmantsev/agenticnativeplatform"

COPY --from=builder /out/finnhub-mcp-server /app/finnhub-mcp-server

USER appuser
EXPOSE 8080

ENTRYPOINT ["/app/finnhub-mcp-server"]
