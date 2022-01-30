package handler

import (
	"fmt"
	"net/http"
)

func Handler(w http.ResponseWriter, r *http.Request) {
	ip := r.Header.Get("X-Real-Ip")
	if ip != "" {
		fmt.Fprintf(w, ip)
		return
	}
	fmt.Fprintf(w, "pong", r)
}
