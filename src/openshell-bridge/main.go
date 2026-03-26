package main

import (
	"encoding/json"
	"fmt"
	"io"
	"log"
	"net/http"
	"os"
	"os/exec"
	"strings"
	"sync"
	"time"

	"github.com/golang-jwt/jwt/v5"
	"github.com/gorilla/websocket"
	"github.com/spoonbobo/trinity/openshell-bridge/adapter"
)

type SandboxInfo struct {
	Name      string
	Namespace string
	Phase     string
}

type SandboxResolver struct {
	mu    sync.RWMutex
	cache map[string]*SandboxInfo
	ttl   time.Duration
	times map[string]time.Time
}

func NewSandboxResolver(ttl time.Duration) *SandboxResolver {
	return &SandboxResolver{
		cache: make(map[string]*SandboxInfo),
		ttl:   ttl,
		times: make(map[string]time.Time),
	}
}

func (r *SandboxResolver) Resolve(userID string) (*SandboxInfo, error) {
	r.mu.RLock()
	if info, ok := r.cache[userID]; ok {
		if time.Since(r.times[userID]) < r.ttl {
			r.mu.RUnlock()
			return info, nil
		}
	}
	r.mu.RUnlock()

	info, err := r.lookupSandbox(userID)
	if err != nil {
		return nil, err
	}

	r.mu.Lock()
	r.cache[userID] = info
	r.times[userID] = time.Now()
	r.mu.Unlock()

	return info, nil
}

func (r *SandboxResolver) lookupSandbox(userID string) (*SandboxInfo, error) {
	out, err := exec.Command("openshell", "sandbox", "list", "--json").Output()
	if err != nil {
		return nil, fmt.Errorf("failed to list sandboxes: %w", err)
	}

	var sandboxes []struct {
		Name      string            `json:"name"`
		Namespace string            `json:"namespace"`
		Phase     string            `json:"phase"`
		Labels    map[string]string `json:"labels"`
	}
	if err := json.Unmarshal(out, &sandboxes); err != nil {
		return nil, fmt.Errorf("failed to parse sandbox list: %w", err)
	}

	for _, sb := range sandboxes {
		if sb.Labels["trinity.work/user-id"] == userID && sb.Phase == "Ready" {
			return &SandboxInfo{
				Name:      sb.Name,
				Namespace: sb.Namespace,
				Phase:     sb.Phase,
			}, nil
		}
	}

	return nil, fmt.Errorf("no ready sandbox found for user %s", userID)
}

func (r *SandboxResolver) Invalidate(userID string) {
	r.mu.Lock()
	delete(r.cache, userID)
	delete(r.times, userID)
	r.mu.Unlock()
}

func sandboxEndpoint(sandboxName, path string) string {
	pattern := os.Getenv("SANDBOX_ENDPOINT_PATTERN")
	if pattern == "" {
		pattern = "http://sandbox-{name}.openshell.svc.cluster.local:18789"
	}
	base := strings.ReplaceAll(pattern, "{name}", sandboxName)
	return base + path
}

var upgrader = websocket.Upgrader{
	CheckOrigin: func(r *http.Request) bool {
		origin := r.Header.Get("Origin")
		allowed := os.Getenv("ALLOWED_ORIGINS")
		if allowed == "" {
			allowed = "http://localhost"
		}
		for _, o := range strings.Split(allowed, ",") {
			if strings.TrimSpace(o) == origin {
				return true
			}
		}
		return false
	},
}

func extractUserFromJWT(tokenStr, jwtSecret string) (string, error) {
	token, err := jwt.Parse(tokenStr, func(token *jwt.Token) (interface{}, error) {
		if _, ok := token.Method.(*jwt.SigningMethodHMAC); !ok {
			return nil, fmt.Errorf("unexpected signing method: %v", token.Header["alg"])
		}
		return []byte(jwtSecret), nil
	})
	if err != nil {
		return "", err
	}

	claims, ok := token.Claims.(jwt.MapClaims)
	if !ok || !token.Valid {
		return "", fmt.Errorf("invalid token claims")
	}

	sub, ok := claims["sub"].(string)
	if !ok {
		return "", fmt.Errorf("missing sub claim")
	}
	return sub, nil
}

func proxyWebSocket(clientConn *websocket.Conn, sandboxName string, path string) {
	targetURL := strings.Replace(sandboxEndpoint(sandboxName, path), "http://", "ws://", 1)
	targetURL = strings.Replace(targetURL, "https://", "wss://", 1)

	backendConn, _, err := websocket.DefaultDialer.Dial(targetURL, nil)
	if err != nil {
		log.Printf("[bridge] Failed to connect to sandbox %s at %s: %v", sandboxName, targetURL, err)
		clientConn.WriteMessage(websocket.CloseMessage,
			websocket.FormatCloseMessage(websocket.CloseInternalServerErr, "sandbox unavailable"))
		return
	}
	defer backendConn.Close()

	done := make(chan struct{})

	go func() {
		defer close(done)
		for {
			msgType, msg, err := backendConn.ReadMessage()
			if err != nil {
				return
			}
			if err := clientConn.WriteMessage(msgType, msg); err != nil {
				return
			}
		}
	}()

	for {
		msgType, msg, err := clientConn.ReadMessage()
		if err != nil {
			break
		}
		if err := backendConn.WriteMessage(msgType, msg); err != nil {
			break
		}
	}

	<-done
}

