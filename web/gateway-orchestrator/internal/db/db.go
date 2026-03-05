package db

import (
	"context"
	"database/sql"
	"fmt"
	"time"
)

// OpenClaw represents an admin-managed OpenClaw instance (rbac.openclaws).
type OpenClaw struct {
	ID           string     `json:"id"`
	Name         string     `json:"name"`
	Description  string     `json:"description,omitempty"`
	GatewayToken string     `json:"gateway_token,omitempty"`
	PodName      string     `json:"pod_name,omitempty"`
	ServiceName  string     `json:"service_name,omitempty"`
	PVCName      string     `json:"pvc_name,omitempty"`
	Namespace    string     `json:"namespace"`
	Status       string     `json:"status"`
	ErrorMessage string     `json:"error_message,omitempty"`
	Port         int        `json:"port"`
	CreatedBy    string     `json:"created_by,omitempty"`
	CreatedAt    time.Time  `json:"created_at"`
	UpdatedAt    *time.Time `json:"updated_at,omitempty"`
	UserCount    int        `json:"user_count"`
}

// Assignment represents a user-to-OpenClaw assignment (rbac.openclaw_assignments).
type Assignment struct {
	ID         string    `json:"id"`
	UserID     string    `json:"user_id"`
	OpenClawID string    `json:"openclaw_id"`
	AssignedBy string    `json:"assigned_by,omitempty"`
	AssignedAt time.Time `json:"assigned_at"`
}

// UserOpenClaw is a joined view of an OpenClaw with assignment info for a user.
type UserOpenClaw struct {
	ID          string `json:"id"`
	Name        string `json:"name"`
	Description string `json:"description,omitempty"`
	Status      string `json:"status"`
	Port        int    `json:"port"`
	UserCount   int    `json:"userCount"`
}

// Store wraps the database connection pool and provides OpenClaw operations.
type Store struct {
	db *sql.DB
}

// NewStore creates a new Store from a database connection pool.
func NewStore(db *sql.DB) *Store {
	return &Store{db: db}
}

// ── OpenClaw CRUD ───────────────────────────────────────────────────────

const openclawColumns = `id, name, COALESCE(description, ''), gateway_token,
	COALESCE(pod_name, ''), COALESCE(service_name, ''), COALESCE(pvc_name, ''),
	namespace, status, COALESCE(error_message, ''),
	port, COALESCE(created_by::TEXT, ''), created_at, updated_at`

func scanOpenClaw(row interface{ Scan(...interface{}) error }) (*OpenClaw, error) {
	var o OpenClaw
	err := row.Scan(
		&o.ID, &o.Name, &o.Description, &o.GatewayToken,
		&o.PodName, &o.ServiceName, &o.PVCName,
		&o.Namespace, &o.Status, &o.ErrorMessage,
		&o.Port, &o.CreatedBy, &o.CreatedAt, &o.UpdatedAt,
	)
	return &o, err
}

// CreateOpenClaw inserts a new OpenClaw instance and returns it.
func (s *Store) CreateOpenClaw(ctx context.Context, name, description, token, namespace, createdBy string) (*OpenClaw, error) {
	// Use NULLIF to convert empty string to NULL for UUID column
	row := s.db.QueryRowContext(ctx,
		`INSERT INTO rbac.openclaws (name, description, gateway_token, namespace, status, port, created_by)
		 VALUES ($1, $2, $3, $4, 'provisioning', 18789, NULLIF($5, '')::UUID)
		 RETURNING `+openclawColumns,
		name, description, token, namespace, createdBy,
	)
	o, err := scanOpenClaw(row)
	if err != nil {
		return nil, fmt.Errorf("create openclaw: %w", err)
	}
	return o, nil
}

// GetOpenClawByID retrieves an OpenClaw by its ID.
func (s *Store) GetOpenClawByID(ctx context.Context, id string) (*OpenClaw, error) {
	row := s.db.QueryRowContext(ctx,
		`SELECT `+openclawColumns+` FROM rbac.openclaws WHERE id = $1`, id,
	)
	o, err := scanOpenClaw(row)
	if err == sql.ErrNoRows {
		return nil, nil
	}
	if err != nil {
		return nil, fmt.Errorf("get openclaw by id: %w", err)
	}
	return o, nil
}

// GetOpenClawByName retrieves an OpenClaw by its name.
func (s *Store) GetOpenClawByName(ctx context.Context, name string) (*OpenClaw, error) {
	row := s.db.QueryRowContext(ctx,
		`SELECT `+openclawColumns+` FROM rbac.openclaws WHERE name = $1`, name,
	)
	o, err := scanOpenClaw(row)
	if err == sql.ErrNoRows {
		return nil, nil
	}
	if err != nil {
		return nil, fmt.Errorf("get openclaw by name: %w", err)
	}
	return o, nil
}

// ListOpenClaws returns all OpenClaw instances with assignment counts.
func (s *Store) ListOpenClaws(ctx context.Context) ([]OpenClaw, error) {
	rows, err := s.db.QueryContext(ctx,
		`SELECT `+openclawColumns+`,
		        (SELECT COUNT(*) FROM rbac.openclaw_assignments a WHERE a.openclaw_id = o.id)
		 FROM rbac.openclaws o
		 ORDER BY o.created_at DESC`,
	)
	if err != nil {
		return nil, fmt.Errorf("list openclaws: %w", err)
	}
	defer rows.Close()

	var list []OpenClaw
	for rows.Next() {
		var o OpenClaw
		err := rows.Scan(
			&o.ID, &o.Name, &o.Description, &o.GatewayToken,
			&o.PodName, &o.ServiceName, &o.PVCName,
			&o.Namespace, &o.Status, &o.ErrorMessage,
			&o.Port, &o.CreatedBy, &o.CreatedAt, &o.UpdatedAt,
			&o.UserCount,
		)
		if err != nil {
			return nil, fmt.Errorf("scan openclaw row: %w", err)
		}
		list = append(list, o)
	}
	return list, rows.Err()
}

