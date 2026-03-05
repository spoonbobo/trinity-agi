package api

import (
	"context"
	"encoding/json"
	"fmt"
	"log"
	"net/http"
	"regexp"

	"github.com/gorilla/mux"

	"trinity-agi/gateway-orchestrator/internal/db"
	k8sclient "trinity-agi/gateway-orchestrator/internal/k8s"
	"trinity-agi/gateway-orchestrator/internal/token"
)

// Handler holds dependencies for HTTP handlers.
type Handler struct {
	store        *db.Store
	k8s          *k8sclient.Client
	namespace    string
	openclawImg  string
	storageClass string
}

// NewRouter creates a configured mux.Router with all routes and middleware.
func NewRouter(store *db.Store, k8s *k8sclient.Client, serviceToken, namespace, openclawImg, storageClass string) *mux.Router {
	h := &Handler{
		store:        store,
		k8s:          k8s,
		namespace:    namespace,
		openclawImg:  openclawImg,
		storageClass: storageClass,
	}

	r := mux.NewRouter()
	r.Use(authMiddleware(serviceToken))

	// Health
	r.HandleFunc("/health", h.handleHealth).Methods(http.MethodGet)

	// OpenClaw instance CRUD (admin)
	r.HandleFunc("/openclaws", h.handleCreateOpenClaw).Methods(http.MethodPost)
	r.HandleFunc("/openclaws", h.handleListOpenClaws).Methods(http.MethodGet)
	r.HandleFunc("/openclaws/{id}", h.handleGetOpenClaw).Methods(http.MethodGet)
	r.HandleFunc("/openclaws/{id}", h.handleDeleteOpenClaw).Methods(http.MethodDelete)
	r.HandleFunc("/openclaws/{id}/status", h.handleOpenClawStatus).Methods(http.MethodGet)
	r.HandleFunc("/openclaws/{id}/resolve", h.handleResolveOpenClaw).Methods(http.MethodGet)

	// User assignment management (admin)
	r.HandleFunc("/openclaws/{id}/assign", h.handleAssignUser).Methods(http.MethodPost)
	r.HandleFunc("/openclaws/{id}/assign/{userId}", h.handleUnassignUser).Methods(http.MethodDelete)
	r.HandleFunc("/openclaws/{id}/assignments", h.handleListAssignments).Methods(http.MethodGet)

	// User-facing: list my OpenClaws
	r.HandleFunc("/users/{userId}/openclaws", h.handleUserOpenClaws).Methods(http.MethodGet)

	return r
}

// --- request/response types ---

type createOpenClawRequest struct {
	Name        string `json:"name"`
	Description string `json:"description"`
	CreatedBy   string `json:"createdBy"`
}

type openClawResponse struct {
	ID          string `json:"id"`
	Name        string `json:"name"`
	Description string `json:"description,omitempty"`
	ServiceName string `json:"serviceName,omitempty"`
	Status      string `json:"status"`
}

type statusResponse struct {
	ID        string `json:"id"`
	Name      string `json:"name"`
	Status    string `json:"status"`
	Ready     bool   `json:"ready"`
	PodStatus string `json:"podStatus,omitempty"`
	Error     string `json:"error,omitempty"`
}

type resolveResponse struct {
	Host    string `json:"host"`
	Port    int    `json:"port"`
	Token   string `json:"token"`
	PodName string `json:"podName"`
}

type assignRequest struct {
	UserID     string `json:"userId"`
	AssignedBy string `json:"assignedBy"`
}

type errorResponse struct {
	Error string `json:"error"`
}

// --- handlers ---

func (h *Handler) handleHealth(w http.ResponseWriter, _ *http.Request) {
	writeJSON(w, http.StatusOK, map[string]bool{"ok": true})
}

// ── OpenClaw CRUD ───────────────────────────────────────────────────────

