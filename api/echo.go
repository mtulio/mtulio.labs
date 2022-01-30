package handler

import (
	"fmt"
	"net/http"
)

type Request struct {
	Headers interface{} `json:"headers"`
}

type Response struct {
	Request Request `json:"headers"`
}

func Handler(w http.ResponseWriter, r *http.Request) {
	fmt.Fprintf(w, r)
}
