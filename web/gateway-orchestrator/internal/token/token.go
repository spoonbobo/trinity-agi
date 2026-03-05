package token

import (
	"crypto/rand"
	"encoding/hex"
	"fmt"
)

// GenerateToken produces a cryptographically random 64-character hex token.
func GenerateToken() (string, error) {
	b := make([]byte, 32)
	if _, err := rand.Read(b); err != nil {
		return "", fmt.Errorf("generate token: %w", err)
	}
	return hex.EncodeToString(b), nil
}
