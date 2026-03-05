package api

import (
	"crypto/subtle"
	"net/http"
	"strings"
)

// authMiddleware validates the Authorization: Bearer <SERVICE_TOKEN> header
// using constant-time comparison. The /health endpoint is excluded.
func authMiddleware(serviceToken string) func(http.Handler) http.Handler {
	return func(next http.Handler) http.Handler {
		return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
			// Skip auth for health check
			if r.URL.Path == "/health" {
				next.ServeHTTP(w, r)
				return
			}

			authHeader := r.Header.Get("Authorization")
			if authHeader == "" {
				http.Error(w, `{"error":"missing authorization header"}`, http.StatusUnauthorized)
				return
			}

			parts := strings.SplitN(authHeader, " ", 2)
			if len(parts) != 2 || !strings.EqualFold(parts[0], "Bearer") {
				http.Error(w, `{"error":"invalid authorization format"}`, http.StatusUnauthorized)
				return
			}

			token := parts[1]
			if subtle.ConstantTimeCompare([]byte(token), []byte(serviceToken)) != 1 {
				http.Error(w, `{"error":"invalid service token"}`, http.StatusForbidden)
				return
			}

			next.ServeHTTP(w, r)
		})
	}
}
