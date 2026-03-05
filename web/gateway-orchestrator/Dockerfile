FROM golang:1.22-bookworm AS builder
WORKDIR /app
COPY go.mod go.sum ./
RUN go mod download
COPY . .
RUN CGO_ENABLED=0 go build -o /gateway-orchestrator .

FROM gcr.io/distroless/static-debian12
COPY --from=builder /gateway-orchestrator /gateway-orchestrator
ENTRYPOINT ["/gateway-orchestrator"]
