# Trinity Shell Web — Multi-stage Docker build
# Mirrors the Flutter frontend Dockerfile pattern:
# build -> copy to /output/ volume

FROM node:22-alpine AS builder

WORKDIR /app

# Install dependencies
COPY package.json package-lock.json* ./
RUN npm ci --no-audit --no-fund 2>/dev/null || npm install --no-audit --no-fund

# Copy source
COPY . .

# Build args (same 4 as Flutter Dockerfile)
ARG NEXT_PUBLIC_GATEWAY_WS_URL=ws://localhost/ws
ARG NEXT_PUBLIC_TERMINAL_WS_URL=ws://localhost/terminal/
ARG NEXT_PUBLIC_AUTH_SERVICE_URL=http://localhost
ARG NEXT_PUBLIC_SUPABASE_ANON_KEY=

# Build static export
RUN npm run build

# Generate version marker (same as Flutter Dockerfile)
RUN echo "{\"version\":\"$(date -u +%Y%m%d%H%M%S)\",\"build\":\"$(date -u +%Y-%m-%dT%H:%M:%SZ)\"}" > /app/out/trinity-version.json

# -------------------------------------------------------------------
# Output stage — copies build artifacts to /output/ volume
# -------------------------------------------------------------------
FROM alpine:3.19

COPY --from=builder /app/out /build

CMD ["sh", "-c", "cp -r /build/* /output/ && echo 'Web build copied to /output/'"]
