# go-rag-api

[![ci](https://github.com/Go-Santiago-Go/go-rag-api/actions/workflows/ci.yml/badge.svg)](https://github.com/Go-Santiago-Go/go-rag-api/actions/workflows/ci.yml)

A containerized Go service that ingests documents and answers questions about them over HTTP,
returning grounded answers with structured citations. Retrieval Augmented Generation (RAG) as a
plain HTTP microservice, built to be consumed by a human, a browser, or an agent.

Two endpoints, one service:

- `POST /ingest` makes a document searchable: chunk it, embed each chunk, store the vectors.
- `POST /query` answers a question: embed it, similarity search the chunks, have an LLM write a
  cited answer, and return `{ answer, sources[] }`.

> **Live demo:** coming in Phase 8 (deployed to AWS). Until then the full loop runs locally via
> `docker compose up`. See the roadmap below for current status.

## Architecture

Target architecture (see the roadmap for what is built today):

```mermaid
flowchart LR
    U[Client] -->|POST /ingest| S[Go service]
    U -->|POST /query| S
    S -->|embed + generate| B[AWS Bedrock]
    S -->|store / search vectors| P[(pgvector)]
    S -->|raw docs| O[(S3)]
```

A document is chunked, each chunk is embedded with Bedrock, and the vectors are stored in pgvector.
A query is embedded with the same model, the nearest chunks are retrieved by vector similarity, and
those chunks are handed to an LLM that writes an answer grounded in them, returned with the source
chunks it used.

### Deployment (AWS, Phase 7–8)

The service runs in a production-shaped three-tier VPC: a public tier for the load balancer and NAT,
a private app tier for the container, and a private data tier for the database with no public
endpoint. Traffic flows down through a chain of security groups, each tier trusting only the one
above it; the app reaches Bedrock and ECR outbound through the NAT gateway.

```mermaid
flowchart TB
    user([Client / Project 2 Agent])

    subgraph cloud["☁️ AWS Cloud · us-east-1"]
        bedrock["Amazon Bedrock<br/>Titan v2 · Claude Haiku"]
        ecr[("ECR<br/>image")]
        secrets["Secrets Manager<br/>DATABASE_URL"]

        subgraph vpc["VPC · 10.0.0.0/16"]
            igw{{"Internet Gateway"}}

            subgraph pub["🌐 Public tier"]
                direction LR
                pubA["subnet · AZ-a<br/>10.0.0.0/24"]
                alb(["Application<br/>Load Balancer<br/>:443"])
                nat{{"NAT<br/>Gateway"}}
                pubB["subnet · AZ-b<br/>10.0.1.0/24"]
            end

            subgraph app["🔒 Private app tier"]
                direction LR
                appA["subnet · AZ-a<br/>10.0.10.0/24"]
                ecs["ECS Fargate<br/>go-rag-api :8080<br/>no public IP"]
                appB["subnet · AZ-b<br/>10.0.11.0/24<br/>(scales here)"]
            end

            subgraph data["🔒 Private data tier"]
                direction LR
                dataA["subnet · AZ-a<br/>10.0.20.0/24"]
                rds[("RDS Postgres 16<br/>pgvector<br/>publicly_accessible = false")]
                dataB["subnet · AZ-b<br/>10.0.21.0/24<br/>(Multi-AZ standby · parked)"]
            end
        end
    end

    user ==>|HTTPS :443| igw ==> alb
    alb ==>|SG chain :8080| ecs
    ecs ==>|SG chain :5432| rds
    ecs -->|egress| nat --> igw
    nat -.->|InvokeModel| bedrock
    nat -.->|image pull| ecr
    ecs -.->|inject DSN| secrets

    classDef public fill:#e8f4ff,stroke:#2b6cb0,color:#1a365d;
    classDef private fill:#f0fff4,stroke:#276749,color:#22543d;
    classDef dataTier fill:#fffaf0,stroke:#b7791f,color:#744210;
    classDef ext fill:#2d3748,stroke:#4a5568,color:#fff;
    class alb,nat,pubA,pubB public;
    class ecs,appA,appB private;
    class rds,dataA,dataB dataTier;
    class bedrock,ecr,secrets ext;
    linkStyle 0,1,2,3 stroke:#2b6cb0,stroke-width:3px;
```

The bold path traces a request: **Client → IGW → ALB → ECS → RDS**, each hop crossing a security
group that trusts only the tier above. The thin dashed lines are the app's outbound calls: egress to
Bedrock and ECR goes through the NAT gateway, and the DB connection string is injected from Secrets
Manager. The greyed second-AZ slots (standby RDS, extra app capacity) are what production *scale*
adds; the demo provisions the subnets but runs single-AZ.

Single NAT and single-AZ RDS keep this demo cheap; production would run a NAT per AZ, Multi-AZ RDS,
and VPC endpoints for the AWS services. Everything is torn down with `terraform destroy` after each
session so nothing bills overnight.

The `infra/` directory holds the Terraform for this stack (29 resources). From `infra/`:

```bash
terraform init      # download the AWS provider
terraform plan      # preview the resources
terraform apply     # build them (RDS takes ~5 min)
terraform destroy   # tear it all down; run after every session
```

Credentials come from your AWS CLI configuration. The only always-on costs are the NAT gateway and
the RDS instance, so a `destroy` after each session keeps the bill at pennies. The database password
is never handed to Terraform: RDS generates it and stores it in Secrets Manager
(`manage_master_user_password`), so it never lands in state.

## Design decisions

Every choice below optimizes for one constraint: the simplest component that satisfies the
requirement, reaching for managed or heavyweight services only where the workload genuinely
demands them. The decisions that are not load-bearing sit behind interfaces, so they can change
later without disturbing the core.

| Decision | Choice | Why | Also considered |
|---|---|---|---|
| Vector storage | pgvector / Postgres | One datastore, standard SQL, free and reproducible locally, swappable behind an interface | OpenSearch Serverless, S3 Vectors |
| API style | REST / JSON | Consumers are a human, a browser, and one agent tool; no streaming requirement yet | gRPC |
| Service shape | Single Go service | Smallest thing that ships; no premature split into a separate ingestion service | Separate Python ingestion service |
| Query response | `{ answer, sources[] }` | Structured citations make the demo verifiable and give a downstream agent clean data to reason over | Prose-only answers |
| Text extraction | Local extraction | Free and offline; reach for a managed service only if the workload needs it | AWS Textract |
| Compute | ECS Express Mode on Fargate | Managed networking, load balancing, and scaling from a container image; App Runner is closed to new customers | Full ECS Fargate |

The pattern under all of it is **dependency inversion at the boundaries**: the RAG logic depends on
a `VectorStore` interface (plus embedder and generator interfaces), and the concrete pieces
(pgvector, Bedrock) are plugged in at `main`. That is what lets the service be tested with a fake
store and no database, and lets pgvector be swapped without touching the RAG logic.

## Status & roadmap

Built local-first, then deployed to AWS. The MVP cut line is the end of Phase 6.

- [x] **Phase 0** — project scaffold, CI green
- [x] **Phase 1** — HTTP server with `/health`
- [x] **Phase 2** — Postgres + pgvector running in Docker
- [x] **Phase 3** — `VectorStore` interface + pgvector implementation
- [x] **Phase 4** — `POST /ingest`: document to stored embeddings
- [x] **Phase 5** — `POST /query`: grounded answer with sources
- [x] **Phase 6** — tests, full README, **MVP complete**
- [x] **Phase 7** — Terraform: three-tier VPC, private RDS, S3, and IAM (apply/destroy verified)
- [ ] **Phase 8** — deployed on ECS Express Mode, live URL

## Stack

- **Go** for the service (standard library `net/http`, no framework).
- **pgvector / Postgres** for vector storage.
- **AWS Bedrock** for embeddings (Titan v2) and answer generation (Claude).
- **S3** for raw document storage.
- **Docker** to containerize, **Terraform** for infrastructure, **GitHub Actions** for CI/CD to ECR.
- **ECS Express Mode on Fargate** to run it.

## Local development

```bash
go run ./cmd/server   # run the service
go build ./...         # build everything
go vet ./...           # static checks
go test ./...          # tests
```

CI runs `go build`, `go vet`, and `go test` on every push and pull request, with the Go version
sourced from `go.mod` so it lives in one place.

## Endpoints

### `POST /ingest`

Makes a document searchable: chunk the text, embed each chunk with Bedrock Titan v2, and store the
vectors in pgvector. Runs synchronously and returns `201 Created` once every chunk is stored.

The service reads its database connection from `DATABASE_URL` (defaulting to the local
`docker compose` Postgres) and calls Bedrock, so the machine running it needs AWS credentials with
Bedrock access and the Titan v2 model enabled in the region.

```bash
docker compose up -d      # start local Postgres + pgvector; schema auto-applies on first boot
go run ./cmd/server       # start the service on :8080

curl -i -X POST localhost:8080/ingest \
  -H 'Content-Type: application/json' \
  -d '{"document_id":"doc-1","text":"pgvector stores embeddings inside Postgres."}'
# HTTP/1.1 201 Created
```

Request body: `{ "document_id": string, "text": string }`. Both fields are required; a malformed or
incomplete body returns `400`, and a Bedrock or database failure returns `500`.

### `POST /query`

Answers a question about the ingested corpus: embed the question with the same Titan v2 model, retrieve
the nearest chunks from pgvector by vector similarity, and have a Claude model write an answer
constrained to those chunks. Returns `{ answer, sources[] }`, where each source is the chunk that
backed the answer. Generation goes through the Bedrock Converse API, so the running machine also needs
the Claude model enabled in the region (a one-time Anthropic use-case form per account gates first use).

```bash
curl -s -X POST localhost:8080/query \
  -H 'Content-Type: application/json' \
  -d '{"question":"Where does pgvector store embeddings?"}'
# { "answer": "pgvector stores embeddings inside Postgres.",
#   "sources": [ { "content": "...", "document_id": "doc-1", "page": 1 } ] }
```

Request body: `{ "question": string }`. The question is required; a malformed body or empty question
returns `400`, and a Bedrock or database failure returns `500`. The `sources[]` array is the contract
that makes an answer auditable and gives a downstream agent structured data instead of prose.

## Writeups

Build notes and explanations published alongside this project:

- _Wiring CI before you have code to test: a Go + GitHub Actions walkthrough_ (coming soon)

More as the project progresses.
