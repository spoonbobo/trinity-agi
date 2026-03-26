package adapter

import (
	"encoding/json"
	"fmt"
	"log"
	"net/http"
	"os"
	"os/exec"
	"strings"
)

// OrchestratorCompat exposes an HTTP API compatible with the legacy
// gateway-orchestrator, backed by OpenShell CLI commands.

type OrchestratorCompat struct {
	SandboxImage string
}

type Sandbox struct {
	ID        string `json:"id"`
	Name      string `json:"name"`
	Phase     string `json:"phase"`
	CreatedAt string `json:"createdAt,omitempty"`
	UserID    string `json:"userId,omitempty"`
}

func (a *OrchestratorCompat) RegisterRoutes(mux *http.ServeMux) {
	mux.HandleFunc("/openclaws", a.handleOpenClaws)
	mux.HandleFunc("/openclaws/", a.handleOpenClaws)
	mux.HandleFunc("/openclaws/fleet/health", a.handleFleetHealth)
	mux.HandleFunc("/openclaws/fleet/sessions", a.handleFleetSessions)
	mux.HandleFunc("/users/", a.handleUserOpenClaws)
}

func (a *OrchestratorCompat) handleOpenClaws(w http.ResponseWriter, r *http.Request) {
	path := strings.TrimPrefix(r.URL.Path, "/openclaws")
	path = strings.TrimPrefix(path, "/")

	w.Header().Set("Content-Type", "application/json")

	switch {
	case r.Method == "GET" && path == "":
		a.listAll(w, r)
	case r.Method == "POST" && path == "":
		a.createSandbox(w, r)
	case r.Method == "DELETE" && !strings.Contains(path, "/"):
		a.deleteSandbox(w, r, path)
	case r.Method == "GET" && strings.HasSuffix(path, "/status"):
		id := strings.TrimSuffix(path, "/status")
		a.getSandboxStatus(w, r, id)
	case r.Method == "GET" && strings.HasSuffix(path, "/resolve"):
		id := strings.TrimSuffix(path, "/resolve")
		a.resolveSandbox(w, r, id)
	case r.Method == "GET" && strings.HasSuffix(path, "/config"):
		id := strings.TrimSuffix(path, "/config")
		a.getSandboxConfig(w, r, id)
	case r.Method == "PATCH" && strings.HasSuffix(path, "/config"):
		id := strings.TrimSuffix(path, "/config")
		a.patchSandboxConfig(w, r, id)
	case r.Method == "GET" && strings.HasSuffix(path, "/delegation-token"):
		id := strings.TrimSuffix(path, "/delegation-token")
		a.getDelegationToken(w, r, id)
	case r.Method == "POST" && strings.HasSuffix(path, "/assign"):
		id := strings.TrimSuffix(path, "/assign")
		a.assignSandbox(w, r, id)
	case strings.Contains(path, "/assign/") && r.Method == "DELETE":
		parts := strings.SplitN(path, "/assign/", 2)
		a.unassignSandbox(w, r, parts[0], parts[1])
	case r.Method == "GET" && strings.HasSuffix(path, "/assignments"):
		id := strings.TrimSuffix(path, "/assignments")
		a.listAssignments(w, r, id)
	case r.Method == "GET" && !strings.Contains(path, "/"):
		a.getSandbox(w, r, path)
	default:
		http.NotFound(w, r)
	}
}

func (a *OrchestratorCompat) listAll(w http.ResponseWriter, _ *http.Request) {
	sandboxes, err := a.listSandboxes("")
	if err != nil {
		http.Error(w, err.Error(), http.StatusInternalServerError)
		return
	}
	json.NewEncoder(w).Encode(sandboxes)
}

func (a *OrchestratorCompat) createSandbox(w http.ResponseWriter, r *http.Request) {
	var body struct {
		Name        string `json:"name"`
		Description string `json:"description"`
		CreatedBy   string `json:"createdBy"`
	}
	if err := json.NewDecoder(r.Body).Decode(&body); err != nil {
		http.Error(w, "invalid body", http.StatusBadRequest)
		return
	}

	sandboxName := fmt.Sprintf("openclaw-%s", sanitizeName(body.Name))
	image := a.SandboxImage
	if image == "" {
		image = "openclaw"
	}

	cmd := exec.Command("openshell", "sandbox", "create",
		"--name", sandboxName,
		"--from", image,
		"--forward", "18789",
	)
	out, err := cmd.CombinedOutput()
	if err != nil {
		log.Printf("[compat] sandbox create failed: %s\n%s", err, out)
		http.Error(w, "sandbox creation failed", http.StatusInternalServerError)
		return
	}

	w.WriteHeader(http.StatusCreated)
	json.NewEncoder(w).Encode(map[string]string{
		"id":   sandboxName,
		"name": sandboxName,
	})
}

func (a *OrchestratorCompat) deleteSandbox(w http.ResponseWriter, _ *http.Request, id string) {
	cmd := exec.Command("openshell", "sandbox", "delete", id)
	out, err := cmd.CombinedOutput()
	if err != nil {
		log.Printf("[compat] sandbox delete failed: %s\n%s", err, out)
		http.Error(w, "sandbox deletion failed", http.StatusInternalServerError)
		return
	}
	w.WriteHeader(http.StatusNoContent)
}

func (a *OrchestratorCompat) getSandbox(w http.ResponseWriter, _ *http.Request, id string) {
	sandboxes, err := a.listSandboxes("")
	if err != nil {
		http.Error(w, err.Error(), http.StatusInternalServerError)
		return
	}
	for _, sb := range sandboxes {
		if sb.Name == id || sb.ID == id {
			json.NewEncoder(w).Encode(sb)
			return
		}
	}
	http.NotFound(w, nil)
}

