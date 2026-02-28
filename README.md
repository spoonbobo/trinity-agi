# Trinity

An agentic shell powered by [OpenClaw](https://docs.openclaw.ai).
The UI starts as a blank canvas — the agent and user build functionality together at runtime.

## Prerequisites

- Docker Desktop (with Compose v2)
- An LLM provider API key (OpenAI, Anthropic, Google, etc.)

## Deployment

### 1. Configure environment

```bash
cp web/.env.example web/.env
```

Edit `web/.env` and set a gateway token:

```
OPENCLAW_GATEWAY_TOKEN=<your-token>
```

Generate one with `openssl rand -hex 32` if needed.

### 2. Build the frontend

```bash
docker compose -f web/docker-compose.yml --profile build build --no-cache frontend-builder
docker compose -f web/docker-compose.yml --profile build run --rm frontend-builder
```

This compiles the Flutter web app and copies the static files into a shared Docker volume.

### 3. Start the stack

```bash
docker compose -f web/docker-compose.yml up -d
```

### 4. Configure LLM providers

Open the OpenClaw dashboard at http://localhost:18789 and add your LLM provider API keys.

### 5. Use Trinity

Open http://localhost in your browser.

### Rebuilding after code changes

```bash
docker compose -f web/docker-compose.yml --profile build build --no-cache frontend-builder
docker compose -f web/docker-compose.yml --profile build run --rm frontend-builder
docker compose -f web/docker-compose.yml restart nginx
```

## License

See [LICENSE](LICENSE) if present, or contact the maintainers.
