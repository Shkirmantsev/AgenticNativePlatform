FROM golang:1.23.0-alpine AS builder

WORKDIR /src

COPY go.mod go.sum ./
RUN go mod download

COPY . .
RUN CGO_ENABLED=0 GOOS=linux GOARCH=amd64 go build -trimpath -ldflags='-s -w' -o /out/finnhub-mcp-server ./cmd/server

FROM alpine:3.21

RUN adduser -D -H -u 10001 appuser
WORKDIR /app

COPY --from=builder /out/finnhub-mcp-server /app/finnhub-mcp-server

USER appuser
EXPOSE 8080

ENTRYPOINT ["/app/finnhub-mcp-server"]