// UpdateOpenClawStatus updates the status and resource names for an OpenClaw.
func (s *Store) UpdateOpenClawStatus(ctx context.Context, id, status, podName, serviceName, pvcName, errorMsg string) error {
	_, err := s.db.ExecContext(ctx,
		`UPDATE rbac.openclaws
		 SET status = $2, pod_name = $3, service_name = $4, pvc_name = $5,
		     error_message = $6, updated_at = NOW()
		 WHERE id = $1`,
		id, status, podName, serviceName, pvcName, errorMsg,
	)
	if err != nil {
		return fmt.Errorf("update openclaw status: %w", err)
	}
	return nil
}

// DeleteOpenClaw removes an OpenClaw record by ID.
// Assignments are cascade-deleted via FK.
func (s *Store) DeleteOpenClaw(ctx context.Context, id string) error {
	_, err := s.db.ExecContext(ctx,
		`DELETE FROM rbac.openclaws WHERE id = $1`, id,
	)
	if err != nil {
		return fmt.Errorf("delete openclaw: %w", err)
	}
	return nil
}

// ── Assignments ─────────────────────────────────────────────────────────

// AssignUser assigns a user to an OpenClaw instance.
func (s *Store) AssignUser(ctx context.Context, userID, openclawID, assignedBy string) error {
	_, err := s.db.ExecContext(ctx,
		`INSERT INTO rbac.openclaw_assignments (user_id, openclaw_id, assigned_by)
		 VALUES ($1::UUID, $2::UUID, NULLIF($3, '')::UUID)
		 ON CONFLICT (user_id, openclaw_id) DO NOTHING`,
		userID, openclawID, assignedBy,
	)
	if err != nil {
		return fmt.Errorf("assign user: %w", err)
	}
	return nil
}

// UnassignUser removes a user's assignment to an OpenClaw instance.
func (s *Store) UnassignUser(ctx context.Context, userID, openclawID string) error {
	_, err := s.db.ExecContext(ctx,
		`DELETE FROM rbac.openclaw_assignments WHERE user_id = $1 AND openclaw_id = $2`,
		userID, openclawID,
	)
	if err != nil {
		return fmt.Errorf("unassign user: %w", err)
	}
	return nil
}

// GetUserOpenClaws returns all OpenClaws assigned to a user.
func (s *Store) GetUserOpenClaws(ctx context.Context, userID string) ([]UserOpenClaw, error) {
	rows, err := s.db.QueryContext(ctx,
		`SELECT o.id, o.name, COALESCE(o.description, ''), o.status, o.port,
		        (SELECT COUNT(*) FROM rbac.openclaw_assignments a2 WHERE a2.openclaw_id = o.id) AS user_count
		 FROM rbac.openclaws o
		 JOIN rbac.openclaw_assignments a ON a.openclaw_id = o.id
		 WHERE a.user_id = $1
		 ORDER BY o.name`,
		userID,
	)
	if err != nil {
		return nil, fmt.Errorf("get user openclaws: %w", err)
	}
	defer rows.Close()

	var list []UserOpenClaw
	for rows.Next() {
		var uo UserOpenClaw
		if err := rows.Scan(&uo.ID, &uo.Name, &uo.Description, &uo.Status, &uo.Port, &uo.UserCount); err != nil {
			return nil, fmt.Errorf("scan user openclaw: %w", err)
		}
		list = append(list, uo)
	}
	return list, rows.Err()
}

// IsUserAssigned checks if a user is assigned to a specific OpenClaw.
func (s *Store) IsUserAssigned(ctx context.Context, userID, openclawID string) (bool, error) {
	var exists bool
	err := s.db.QueryRowContext(ctx,
		`SELECT EXISTS(
			SELECT 1 FROM rbac.openclaw_assignments
			WHERE user_id = $1 AND openclaw_id = $2
		)`,
		userID, openclawID,
	).Scan(&exists)
	if err != nil {
		return false, fmt.Errorf("check assignment: %w", err)
	}
	return exists, nil
}

// GetOpenClawAssignments returns all user assignments for an OpenClaw.
func (s *Store) GetOpenClawAssignments(ctx context.Context, openclawID string) ([]Assignment, error) {
	rows, err := s.db.QueryContext(ctx,
		`SELECT id, user_id, openclaw_id, COALESCE(assigned_by::TEXT, ''), assigned_at
		 FROM rbac.openclaw_assignments
		 WHERE openclaw_id = $1
		 ORDER BY assigned_at`,
		openclawID,
	)
	if err != nil {
		return nil, fmt.Errorf("get assignments: %w", err)
	}
	defer rows.Close()

	var list []Assignment
	for rows.Next() {
		var a Assignment
		if err := rows.Scan(&a.ID, &a.UserID, &a.OpenClawID, &a.AssignedBy, &a.AssignedAt); err != nil {
			return nil, fmt.Errorf("scan assignment: %w", err)
		}
		list = append(list, a)
	}
	return list, rows.Err()
}
