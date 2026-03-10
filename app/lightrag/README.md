# LightRAG Sidecar

Python sidecar for Trinity tender-check retrieval.

This service is intentionally scoped as an internal retrieval subsystem:

- Trinity remains the auth and RBAC boundary.
- The sidecar uses header-based scope from trusted Trinity callers.
- `workspace` is used for data isolation, not as a replacement for authorization.

## Responsibilities

- accept authorized document uploads for external ingestion flows
- extract normalized text from `pdf`, `docx`, `txt`, and `md`
- persist chunks and extraction artifacts for evidence/citation use
- index content into LightRAG per workspace
- provide scoped retrieval and comparison endpoints
- provide tender-check analysis endpoints over already indexed corpora

## Environment

Required for internal access:

- `LIGHTRAG_INTERNAL_TOKEN`

Optional but recommended for LightRAG query/index quality:

- `OPENAI_API_KEY`
- `OPENAI_BASE_URL`
- `LIGHTRAG_LLM_API_KEY`
- `LIGHTRAG_LLM_BASE_URL`
- `LIGHTRAG_LLM_MODEL`
- `LIGHTRAG_EMBEDDING_API_KEY`
- `LIGHTRAG_EMBEDDING_BASE_URL`
- `LIGHTRAG_EMBEDDING_MODEL`
- `LIGHTRAG_EMBEDDING_DIM`
- `LIGHTRAG_EMBEDDING_MAX_TOKENS`

## Trusted Headers

Trinity should send:

- `Authorization: Bearer <LIGHTRAG_INTERNAL_TOKEN>`
- `X-Trinity-Tenant`
- `X-Trinity-Workspace`
- `X-Trinity-User`
- `X-Trinity-Openclaw` when the workspace belongs to a specific claw

## Workspace Contract

Default claw workspace convention:
- `tenant_<tenantId>__claw_<openclawId>`

Behavior:
- if `X-Trinity-Openclaw` is present, the sidecar derives the canonical workspace
- if both `X-Trinity-Openclaw` and `X-Trinity-Workspace` are present, they must match
- callers should not invent arbitrary workspaces for claw-owned corpora

## API Summary

- `GET /health`
- `POST /documents`
- `POST /documents/{document_id}/ingest`
- `GET /documents/{document_id}/status`
- `GET /documents/{document_id}/chunks`
- `GET /knowledge/graph`
- `POST /retrieval/search`
- `POST /retrieval/compare`
- `POST /tender-check/runs`
- `GET /tender-check/runs/{run_id}`
- `GET /tender-check/runs/{run_id}/report`

## Notes

- If LightRAG model credentials are missing, the service still stores files, extracts text, chunks content, and returns evidence via deterministic local chunk search.
- When LightRAG is configured, responses also include LightRAG-generated retrieval output.
- `tender-check` consumes already indexed corpora. It does not own ingestion inside its workflow.
- Separate provider credentials are supported for:
  - LLM/chat completions
  - embedding generation
