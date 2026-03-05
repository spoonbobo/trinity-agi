package resolver

import (
	"context"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"time"
)

// Backend represents a resolved upstream OpenClaw gateway pod.
type Backend struct {
	Host    string `json:"host"`
	Port    int    `json:"port"`
	Token   string `json:"token"`
	PodName string `json:"podName,omitempty"`
}

// Resolver resolves OpenClaw IDs to backend gateway pods via the orchestrator.
type Resolver struct {
	orchestratorURL string
	serviceToken    string
	cacheTTL        time.Duration
	cache           *Cache
	httpClient      *http.Client
}

// New creates a new Resolver.
func New(orchestratorURL, serviceToken string, cacheTTL time.Duration) *Resolver {
	return &Resolver{
		orchestratorURL: orchestratorURL,
		serviceToken:    serviceToken,
		cacheTTL:        cacheTTL,
		cache:           NewCache(),
		httpClient: &http.Client{
			Timeout: 10 * time.Second,
		},
	}
}

// Resolve looks up the backend for a given OpenClaw ID. It checks the cache
// first and falls back to the orchestrator on a miss.
func (r *Resolver) Resolve(ctx context.Context, openclawID string) (*Backend, error) {
	// Check cache first
	if backend, ok := r.cache.Get(openclawID); ok {
		return backend, nil
	}

	// Cache miss: query orchestrator
	url := fmt.Sprintf("%s/openclaws/%s/resolve", r.orchestratorURL, openclawID)

	req, err := http.NewRequestWithContext(ctx, http.MethodGet, url, nil)
	if err != nil {
		return nil, fmt.Errorf("creating resolve request: %w", err)
	}
	if r.serviceToken != "" {
		req.Header.Set("Authorization", "Bearer "+r.serviceToken)
	}

	resp, err := r.httpClient.Do(req)
	if err != nil {
		return nil, fmt.Errorf("resolve request failed: %w", err)
	}
	defer resp.Body.Close()

	if resp.StatusCode == http.StatusNotFound {
		return nil, nil // no backend found
	}

	if resp.StatusCode != http.StatusOK {
		body, _ := io.ReadAll(resp.Body)
		return nil, fmt.Errorf("resolve returned status %d: %s", resp.StatusCode, string(body))
	}

	var backend Backend
	if err := json.NewDecoder(resp.Body).Decode(&backend); err != nil {
		return nil, fmt.Errorf("decoding resolve response: %w", err)
	}

	// Store in cache keyed by openclawID
	r.cache.Set(openclawID, &backend, r.cacheTTL)

	return &backend, nil
}

// CheckAssignment verifies that a user is assigned to a specific OpenClaw
// instance by querying the orchestrator's user openclaws endpoint.
func (r *Resolver) CheckAssignment(ctx context.Context, userID, openclawID string) (bool, error) {
	// Check cache first
	cacheKey := "assign:" + userID + ":" + openclawID
	if _, ok := r.cache.Get(cacheKey); ok {
		return true, nil
	}

	url := fmt.Sprintf("%s/users/%s/openclaws", r.orchestratorURL, userID)
	req, err := http.NewRequestWithContext(ctx, http.MethodGet, url, nil)
	if err != nil {
		return false, fmt.Errorf("creating assignment check request: %w", err)
	}
	if r.serviceToken != "" {
		req.Header.Set("Authorization", "Bearer "+r.serviceToken)
	}

	resp, err := r.httpClient.Do(req)
	if err != nil {
		return false, fmt.Errorf("assignment check request failed: %w", err)
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		return false, nil
	}

	var openclaws []struct {
		ID string `json:"id"`
	}
	if err := json.NewDecoder(resp.Body).Decode(&openclaws); err != nil {
		return false, fmt.Errorf("decoding assignment check response: %w", err)
	}

	for _, oc := range openclaws {
		if oc.ID == openclawID {
			// Cache the positive result
			r.cache.Set(cacheKey, &Backend{}, r.cacheTTL)
			return true, nil
		}
	}
	return false, nil
}

// InvalidateCache removes the cached backend for an OpenClaw ID.
func (r *Resolver) InvalidateCache(openclawID string) {
	r.cache.Delete(openclawID)
}