func (h *Handler) handleCreateOpenClaw(w http.ResponseWriter, r *http.Request) {
	var req createOpenClawRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		writeJSON(w, http.StatusBadRequest, errorResponse{Error: "invalid request body"})
		return
	}
	if req.Name == "" {
		writeJSON(w, http.StatusBadRequest, errorResponse{Error: "name is required"})
		return
	}

	// Validate name is a valid Kubernetes resource name component:
	// lowercase, alphanumeric + hyphens, 1-50 chars, start/end alphanumeric.
	if err := validateName(req.Name); err != nil {
		writeJSON(w, http.StatusBadRequest, errorResponse{Error: err.Error()})
		return
	}

	ctx := r.Context()

	// Check if name already taken
	existing, err := h.store.GetOpenClawByName(ctx, req.Name)
	if err != nil {
		log.Printf("ERROR create: lookup name %s: %v", req.Name, err)
		writeJSON(w, http.StatusInternalServerError, errorResponse{Error: "failed to check existing instance"})
		return
	}
	if existing != nil {
		writeJSON(w, http.StatusConflict, errorResponse{Error: "an OpenClaw with this name already exists"})
		return
	}

	// Generate gateway token
	gwToken, err := token.GenerateToken()
	if err != nil {
		log.Printf("ERROR create: generate token: %v", err)
		writeJSON(w, http.StatusInternalServerError, errorResponse{Error: "failed to generate token"})
		return
	}

	// Create DB record
	oc, err := h.store.CreateOpenClaw(ctx, req.Name, req.Description, gwToken, h.namespace, req.CreatedBy)
	if err != nil {
		log.Printf("ERROR create: insert %s: %v", req.Name, err)
		writeJSON(w, http.StatusInternalServerError, errorResponse{Error: "failed to create record"})
		return
	}

	// Create K8s resources: Secret -> ConfigMap -> PVC -> Service -> Deployment
	resName := k8sclient.ResourceName(req.Name)

	if err := h.k8s.CreateOpenClawSecret(ctx, oc, resName); err != nil {
		h.markError(ctx, oc, "failed to create secret", err)
		writeJSON(w, http.StatusInternalServerError, errorResponse{Error: "failed to create secret"})
		return
	}
	if err := h.k8s.CreateOpenClawConfigMap(ctx, oc, resName); err != nil {
		h.markError(ctx, oc, "failed to create configmap", err)
		writeJSON(w, http.StatusInternalServerError, errorResponse{Error: "failed to create configmap"})
		return
	}
	if err := h.k8s.CreateOpenClawPVC(ctx, oc, resName, h.storageClass); err != nil {
		h.markError(ctx, oc, "failed to create pvc", err)
		writeJSON(w, http.StatusInternalServerError, errorResponse{Error: "failed to create pvc"})
		return
	}
	if err := h.k8s.CreateOpenClawService(ctx, oc, resName); err != nil {
		h.markError(ctx, oc, "failed to create service", err)
		writeJSON(w, http.StatusInternalServerError, errorResponse{Error: "failed to create service"})
		return
	}
	if err := h.k8s.CreateOpenClawDeployment(ctx, oc, resName, h.openclawImg, h.storageClass); err != nil {
		h.markError(ctx, oc, "failed to create deployment", err)
		writeJSON(w, http.StatusInternalServerError, errorResponse{Error: "failed to create deployment"})
		return
	}

	// Update DB with resource names -- status stays "provisioning" until
	// the pod is actually ready (status endpoint checks live pod readiness).
	if err := h.store.UpdateOpenClawStatus(ctx, oc.ID, "provisioning", resName, resName, resName, ""); err != nil {
		log.Printf("ERROR create: update status %s: %v", oc.ID, err)
		writeJSON(w, http.StatusInternalServerError, errorResponse{Error: "resources created but failed to update status"})
		return
	}

	writeJSON(w, http.StatusCreated, openClawResponse{
		ID:          oc.ID,
		Name:        oc.Name,
		Description: oc.Description,
		ServiceName: resName,
		Status:      "provisioning",
	})
}

func (h *Handler) handleListOpenClaws(w http.ResponseWriter, r *http.Request) {
	list, err := h.store.ListOpenClaws(r.Context())
	if err != nil {
		log.Printf("ERROR list: %v", err)
		writeJSON(w, http.StatusInternalServerError, errorResponse{Error: "failed to list openclaws"})
		return
	}
	if list == nil {
		list = []db.OpenClaw{}
	}
	writeJSON(w, http.StatusOK, list)
}

func (h *Handler) handleGetOpenClaw(w http.ResponseWriter, r *http.Request) {
	id := mux.Vars(r)["id"]
	oc, err := h.store.GetOpenClawByID(r.Context(), id)
	if err != nil {
		log.Printf("ERROR get: %v", err)
		writeJSON(w, http.StatusInternalServerError, errorResponse{Error: "failed to get openclaw"})
		return
	}
	if oc == nil {
		writeJSON(w, http.StatusNotFound, errorResponse{Error: "openclaw not found"})
		return
	}
	writeJSON(w, http.StatusOK, oc)
}

