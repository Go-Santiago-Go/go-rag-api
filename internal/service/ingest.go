package service

import (
	"context"
	"fmt"

	"github.com/go-santiago-go/go-rag-api/internal/store"
)

// Chunking parameters. Fixed-size passages with a small overlap so an idea that
// straddles a boundary survives whole in at least one chunk. Tunable later if
// retrieval quality warrants; kept as constants to avoid magic numbers.
const (
	chunkSize    = 500
	chunkOverlap = 50
)

// IngestService turns a document's text into stored, searchable vectors. It
// depends only on the Embedder and VectorStore interfaces, so tests can drive
// the whole ingest flow with fakes, no Bedrock and no database.
type IngestService struct {
	embedder Embedder
	store    store.VectorStore
}

// NewIngestService wires the ingest pipeline from its dependencies. The concrete
// Bedrock embedder and pgvector store are injected at main; a test injects fakes.
func NewIngestService(embedder Embedder, vs store.VectorStore) *IngestService {
	return &IngestService{embedder: embedder, store: vs}
}

// Ingest makes a document searchable: it splits text into overlapping passages,
// embeds each one, and persists the resulting vectors under documentID. It runs
// synchronously, so a returned nil means every chunk is embedded and stored. The
// first embed or save failure aborts and is returned wrapped for context.
func (s *IngestService) Ingest(ctx context.Context, documentID, text string) error {
	passages := Chunk(text, chunkSize, chunkOverlap)

	// Embed one passage at a time, then save the batch in a single store call.
	// Embedding must use the same model as queries or the vectors are not
	// comparable at search time; that model choice lives in the injected Embedder.
	chunks := make([]store.Chunk, 0, len(passages))
	for _, passage := range passages {
		embedding, err := s.embedder.Embed(ctx, passage)
		if err != nil {
			return fmt.Errorf("embed chunk: %w", err)
		}
		chunks = append(chunks, store.Chunk{
			DocumentID: documentID,
			Content:    passage,
			Embedding:  embedding,
		})
	}

	return s.store.Save(ctx, chunks)
}
