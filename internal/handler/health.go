package handler

import "net/http"

// Health returns a handler that reports service liveness
// Deployment platforms (ECS, load balancers) poll this before routing traffic
func Health() http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		w.Write([]byte(`{"status": "ok"}`))
	}
}
