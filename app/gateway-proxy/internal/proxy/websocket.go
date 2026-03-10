package proxy

import (
	"encoding/json"
	"fmt"
	"log"
	"net/http"
	"sync"

	"trinity/gateway-proxy/internal/resolver"

	"github.com/gorilla/websocket"
)

var upgrader = websocket.Upgrader{
	ReadBufferSize:  4096,
	WriteBufferSize: 4096,
	CheckOrigin: func(r *http.Request) bool {
		return true // origin checked at nginx layer
	},
}

// HandleWebSocket upgrades the client connection, opens a WebSocket to the
// upstream gateway pod, rewrites the auth token in the first (connect) frame,
// then bidirectionally pipes all subsequent messages.
func HandleWebSocket(w http.ResponseWriter, r *http.Request, backend *resolver.Backend) {
	// Upgrade client connection
	clientConn, err := upgrader.Upgrade(w, r, nil)
	if err != nil {
		log.Printf("websocket upgrade error: %v", err)
		return
	}
	defer clientConn.Close()

	// Open upstream connection with matching Origin header so OpenClaw
	// accepts the connection (controlUi.dangerouslyAllowHostHeaderOriginFallback).
	upstreamURL := fmt.Sprintf("ws://%s:%d/ws", backend.Host, backend.Port)
	upstreamHeaders := http.Header{
		"Origin": {fmt.Sprintf("http://%s:%d", backend.Host, backend.Port)},
	}
	upstreamConn, _, err := websocket.DefaultDialer.Dial(upstreamURL, upstreamHeaders)
	if err != nil {
		log.Printf("upstream websocket dial error: %v", err)
		clientConn.WriteMessage(websocket.CloseMessage,
			websocket.FormatCloseMessage(websocket.CloseInternalServerErr, "upstream unavailable"))
		return
	}
	defer upstreamConn.Close()

	// OpenClaw protocol: upstream sends connect.challenge first, then client
	// responds with connect request. We need to:
	// 1. Forward the challenge from upstream to client
	// 2. Read the client's connect response
	// 3. Rewrite the auth token and forward to upstream

	// Step 1: Forward connect.challenge from upstream to client
	challengeMsgType, challengeData, err := upstreamConn.ReadMessage()
	if err != nil {
		log.Printf("upstream challenge read error: %v", err)
		clientConn.WriteMessage(websocket.CloseMessage,
			websocket.FormatCloseMessage(websocket.CloseInternalServerErr, "upstream challenge error"))
		return
	}
	log.Printf("[ws-debug] challenge received (%d bytes): %s", len(challengeData), truncate(string(challengeData), 200))
	if err := clientConn.WriteMessage(challengeMsgType, challengeData); err != nil {
		log.Printf("client challenge write error: %v", err)
		return
	}

	// Step 2+3: Read client's connect response, rewrite token, forward
	if err := handleConnectFrame(clientConn, upstreamConn, backend.Token); err != nil {
		log.Printf("connect frame handling error: %v", err)
		clientConn.WriteMessage(websocket.CloseMessage,
			websocket.FormatCloseMessage(websocket.CloseInternalServerErr, "connect frame error"))
		return
	}

	// Step 4: Forward the hello-ok response from upstream to client
	helloMsgType, helloData, err := upstreamConn.ReadMessage()
	if err != nil {
		log.Printf("[ws-debug] upstream hello-ok read error: %v", err)
		return
	}
	log.Printf("[ws-debug] hello-ok received (%d bytes): %s", len(helloData), truncate(string(helloData), 200))
	if err := clientConn.WriteMessage(helloMsgType, helloData); err != nil {
		log.Printf("client hello-ok write error: %v", err)
		return
	}

	// Bidirectional pipe for all subsequent messages
	var once sync.Once
	done := make(chan struct{})

	closeAll := func() {
		once.Do(func() {
			close(done)
		})
	}

	// Client -> Upstream
	go func() {
		defer closeAll()
		for {
			msgType, data, err := clientConn.ReadMessage()
			if err != nil {
				if !websocket.IsCloseError(err, websocket.CloseNormalClosure, websocket.CloseGoingAway) {
					log.Printf("client read error: %v", err)
				}
				return
			}
			if err := upstreamConn.WriteMessage(msgType, data); err != nil {
				log.Printf("upstream write error: %v", err)
				return
			}
		}
	}()

	// Upstream -> Client
	go func() {
		defer closeAll()
		for {
			msgType, data, err := upstreamConn.ReadMessage()
			if err != nil {
				if !websocket.IsCloseError(err, websocket.CloseNormalClosure, websocket.CloseGoingAway) {
					log.Printf("upstream read error: %v", err)
				}
				return
			}
			if err := clientConn.WriteMessage(msgType, data); err != nil {
				log.Printf("client write error: %v", err)
				return
			}
		}
	}()

	// Wait for either side to close
	<-done
}

// handleConnectFrame reads the first message from the client, replaces the
// auth token with the per-user gateway token, and forwards to upstream.
//
// The connect frame is JSON like:
// {"type":"req","id":"...","method":"connect","params":{"auth":{"token":"<CLIENT_JWT>"},...}}
//
// We replace params.auth.token with the gateway token.
func handleConnectFrame(clientConn, upstreamConn *websocket.Conn, gatewayToken string) error {
	msgType, data, err := clientConn.ReadMessage()
	if err != nil {
		return fmt.Errorf("reading connect frame: %w", err)
	}

	// Try to parse and rewrite the auth token
	rewritten, err := rewriteConnectToken(data, gatewayToken)
	if err != nil {
		// If we can't parse it, forward as-is (might not be a connect frame)
		log.Printf("warning: could not rewrite connect frame, forwarding as-is: %v", err)
		return upstreamConn.WriteMessage(msgType, data)
	}

	return upstreamConn.WriteMessage(msgType, rewritten)
}

// rewriteConnectToken parses a connect frame JSON, replaces the auth token,
// and re-serializes it. Uses a generic map to preserve all other fields.
func truncate(s string, n int) string {
	if len(s) <= n {
		return s
	}
	return s[:n]
}

func rewriteConnectToken(data []byte, gatewayToken string) ([]byte, error) {
	var msg map[string]interface{}
	if err := json.Unmarshal(data, &msg); err != nil {
		return nil, fmt.Errorf("unmarshalling connect frame: %w", err)
	}

	// Navigate to params.auth.token
	params, ok := msg["params"]
	if !ok {
		return nil, fmt.Errorf("no 'params' field in connect frame")
	}
	paramsMap, ok := params.(map[string]interface{})
	if !ok {
		return nil, fmt.Errorf("'params' is not an object")
	}

	authField, ok := paramsMap["auth"]
	if !ok {
		return nil, fmt.Errorf("no 'auth' field in params")
	}
	authMap, ok := authField.(map[string]interface{})
	if !ok {
		return nil, fmt.Errorf("'auth' is not an object")
	}

	// Replace the token
	oldToken, _ := authMap["token"].(string)
	authMap["token"] = gatewayToken
	log.Printf("[ws-debug] token rewrite: old=%s... new=%s...", truncate(oldToken, 20), truncate(gatewayToken, 20))

	// Re-serialize
	result, err := json.Marshal(msg)
	if err != nil {
		return nil, fmt.Errorf("marshalling rewritten connect frame: %w", err)
	}

	log.Printf("[ws-debug] rewritten connect frame: %s", truncate(string(result), 200))
	return result, nil
}
