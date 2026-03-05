FROM golang:1.22-bookworm AS builder
WORKDIR /app
COPY go.mod go.sum* ./
RUN go mod download
COPY . .
RUN go mod tidy && CGO_ENABLED=0 go build -o /gateway-proxy .

FROM gcr.io/distroless/static-debian12
COPY --from=builder /gateway-proxy /gateway-proxy
ENTRYPOINT ["/gateway-proxy"]
