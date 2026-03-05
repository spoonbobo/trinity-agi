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
