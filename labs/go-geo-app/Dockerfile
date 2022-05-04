FROM golang:1.18.1-alpine3.14 as builder

WORKDIR /go/src/app
COPY . .

RUN go get -d -v ./...
RUN CGO_ENABLED=0 \
    GOOS=linux \
    go build \
    -a -installsuffix cgo \
    -o go-geo-app main.go

FROM alpine:3.14
RUN apk --no-cache add ca-certificates
WORKDIR /app
COPY --from=builder /go/src/app/go-geo-app /app/
RUN chmod +x ./go-geo-app
CMD [ "./go-geo-app" ]
