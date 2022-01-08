# Alpine Dockerfile | containers

Create small container images using Alpine Linux

- Multi-layer strategy

```Dockerfile
FROM golang:1.17 as builder
WORKDIR /go/src/app
COPY . .

RUN go get -d -v ./...
RUN CGO_ENABLED=0 GOOS=linux go build -a -installsuffix cgo -o lb-watcher ./cmd/lb-watcher/

FROM alpine:latest
RUN apk --no-cache add ca-certificates
WORKDIR /app
COPY --from=builder /go/src/app/lb-watcher /app/
RUN chmod +x ./lb-watcher
CMD [ "./lb-watcher" ]
```
