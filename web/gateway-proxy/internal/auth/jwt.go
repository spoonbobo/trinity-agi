package auth

import (
	"fmt"
	"net/http"
	"strings"

	"github.com/golang-jwt/jwt/v5"
)

// ParseUserID parses a JWT signed with HS256, extracts the "sub" claim as the
// user ID, and validates expiration. Returns the user ID string.
func ParseUserID(tokenString string, jwtSecret []byte) (string, error) {
	token, err := jwt.Parse(tokenString, func(token *jwt.Token) (interface{}, error) {
		if _, ok := token.Method.(*jwt.SigningMethodHMAC); !ok {
			return nil, fmt.Errorf("unexpected signing method: %v", token.Header["alg"])
		}
		return jwtSecret, nil
	}, jwt.WithValidMethods([]string{"HS256"}))
	if err != nil {
		return "", fmt.Errorf("invalid token: %w", err)
	}

	claims, ok := token.Claims.(jwt.MapClaims)
	if !ok || !token.Valid {
		return "", fmt.Errorf("invalid token claims")
	}

	sub, ok := claims["sub"]
	if !ok {
		return "", fmt.Errorf("token missing 'sub' claim")
	}

	userID, ok := sub.(string)
	if !ok {
		return "", fmt.Errorf("'sub' claim is not a string")
	}

	if userID == "" {
		return "", fmt.Errorf("'sub' claim is empty")
	}

	return userID, nil
}

// ExtractToken tries to get a JWT from the request:
//  1. Authorization: Bearer <token> header
//  2. ?token=<token> query parameter (for WebSocket upgrades)
//
// Returns the raw token string or "".
func ExtractToken(r *http.Request) string {
	// Try Authorization header first
	authHeader := r.Header.Get("Authorization")
	if authHeader != "" {
		parts := strings.SplitN(authHeader, " ", 2)
		if len(parts) == 2 && strings.EqualFold(parts[0], "Bearer") {
			token := strings.TrimSpace(parts[1])
			if token != "" {
				return token
			}
		}
	}

	// Fall back to query parameter
	if token := r.URL.Query().Get("token"); token != "" {
		return token
	}

	return ""
}
