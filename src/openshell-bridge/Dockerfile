FROM golang:1.22-alpine AS builder

WORKDIR /build
COPY go.mod go.sum* ./
COPY . .
RUN go mod tidy && CGO_ENABLED=0 go build -o openshell-bridge .

FROM alpine:3.20

RUN apk add --no-cache ca-certificates curl bash

COPY --from=builder /build/openshell-bridge /usr/local/bin/openshell-bridge

EXPOSE 18800

ENTRYPOINT ["openshell-bridge"]