func (h *Handler) handleDeleteOpenClaw(w http.ResponseWriter, r *http.Request) {
	id := mux.Vars(r)["id"]
	ctx := r.Context()

	oc, err := h.store.GetOpenClawByID(ctx, id)
	if err != nil {
		log.Printf("ERROR delete: lookup %s: %v", id, err)
		writeJSON(w, http.StatusInternalServerError, errorResponse{Error: "failed to look up openclaw"})
		return
	}
	if oc == nil {
		writeJSON(w, http.StatusNotFound, errorResponse{Error: "openclaw not found"})
		return
	}

	// Delete K8s resources
	resName := k8sclient.ResourceName(oc.Name)
	if err := h.k8s.DeleteOpenClawResources(ctx, oc, resName); err != nil {
		log.Printf("ERROR delete: k8s resources for %s: %v", id, err)
		writeJSON(w, http.StatusInternalServerError, errorResponse{Error: "failed to delete kubernetes resources"})
		return
	}

	// Delete DB record (cascade deletes assignments)
	if err := h.store.DeleteOpenClaw(ctx, id); err != nil {
		log.Printf("ERROR delete: db record %s: %v", id, err)
		writeJSON(w, http.StatusInternalServerError, errorResponse{Error: "k8s deleted but failed to remove db record"})
		return
	}

	writeJSON(w, http.StatusOK, map[string]string{"status": "deleted", "id": id})
}

func (h *Handler) handleOpenClawStatus(w http.ResponseWriter, r *http.Request) {
	id := mux.Vars(r)["id"]
	ctx := r.Context()

	oc, err := h.store.GetOpenClawByID(ctx, id)
	if err != nil {
		log.Printf("ERROR status: %v", err)
		writeJSON(w, http.StatusInternalServerError, errorResponse{Error: "failed to look up openclaw"})
		return
	}
	if oc == nil {
		writeJSON(w, http.StatusNotFound, errorResponse{Error: "openclaw not found"})
		return
	}

	resp := statusResponse{
		ID:     oc.ID,
		Name:   oc.Name,
		Status: oc.Status,
		Error:  oc.ErrorMessage,
	}

	if oc.Status == "running" || oc.Status == "provisioning" {
		podStatus, err := h.k8s.GetOpenClawPodStatus(ctx, oc)
		if err != nil {
			log.Printf("WARN status: pod status for %s: %v", id, err)
			resp.PodStatus = "unknown"
		} else {
			resp.PodStatus = podStatus
			resp.Ready = podStatus == "Running/ready"
			// Auto-transition provisioning -> running when pod is ready
			if oc.Status == "provisioning" && resp.Ready {
				if uerr := h.store.UpdateOpenClawStatus(
					ctx, oc.ID, "running", oc.PodName, oc.ServiceName, oc.PVCName, "",
				); uerr != nil {
					log.Printf("WARN status: failed to transition %s to running: %v", id, uerr)
				} else {
					resp.Status = "running"
				}
			}
		}
	}

	writeJSON(w, http.StatusOK, resp)
}

func (h *Handler) handleResolveOpenClaw(w http.ResponseWriter, r *http.Request) {
	id := mux.Vars(r)["id"]
	ctx := r.Context()

	oc, err := h.store.GetOpenClawByID(ctx, id)
	if err != nil {
		log.Printf("ERROR resolve: %v", err)
		writeJSON(w, http.StatusInternalServerError, errorResponse{Error: "failed to look up openclaw"})
		return
	}
	if oc == nil {
		writeJSON(w, http.StatusNotFound, errorResponse{Error: "openclaw not found"})
		return
	}
	if oc.Status != "running" {
		writeJSON(w, http.StatusServiceUnavailable, errorResponse{Error: "openclaw is not running (status: " + oc.Status + ")"})
		return
	}

	writeJSON(w, http.StatusOK, resolveResponse{
		Host:    oc.ServiceName,
		Port:    oc.Port,
		Token:   oc.GatewayToken,
		PodName: "deployment/" + oc.PodName,
	})
}

// ── Assignments ─────────────────────────────────────────────────────────

