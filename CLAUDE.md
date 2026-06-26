# CLAUDE.md

Guidance for working in this repository.

## What this is

A containerized **Go RAG (Retrieval-Augmented Generation) service** that ingests documents and
answers questions about them over HTTP, returning grounded answers with structured citations:
`{ answer, sources[] }`. Two endpoints, one service:

- `POST /ingest` makes a document searchable: chunk it, embed each chunk (Bedrock), store vectors.
- `POST /query` answers a question: embed it, similarity-search chunks, have the LLM write a cited
  answer, return `{ answer, sources[] }`.

It is a deliberately plain HTTP microservice that knows nothing about agents. Project 2 (a separate
Strands agent) consumes `/query` as a tool. The structured `sources[]` response is the contract that
keeps that boundary clean.

**Stack:** Go, pgvector/Postgres, AWS Bedrock (Titan v2 embeddings plus a Claude model for
generation), S3 (raw doc storage), Docker, Terraform, GitHub Actions to ECR, ECS Express Mode on
Fargate.

**Canonical name:** `go-rag-api`. Use it for the repo, the README title, and the Go module path
(`github.com/<you>/go-rag-api`). Do not introduce alternate names.

## Status: pre-code

As of this writing the repo contains only planning docs. There is **no Go code, no `go.mod`, and no
git repo yet**. The full phased build plan is in `PROJECT1_BUILD_PLAN.md` (phases 0 through 8);
Phase 6 is the MVP cut line. `PROJECT2_BUILD_PLAN.md` describes the downstream agent. The commands
and layout below are the *target* the plan builds toward. Create them as you implement each phase.

## Target layout

```
cmd/server/main.go      # entrypoint: wires dependencies, starts the server. Keep thin.
internal/handler/       # HTTP handlers: parse request, call service, write response. No logic here.
internal/service/       # RAG logic: chunk, embed, search, generate.
internal/store/         # VectorStore interface plus pgvector implementation. Only place that knows SQL.
migrations/             # SQL schema (e.g. 001_init.sql).
infra/                  # Terraform (Phase 7+).
docker-compose.yml      # local pgvector (pgvector/pgvector:pg16).
Dockerfile              # multi-stage; distroless final image (Phase 8).
```

Use Go's conventional layout: `cmd/` for the `main` entrypoint, `internal/` for app code the
compiler forbids other modules from importing.

## Commands (once code exists)

```bash
go run ./cmd/server          # run the service (listens on :8080)
go build ./...               # build everything
go vet ./...                 # static checks (also runs in CI)
go test ./...                # tests (also runs in CI)
docker compose up -d         # start local Postgres plus pgvector
curl localhost:8080/health   # health check
```

CI (`.github/workflows/ci.yml`) runs `go build`, `go vet`, and `go test` on push and PR.

## Key conventions and design

- **Dependency inversion at the boundaries** is the core idea. Service logic depends on the
  `VectorStore` interface (and embedder/generator interfaces), never on pgvector or Bedrock
  directly. Concrete implementations are plugged in at `main`. This is what lets tests use a fake
  store with no database, and lets pgvector be swapped without touching RAG logic.
- **Handlers orchestrate, services do the work.** Handlers parse HTTP and return status codes; all
  business logic lives in `internal/service` so it stays unit-testable.
- **Same embedding model on both sides.** Documents and questions must be embedded with the same
  Bedrock model, since vectors from different models aren't comparable.
- **Vector column dimension must match the embedding model** (e.g. `vector(1024)` for Titan v2).
- **`/query` returns `{ answer, sources[] }`**, not prose. Structured sources are the contract for
  the human demo and for Project 2's agent.
- **Modern stdlib.** Use `net/http` with Go 1.22+ method-based routing
  (`mux.HandleFunc("GET /health", …)`) and `log/slog` for structured logs. No web framework; stdlib
  is sufficient.
- **Testing.** Test pure logic (chunking) directly; test `/query` with a fake `VectorStore`
  implementation rather than a real DB. Prefer table-driven tests.
- **Comments explain the *why*, not the *what*.** Document exported identifiers per Go convention.

## Local-first, cloud-last

Build and prove the whole loop on the laptop (Docker) through Phase 6 before any AWS work. Keep AWS
cheap and run `terraform destroy` after each session so nothing bills overnight.

## Related instructions

`CLAUDE.local.md` (git-ignored, not part of the shipped project) holds local working notes and
conventions. Read it if present; it governs *how* to work in this repo.
