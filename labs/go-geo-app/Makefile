

VERSION ?= $(shell git rev-parse --short HEAD)
CONTAINER_IMAGE ?= quay.io/mrbraga/go-geo-app

.PHONY: run
run:
	go run main.go

.PHONY: build-bin
build-bin:
	go build

.PHONY: build-container
build-container:
	podman build -t $(CONTAINER_IMAGE):$(VERSION) .
	podman tag $(CONTAINER_IMAGE):$(VERSION) $(CONTAINER_IMAGE):latest

.PHONY: push-container
push-container:
	podman push $(CONTAINER_IMAGE):$(VERSION)
	podman push $(CONTAINER_IMAGE):latest

.PHONY: deploy
deploy: build-container push-container

.PHONY: run-redis
run-redis:
	podman run -p 6379 -d redis