func (h *Handler) handleAssignUser(w http.ResponseWriter, r *http.Request) {
	openclawID := mux.Vars(r)["id"]
	var req assignRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		writeJSON(w, http.StatusBadRequest, errorResponse{Error: "invalid request body"})
		return
	}
	if req.UserID == "" {
		writeJSON(w, http.StatusBadRequest, errorResponse{Error: "userId is required"})
		return
	}

	ctx := r.Context()

	// Verify OpenClaw exists
	oc, err := h.store.GetOpenClawByID(ctx, openclawID)
	if err != nil || oc == nil {
		writeJSON(w, http.StatusNotFound, errorResponse{Error: "openclaw not found"})
		return
	}

	if err := h.store.AssignUser(ctx, req.UserID, openclawID, req.AssignedBy); err != nil {
		log.Printf("ERROR assign: %v", err)
		writeJSON(w, http.StatusInternalServerError, errorResponse{Error: "failed to assign user"})
		return
	}

	writeJSON(w, http.StatusOK, map[string]string{"status": "assigned", "userId": req.UserID, "openclawId": openclawID})
}

func (h *Handler) handleUnassignUser(w http.ResponseWriter, r *http.Request) {
	vars := mux.Vars(r)
	openclawID := vars["id"]
	userID := vars["userId"]

	if err := h.store.UnassignUser(r.Context(), userID, openclawID); err != nil {
		log.Printf("ERROR unassign: %v", err)
		writeJSON(w, http.StatusInternalServerError, errorResponse{Error: "failed to unassign user"})
		return
	}

	writeJSON(w, http.StatusOK, map[string]string{"status": "unassigned", "userId": userID, "openclawId": openclawID})
}

func (h *Handler) handleListAssignments(w http.ResponseWriter, r *http.Request) {
	openclawID := mux.Vars(r)["id"]
	list, err := h.store.GetOpenClawAssignments(r.Context(), openclawID)
	if err != nil {
		log.Printf("ERROR assignments: %v", err)
		writeJSON(w, http.StatusInternalServerError, errorResponse{Error: "failed to list assignments"})
		return
	}
	if list == nil {
		list = []db.Assignment{}
	}
	writeJSON(w, http.StatusOK, list)
}

// ── User-facing ─────────────────────────────────────────────────────────

func (h *Handler) handleUserOpenClaws(w http.ResponseWriter, r *http.Request) {
	userID := mux.Vars(r)["userId"]
	list, err := h.store.GetUserOpenClaws(r.Context(), userID)
	if err != nil {
		log.Printf("ERROR user openclaws: %v", err)
		writeJSON(w, http.StatusInternalServerError, errorResponse{Error: "failed to list user openclaws"})
		return
	}
	if list == nil {
		list = []db.UserOpenClaw{}
	}
	writeJSON(w, http.StatusOK, list)
}

// --- helpers ---

func (h *Handler) markError(ctx context.Context, oc *db.OpenClaw, msg string, err error) {
	log.Printf("ERROR create: %s for %s: %v", msg, oc.Name, err)
	if uerr := h.store.UpdateOpenClawStatus(
		ctx, oc.ID, "error", "", "", "", msg+": "+err.Error(),
	); uerr != nil {
		log.Printf("ERROR: additionally failed to update error status for %s: %v", oc.Name, uerr)
	}
}

// validateName checks that a name is valid for use as a Kubernetes resource.
// Rules: lowercase, alphanumeric + hyphens, 1-50 chars, must start and end
// with an alphanumeric character. The final k8s resource will be "openclaw-<name>".
var validNameRe = regexp.MustCompile(`^[a-z0-9][a-z0-9-]{0,48}[a-z0-9]$`)

func validateName(name string) error {
	if len(name) < 2 {
		return fmt.Errorf("name must be at least 2 characters")
	}
	if len(name) > 50 {
		return fmt.Errorf("name must be at most 50 characters")
	}
	if !validNameRe.MatchString(name) {
		return fmt.Errorf("name must be lowercase, alphanumeric and hyphens only, and start/end with a letter or number (e.g. 'dev-team', 'prod-01')")
	}
	return nil
}

func writeJSON(w http.ResponseWriter, status int, v interface{}) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(status)
	if err := json.NewEncoder(w).Encode(v); err != nil {
		log.Printf("ERROR: failed to encode JSON response: %v", err)
	}
}
