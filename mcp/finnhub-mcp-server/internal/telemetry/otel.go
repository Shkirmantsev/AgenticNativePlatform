package telemetry

import (
	"context"
	"errors"
	"os"
	"strings"

	"go.opentelemetry.io/otel/attribute"
	"go.opentelemetry.io/otel"
	"go.opentelemetry.io/otel/exporters/otlp/otlptrace/otlptracegrpc"
	"go.opentelemetry.io/otel/propagation"
	"go.opentelemetry.io/otel/sdk/resource"
	sdktrace "go.opentelemetry.io/otel/sdk/trace"
)

// SetupOTel configures a process-wide trace provider for the MCP server.
//
// The exporter reads its destination from the standard OTEL_* environment
// variables. When no OTLP trace endpoint is configured, telemetry stays
// disabled and the returned shutdown function is a no-op.
func SetupOTel(ctx context.Context, serviceName, serviceVersion string) (func(context.Context) error, error) {
	if tracingDisabled() {
		return func(context.Context) error { return nil }, nil
	}

	exporter, err := otlptracegrpc.New(ctx)
	if err != nil {
		return nil, err
	}

	res, err := resource.Merge(
		resource.Default(),
		// Keep service identity schemaless so it can merge with whatever schema
		// version the active OTel SDK/default detectors are using at runtime.
		resource.NewSchemaless(
			attribute.String("service.name", serviceName),
			attribute.String("service.version", serviceVersion),
		),
	)
	if err != nil {
		return nil, err
	}

	tracerProvider := sdktrace.NewTracerProvider(
		sdktrace.WithBatcher(exporter),
		sdktrace.WithResource(res),
	)

	otel.SetTracerProvider(tracerProvider)
	otel.SetTextMapPropagator(propagation.NewCompositeTextMapPropagator(
		propagation.TraceContext{},
		propagation.Baggage{},
	))

	return func(ctx context.Context) error {
		var shutdownErr error
		if err := tracerProvider.Shutdown(ctx); err != nil {
			shutdownErr = errors.Join(shutdownErr, err)
		}
		return shutdownErr
	}, nil
}

func tracingDisabled() bool {
	if strings.EqualFold(strings.TrimSpace(os.Getenv("OTEL_SDK_DISABLED")), "true") {
		return true
	}

	if endpointConfigured("OTEL_EXPORTER_OTLP_TRACES_ENDPOINT") {
		return false
	}
	if endpointConfigured("OTEL_EXPORTER_OTLP_ENDPOINT") {
		return false
	}

	return true
}

func endpointConfigured(envKey string) bool {
	return strings.TrimSpace(os.Getenv(envKey)) != ""
}