func handleWS(resolver *SandboxResolver, jwtSecret string, w http.ResponseWriter, r *http.Request) {
	token := r.URL.Query().Get("token")
	if token == "" {
		authHeader := r.Header.Get("Authorization")
		if strings.HasPrefix(authHeader, "Bearer ") {
			token = strings.TrimPrefix(authHeader, "Bearer ")
		}
	}

	if token == "" {
		http.Error(w, "missing authentication token", http.StatusUnauthorized)
		return
	}

	userID, err := extractUserFromJWT(token, jwtSecret)
	if err != nil {
		http.Error(w, "invalid token", http.StatusUnauthorized)
		return
	}

	sandbox, err := resolver.Resolve(userID)
	if err != nil {
		http.Error(w, fmt.Sprintf("no sandbox for user: %v", err), http.StatusServiceUnavailable)
		return
	}

	clientConn, err := upgrader.Upgrade(w, r, nil)
	if err != nil {
		log.Printf("[bridge] WebSocket upgrade failed: %v", err)
		return
	}
	defer clientConn.Close()

	log.Printf("[bridge] User %s -> sandbox %s (%s)", userID, sandbox.Name, r.URL.Path)
	proxyWebSocket(clientConn, sandbox.Name, r.URL.Path)
}

func handleHTTPProxy(resolver *SandboxResolver, jwtSecret string, w http.ResponseWriter, r *http.Request) {
	token := r.Header.Get("Authorization")
	if strings.HasPrefix(token, "Bearer ") {
		token = strings.TrimPrefix(token, "Bearer ")
	}
	if token == "" {
		token = r.URL.Query().Get("token")
	}

	if token == "" {
		http.Error(w, "missing authentication token", http.StatusUnauthorized)
		return
	}

	userID, err := extractUserFromJWT(token, jwtSecret)
	if err != nil {
		http.Error(w, "invalid token", http.StatusUnauthorized)
		return
	}

	sandbox, err := resolver.Resolve(userID)
	if err != nil {
		http.Error(w, fmt.Sprintf("no sandbox: %v", err), http.StatusServiceUnavailable)
		return
	}

	targetURL := sandboxEndpoint(sandbox.Name, r.URL.Path)
	if r.URL.RawQuery != "" {
		targetURL += "?" + r.URL.RawQuery
	}

	proxyReq, err := http.NewRequestWithContext(r.Context(), r.Method, targetURL, r.Body)
	if err != nil {
		http.Error(w, "failed to create proxy request", http.StatusInternalServerError)
		return
	}

	for k, vv := range r.Header {
		for _, v := range vv {
			proxyReq.Header.Add(k, v)
		}
	}

	resp, err := http.DefaultClient.Do(proxyReq)
	if err != nil {
		http.Error(w, "sandbox request failed", http.StatusBadGateway)
		return
	}
	defer resp.Body.Close()

	for k, vv := range resp.Header {
		for _, v := range vv {
			w.Header().Add(k, v)
		}
	}
	w.WriteHeader(resp.StatusCode)
	io.Copy(w, resp.Body)
}

func main() {
	port := os.Getenv("BRIDGE_PORT")
	if port == "" {
		port = "18800"
	}

	jwtSecret := os.Getenv("JWT_SECRET")
	if jwtSecret == "" {
		log.Fatal("[bridge] JWT_SECRET is required")
	}

	resolver := NewSandboxResolver(30 * time.Second)

	mux := http.NewServeMux()

	mux.HandleFunc("/ws", func(w http.ResponseWriter, r *http.Request) {
		handleWS(resolver, jwtSecret, w, r)
	})

	mux.HandleFunc("/terminal/", func(w http.ResponseWriter, r *http.Request) {
		handleWS(resolver, jwtSecret, w, r)
	})

	mux.HandleFunc("/__openclaw__/", func(w http.ResponseWriter, r *http.Request) {
		if websocket.IsWebSocketUpgrade(r) {
			handleWS(resolver, jwtSecret, w, r)
		} else {
			handleHTTPProxy(resolver, jwtSecret, w, r)
		}
	})

	mux.HandleFunc("/v1/", func(w http.ResponseWriter, r *http.Request) {
		handleHTTPProxy(resolver, jwtSecret, w, r)
	})

	mux.HandleFunc("/tools/", func(w http.ResponseWriter, r *http.Request) {
		handleHTTPProxy(resolver, jwtSecret, w, r)
	})

	mux.HandleFunc("/health", func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		w.Write([]byte(`{"status":"ok"}`))
	})

	orchCompat := &adapter.OrchestratorCompat{
		SandboxImage: os.Getenv("OPENSHELL_SANDBOX_IMAGE"),
	}
	orchCompat.RegisterRoutes(mux)

	log.Printf("[bridge] OpenShell bridge listening on :%s", port)
	log.Printf("[bridge] Sandbox endpoint pattern: %s", sandboxEndpoint("<name>", ""))
	log.Fatal(http.ListenAndServe(":"+port, mux))
}
