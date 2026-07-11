package store

import (
	"context"
	_ "embed"
)

// schemaSQL is the canonical schema, compiled into the binary at build time.
// Embedding it (rather than reading a file at runtime) keeps the distroless
// image self-contained: there is no schema.sql on disk in the final image.
//
//go:embed schema.sql
var schemaSQL string

// Migrate applies the embedded schema. Every statement is idempotent
// (IF NOT EXISTS), so this is safe to run on every startup: it creates the
// vector extension and chunks table on first boot and is a no-op thereafter.
//
// This is how the schema reaches cloud RDS, which (unlike the local
// docker-compose Postgres) has no init-directory hook to load migrations.
func (s *Postgres) Migrate(ctx context.Context) error {
	_, err := s.db.ExecContext(ctx, schemaSQL)
	return err
}
