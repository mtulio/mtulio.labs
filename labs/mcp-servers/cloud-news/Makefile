.PHONY: all build-server build-client clean

all: build-server build-client

build-server:
	go build -o aws aws.go

build-client:
	go build -o aws-client client/main.go

clean:
	rm -f aws aws-client
	#rmdir bin 2>/dev/null || true
