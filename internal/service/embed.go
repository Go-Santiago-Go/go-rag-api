package service

import (
	"context"
	"encoding/json"
	"fmt"

	"github.com/aws/aws-sdk-go-v2/aws"
	"github.com/aws/aws-sdk-go-v2/service/bedrockruntime"
)

// Embedder turns text into a vector embedding. Bedrock/Titan is one
// implementation; a fake satisfies it in tests with no network call. The RAG
// service depends on this interface, never on the AWS SDK directly.
type Embedder interface {
	Embed(ctx context.Context, text string) ([]float32, error)
}

// BedrockEmbedder implements Embedder using Titan Text Embeddings v2 on Amazon
// Bedrock. It holds a Bedrock Runtime client; all Titan-specific knowledge will
// live in this file so nothing upstream depends on it.
type BedrockEmbedder struct {
	client *bedrockruntime.Client
}

// NewBedrockEmbedder returns an Embedder backed by a configured Bedrock Runtime
// client. The client carries AWS credentials and region, loaded once at main
// and injected here.
func NewBedrockEmbedder(client *bedrockruntime.Client) *BedrockEmbedder {
	return &BedrockEmbedder{client: client}
}

// Compile-time proof BedrockEmbedder satisfies Embedder, fails the build here
// if the method set ever drifts from the interface.
var _ Embedder = (*BedrockEmbedder)(nil)

// titanRequest is the JSON body Titan v2 expects. normalize scales the vector to
// unit length (better cosine-similarity retrieval); dimensions fixes the output
// width so it matches the vector(1024) storage column.
type titanRequest struct {
	InputText  string `json:"inputText"`
	Dimensions int    `json:"dimensions"`
	Normalize  bool   `json:"normalize"`
}

// titanResponse is the JSON body Titan v2 returns. The model also reports a
// token count, which we ignore; the embedding is all the pipeline needs.
type titanResponse struct {
	Embedding []float32 `json:"embedding"`
}

// Embed sends text to Titan v2 and returns its embedding. It marshals a Titan
// request, invokes the model, and unmarshals the Titan response, translating
// between the SDK and the plain []float32 the rest of the service speaks.
func (e *BedrockEmbedder) Embed(ctx context.Context, text string) ([]float32, error) {
	body, err := json.Marshal(titanRequest{
		InputText:  text,
		Dimensions: 1024,
		Normalize:  true,
	})
	if err != nil {
		return nil, fmt.Errorf("marshal titan request: %w", err)
	}

	out, err := e.client.InvokeModel(ctx, &bedrockruntime.InvokeModelInput{
		ModelId:     aws.String("amazon.titan-embed-text-v2:0"),
		ContentType: aws.String("application/json"),
		Body:        body,
	})
	if err != nil {
		return nil, fmt.Errorf("invoke titan model: %w", err)
	}

	var resp titanResponse
	if err := json.Unmarshal(out.Body, &resp); err != nil {
		return nil, fmt.Errorf("unmarshal titan response: %w", err)
	}
	if len(resp.Embedding) == 0 {
		return nil, fmt.Errorf("empty titan embedding")
	}
	return resp.Embedding, nil
}
