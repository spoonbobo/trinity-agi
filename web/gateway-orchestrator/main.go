package main

import (
	"database/sql"
	"fmt"
	"log"
	"net/http"
	"os"
	"time"

	"trinity-agi/gateway-orchestrator/internal/api"
	"trinity-agi/gateway-orchestrator/internal/db"
	k8sclient "trinity-agi/gateway-orchestrator/internal/k8s"

	_ "github.com/lib/pq"
	"k8s.io/client-go/kubernetes"
	"k8s.io/client-go/rest"
)

func main() {
	port := envOrDefault("PORT", "8080")
	namespace := envOrDefault("NAMESPACE", "trinity")
	serviceToken := mustEnv("SERVICE_TOKEN")
	pgHost := envOrDefault("POSTGRES_HOST", "localhost")
	pgPort := envOrDefault("POSTGRES_PORT", "5432")
	pgDB := envOrDefault("POSTGRES_DB", "trinity")
	pgUser := envOrDefault("POSTGRES_USER", "postgres")
	pgPassword := mustEnv("POSTGRES_PASSWORD")
	openclawImage := envOrDefault("OPENCLAW_IMAGE", "openclaw/gateway:latest")
	storageClass := envOrDefault("STORAGE_CLASS", "standard")

	// Initialize Kubernetes client
	config, err := rest.InClusterConfig()
	if err != nil {
		log.Fatalf("Failed to get in-cluster config: %v", err)
	}
	clientset, err := kubernetes.NewForConfig(config)
	if err != nil {
		log.Fatalf("Failed to create Kubernetes client: %v", err)
	}

	// Initialize PostgreSQL connection
	connStr := fmt.Sprintf(
		"host=%s port=%s dbname=%s user=%s password=%s sslmode=disable",
		pgHost, pgPort, pgDB, pgUser, pgPassword,
	)
	pool, err := sql.Open("postgres", connStr)
	if err != nil {
		log.Fatalf("Failed to open database connection: %v", err)
	}
	defer pool.Close()

	pool.SetMaxOpenConns(25)
	pool.SetMaxIdleConns(5)
	pool.SetConnMaxLifetime(5 * time.Minute)

	if err := pool.Ping(); err != nil {
		log.Fatalf("Failed to ping database: %v", err)
	}
	log.Println("Connected to PostgreSQL")

	// Initialize service components
	store := db.NewStore(pool)
	k8sClient := k8sclient.NewClient(clientset, namespace)

	// Build router
	router := api.NewRouter(store, k8sClient, serviceToken, namespace, openclawImage, storageClass)

	srv := &http.Server{
		Addr:         ":" + port,
		Handler:      router,
		ReadTimeout:  15 * time.Second,
		WriteTimeout: 30 * time.Second,
		IdleTimeout:  60 * time.Second,
	}

	log.Printf("gateway-orchestrator listening on :%s (namespace=%s)", port, namespace)
	if err := srv.ListenAndServe(); err != nil && err != http.ErrServerClosed {
		log.Fatalf("Server failed: %v", err)
	}
}

func envOrDefault(key, fallback string) string {
	if v := os.Getenv(key); v != "" {
		return v
	}
	return fallback
}

func mustEnv(key string) string {
	v := os.Getenv(key)
	if v == "" {
		log.Fatalf("Required environment variable %s is not set", key)
	}
	return v
}
