package proxy

import (
	"fmt"
	"net/http"
	"net/http/httputil"
	"net/url"

	"trinity-agi/gateway-proxy/internal/resolver"
)

// HandleHTTP proxies an HTTP request to the upstream gateway pod using
// httputil.ReverseProxy. It injects the per-user gateway token as the
// Authorization header and copies all other headers.
func HandleHTTP(w http.ResponseWriter, r *http.Request, backend *resolver.Backend) {
	target := &url.URL{
		Scheme: "http",
		Host:   fmt.Sprintf("%s:%d", backend.Host, backend.Port),
	}

	proxy := &httputil.ReverseProxy{
		Director: func(req *http.Request) {
			req.URL.Scheme = target.Scheme
			req.URL.Host = target.Host
			req.Host = target.Host

			// Inject the per-user gateway token
			req.Header.Set("Authorization", "Bearer "+backend.Token)
		},
		ErrorHandler: func(w http.ResponseWriter, r *http.Request, err error) {
			http.Error(w, fmt.Sprintf("proxy error: %v", err), http.StatusBadGateway)
		},
	}

	proxy.ServeHTTP(w, r)
}

// browserControlPort is the socat bridge port on the OpenClaw pod that
// forwards to the loopback-bound browser control API (127.0.0.1:18791).
const browserControlPort = 18793

// HandleBrowserHTTP proxies browser control requests to port 18793 on the
// upstream pod. It strips the /__openclaw__/browser prefix so the browser
// control API receives the path it expects (e.g. "/" or "/?profile=openclaw").
func HandleBrowserHTTP(w http.ResponseWriter, r *http.Request, backend *resolver.Backend) {
	target := &url.URL{
		Scheme: "http",
		Host:   fmt.Sprintf("%s:%d", backend.Host, browserControlPort),
	}

	proxy := &httputil.ReverseProxy{
		Director: func(req *http.Request) {
			req.URL.Scheme = target.Scheme
			req.URL.Host = target.Host
			req.Host = target.Host

			// Strip the /__openclaw__/browser prefix
			path := req.URL.Path
			const prefix = "/__openclaw__/browser"
			if len(path) > len(prefix) {
				path = path[len(prefix):]
			} else {
				path = "/"
			}
			req.URL.Path = path

			// Inject the per-user gateway token
			req.Header.Set("Authorization", "Bearer "+backend.Token)
		},
		ErrorHandler: func(w http.ResponseWriter, r *http.Request, err error) {
			http.Error(w, fmt.Sprintf("browser proxy error: %v", err), http.StatusBadGateway)
		},
	}

	proxy.ServeHTTP(w, r)
}