func (a *OrchestratorCompat) getSandboxStatus(w http.ResponseWriter, _ *http.Request, id string) {
	sandboxes, err := a.listSandboxes("")
	if err != nil {
		http.Error(w, err.Error(), http.StatusInternalServerError)
		return
	}
	for _, sb := range sandboxes {
		if sb.Name == id || sb.ID == id {
			json.NewEncoder(w).Encode(map[string]interface{}{
				"id":    sb.ID,
				"phase": sb.Phase,
				"ready": sb.Phase == "Ready",
			})
			return
		}
	}
	http.NotFound(w, nil)
}

func (a *OrchestratorCompat) resolveSandbox(w http.ResponseWriter, _ *http.Request, id string) {
	pattern := os.Getenv("SANDBOX_ENDPOINT_PATTERN")
	if pattern == "" {
		pattern = "http://sandbox-{name}.openshell.svc.cluster.local:18789"
	}
	endpoint := strings.ReplaceAll(pattern, "{name}", id)
	json.NewEncoder(w).Encode(map[string]string{
		"id":       id,
		"endpoint": endpoint,
	})
}

func (a *OrchestratorCompat) getSandboxConfig(w http.ResponseWriter, _ *http.Request, id string) {
	json.NewEncoder(w).Encode(map[string]interface{}{
		"id":     id,
		"config": map[string]interface{}{},
	})
}

func (a *OrchestratorCompat) patchSandboxConfig(w http.ResponseWriter, _ *http.Request, id string) {
	json.NewEncoder(w).Encode(map[string]interface{}{
		"id":      id,
		"updated": true,
	})
}

func (a *OrchestratorCompat) getDelegationToken(w http.ResponseWriter, _ *http.Request, id string) {
	json.NewEncoder(w).Encode(map[string]string{
		"id":    id,
		"token": "",
	})
}

func (a *OrchestratorCompat) assignSandbox(w http.ResponseWriter, r *http.Request, id string) {
	var body struct {
		UserID     string `json:"userId"`
		AssignedBy string `json:"assignedBy"`
	}
	json.NewDecoder(r.Body).Decode(&body)
	json.NewEncoder(w).Encode(map[string]string{
		"id":     id,
		"userId": body.UserID,
		"status": "assigned",
	})
}

func (a *OrchestratorCompat) unassignSandbox(w http.ResponseWriter, _ *http.Request, id, userID string) {
	json.NewEncoder(w).Encode(map[string]string{
		"id":     id,
		"userId": userID,
		"status": "unassigned",
	})
}

func (a *OrchestratorCompat) listAssignments(w http.ResponseWriter, _ *http.Request, id string) {
	json.NewEncoder(w).Encode([]interface{}{})
}

func (a *OrchestratorCompat) handleUserOpenClaws(w http.ResponseWriter, r *http.Request) {
	w.Header().Set("Content-Type", "application/json")
	parts := strings.Split(strings.Trim(r.URL.Path, "/"), "/")
	if len(parts) < 3 || parts[0] != "users" || parts[2] != "openclaws" {
		http.NotFound(w, r)
		return
	}
	userID := parts[1]
	sandboxes, err := a.listSandboxes(userID)
	if err != nil {
		http.Error(w, err.Error(), http.StatusInternalServerError)
		return
	}
	json.NewEncoder(w).Encode(sandboxes)
}

func (a *OrchestratorCompat) handleFleetHealth(w http.ResponseWriter, _ *http.Request) {
	w.Header().Set("Content-Type", "application/json")
	sandboxes, err := a.listSandboxes("")
	if err != nil {
		http.Error(w, err.Error(), http.StatusInternalServerError)
		return
	}
	total := len(sandboxes)
	ready := 0
	for _, sb := range sandboxes {
		if sb.Phase == "Ready" {
			ready++
		}
	}
	json.NewEncoder(w).Encode(map[string]int{"total": total, "ready": ready})
}

func (a *OrchestratorCompat) handleFleetSessions(w http.ResponseWriter, _ *http.Request) {
	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode([]interface{}{})
}

func (a *OrchestratorCompat) listSandboxes(userFilter string) ([]Sandbox, error) {
	out, err := exec.Command("openshell", "sandbox", "list", "--json").Output()
	if err != nil {
		return []Sandbox{}, nil
	}

	trimmed := strings.TrimSpace(string(out))
	if trimmed == "" || trimmed == "[]" {
		return []Sandbox{}, nil
	}

	var raw []struct {
		Name      string            `json:"name"`
		Namespace string            `json:"namespace"`
		Phase     string            `json:"phase"`
		Created   string            `json:"created"`
		Labels    map[string]string `json:"labels"`
	}
	if err := json.Unmarshal([]byte(trimmed), &raw); err != nil {
		log.Printf("[compat] Failed to parse sandbox JSON: %v (raw: %s)", err, trimmed[:min(len(trimmed), 200)])
		return []Sandbox{}, nil
	}

	var sandboxes []Sandbox
	for _, r := range raw {
		sb := Sandbox{
			ID:        r.Name,
			Name:      r.Name,
			Phase:     r.Phase,
			CreatedAt: r.Created,
			UserID:    r.Labels["trinity.work/user-id"],
		}
		if userFilter == "" || sb.UserID == userFilter || strings.Contains(sb.Name, safePrefix(userFilter, 8)) {
			sandboxes = append(sandboxes, sb)
		}
	}
	return sandboxes, nil
}

func safePrefix(s string, n int) string {
	if len(s) <= n {
		return s
	}
	return s[:n]
}

func sanitizeName(name string) string {
	name = strings.ToLower(name)
	name = strings.ReplaceAll(name, " ", "-")
	if len(name) > 40 {
		name = name[:40]
	}
	return name
}

func min(a, b int) int {
	if a < b {
		return a
	}
	return b
}
