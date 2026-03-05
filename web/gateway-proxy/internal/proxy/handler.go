package proxy

import (
	"log"
	"net/http"
	"strings"

	"trinity-agi/gateway-proxy/internal/auth"
	"trinity-agi/gateway-proxy/internal/resolver"
)

// Handler is the main HTTP handler that ties authentication, resolution,
// and proxying together.
type Handler struct {
	jwtSecret []byte
	resolver  *resolver.Resolver
}

// NewHandler creates a new Handler.
func NewHandler(jwtSecret []byte, resolver *resolver.Resolver) *Handler {
	return &Handler{
		jwtSecret: jwtSecret,
		resolver:  resolver,
	}
}

// ServeHTTP implements http.Handler. It:
//  1. Extracts and validates the JWT
//  2. Gets the openclawId from query param or header
//  3. Resolves the backend for that OpenClaw instance
//  4. Routes to WebSocket or HTTP proxy
func (h *Handler) ServeHTTP(w http.ResponseWriter, r *http.Request) {
	// Extract JWT
	tokenString := auth.ExtractToken(r)
	if tokenString == "" {
		http.Error(w, `{"error":"missing authentication token"}`, http.StatusUnauthorized)
		return
	}

	// Validate JWT and extract userID for authorization
	userID, err := auth.ParseUserID(tokenString, h.jwtSecret)
	if err != nil {
		log.Printf("auth error: %v", err)
		http.Error(w, `{"error":"invalid authentication token"}`, http.StatusUnauthorized)
		return
	}

	// Get OpenClaw ID from query param or header
	openclawID := r.URL.Query().Get("openclaw")
	if openclawID == "" {
		openclawID = r.Header.Get("X-OpenClaw-Id")
	}
	if openclawID == "" {
		http.Error(w, `{"error":"missing openclaw id (use ?openclaw=<id> or X-OpenClaw-Id header)"}`, http.StatusBadRequest)
		return
	}

	// Verify user is assigned to this OpenClaw
	assigned, err := h.resolver.CheckAssignment(r.Context(), userID, openclawID)
	if err != nil {
		log.Printf("assignment check error for user %s openclaw %s: %v", userID, openclawID, err)
		http.Error(w, `{"error":"authorization check failed"}`, http.StatusInternalServerError)
		return
	}
	if !assigned {
		log.Printf("user %s not assigned to openclaw %s", userID, openclawID)
		http.Error(w, `{"error":"you are not assigned to this OpenClaw instance"}`, http.StatusForbidden)
		return
	}

	// Resolve backend by OpenClaw ID
	backend, err := h.resolver.Resolve(r.Context(), openclawID)
	if err != nil {
		log.Printf("resolve error for openclaw %s: %v", openclawID, err)
		http.Error(w, `{"error":"backend resolution failed"}`, http.StatusBadGateway)
		return
	}

	if backend == nil {
		http.Error(w, `{"error":"no backend available for this OpenClaw instance"}`, http.StatusServiceUnavailable)
		return
	}

	// Route to appropriate handler
	isWebSocket := isWebSocketUpgrade(r)
	if isWebSocket {
		HandleWebSocket(w, r, backend)
	} else {
		HandleHTTP(w, r, backend)
	}
}

// isWebSocketUpgrade checks whether the request is a WebSocket upgrade request.
func isWebSocketUpgrade(r *http.Request) bool {
	for _, v := range r.Header.Values("Connection") {
		if strings.EqualFold(strings.TrimSpace(v), "upgrade") {
			if strings.EqualFold(r.Header.Get("Upgrade"), "websocket") {
				return true
			}
		}
	}
	return false
}
