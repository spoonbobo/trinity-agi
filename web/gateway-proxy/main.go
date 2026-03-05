package main

import (
	"log"
	"net/http"
	"os"
	"strconv"
	"time"

	"trinity-agi/gateway-proxy/internal/proxy"
	"trinity-agi/gateway-proxy/internal/resolver"
)

func main() {
	port := envOrDefault("PORT", "18800")
	jwtSecret := os.Getenv("JWT_SECRET")
	orchestratorURL := envOrDefault("ORCHESTRATOR_URL", "http://gateway-orchestrator:18801")
	serviceToken := os.Getenv("ORCHESTRATOR_SERVICE_TOKEN")
	cacheTTLStr := envOrDefault("RESOLVER_CACHE_TTL", "60")

	if jwtSecret == "" {
		log.Fatal("JWT_SECRET environment variable is required")
	}

	cacheTTL, err := strconv.Atoi(cacheTTLStr)
	if err != nil {
		log.Fatalf("Invalid RESOLVER_CACHE_TTL: %v", err)
	}

	res := resolver.New(orchestratorURL, serviceToken, time.Duration(cacheTTL)*time.Second)
	handler := proxy.NewHandler([]byte(jwtSecret), res)

	mux := http.NewServeMux()
	mux.HandleFunc("/health", func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		w.WriteHeader(http.StatusOK)
		w.Write([]byte(`{"status":"ok"}`))
	})
	mux.HandleFunc("/", handler.ServeHTTP)

	addr := ":" + port
	log.Printf("gateway-proxy listening on %s", addr)
	if err := http.ListenAndServe(addr, mux); err != nil {
		log.Fatalf("server error: %v", err)
	}
}

func envOrDefault(key, defaultVal string) string {
	if v := os.Getenv(key); v != "" {
		return v
	}
	return defaultVal
}
