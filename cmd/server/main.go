package main

import (
	"context"
	"log/slog"
	"net/http"
	"os"

	"github.com/aws/aws-sdk-go-v2/config"
	"github.com/aws/aws-sdk-go-v2/service/bedrockruntime"

	"github.com/go-santiago-go/go-rag-api/internal/handler"
	"github.com/go-santiago-go/go-rag-api/internal/service"
	"github.com/go-santiago-go/go-rag-api/internal/store"
)

// main is the composition root: the one place that builds every concrete
// dependency (Postgres store, Bedrock embedder) and injects them down through
// interfaces. Nothing below main knows which store or embedder it received.
func main() {
	ctx := context.Background()

	// DSN from the environment with a local default, so the same binary runs
	// against docker-compose locally and RDS in the cloud with no code change;
	// only DATABASE_URL differs.
	dsn := getenv("DATABASE_URL", "postgres://postgres:localdev@localhost:5432/go_rag_api?sslmode=disable")
	// NewPostgres pings on startup, so a bad DSN fails here rather than on the
	// first request. A store we cannot reach is fatal: log and exit non-zero.
	pg, err := store.NewPostgres(ctx, dsn)
	if err != nil {
		slog.Error("connect postgres", "err", err)
		os.Exit(1)
	}

	// LoadDefaultConfig walks the standard AWS credential chain (env vars, the
	// shared config files, then an IAM role) and resolves the region. That is
	// what lets this binary use local creds on a laptop and the task role on
	// Fargate without any code change.
	cfg, err := config.LoadDefaultConfig(ctx)
	if err != nil {
		slog.Error("load aws config", "err", err)
		os.Exit(1)
	}
	bedrockClient := bedrockruntime.NewFromConfig(cfg)
	embedder := service.NewBedrockEmbedder(bedrockClient)
	generator := service.NewBedrockGenerator(bedrockClient)

	// Inject the concrete embedder and store into the service, which only ever
	// sees the Embedder and VectorStore interfaces.
	ingestSvc := service.NewIngestService(embedder, pg)
	querySvc := service.NewQueryService(embedder, pg, generator)

	mux := http.NewServeMux()
	mux.HandleFunc("GET /health", handler.Health())
	// handler.Ingest closes the service into a route-shaped handler.
	mux.HandleFunc("POST /ingest", handler.Ingest(ingestSvc))
	mux.HandleFunc("POST /query", handler.Query(querySvc))

	slog.Info("listening", "addr", ":8080")
	// ListenAndServe blocks until it fails to serve; a non-nil return means the
	// process can no longer accept requests, so log and exit non-zero.
	if err := http.ListenAndServe(":8080", mux); err != nil {
		slog.Error("server stopped", "err", err)
		os.Exit(1)
	}
}

// getenv returns the value of key, or fallback when it is unset or empty. It
// keeps the local default in one place so running with docker-compose needs no
// environment setup while production overrides via the environment.
func getenv(key, fallback string) string {
	if v := os.Getenv(key); v != "" {
		return v
	}
	return fallback
}
