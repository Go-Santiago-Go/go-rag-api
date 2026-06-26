package main

import (
	"log"
	"net/http"

	"github.com/go-santiago-go/go-rag-api/internal/handler"
)

func main() {
	mux := http.NewServeMux()
	mux.HandleFunc("GET /health", handler.Health())

	log.Println("listening on :8080")
	// ListenAndServe blocks until it fails to serve; a non-nil return means the
	// process can no longer accept requests, so exit non-zero to signal failure.
	log.Fatal(http.ListenAndServe(":8080", mux))
}
