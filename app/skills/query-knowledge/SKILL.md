---
name: query-knowledge
description: Query existing LightRAG knowledge in a claw-scoped workspace without ingesting or mutating documents.
homepage: https://github.com/trinityagi/trinity
metadata:
  {
    "openclaw":
      {
        "emoji": "🔎",
      },
  }
---

# Query Knowledge

Search, compare, inspect, and summarize knowledge that is already indexed in the active `openclaw` LightRAG workspace.

## Purpose

Use this skill when a claw needs retrieval-backed answers from existing knowledge without performing ingestion, re-indexing, or document mutation.

Examples:
- search an indexed handbook for applicable requirements
- compare two indexed documents against a question
- inspect document status, chunks, or graph labels before analysis
- retrieve evidence for a downstream compliance or reasoning skill

## Responsibilities

- list existing indexed documents
- inspect document status and chunks
- run scoped retrieval queries
- run scoped compare queries
- inspect graph labels or graph slices when graph knowledge is useful
- return evidence-backed retrieval results for downstream workflows

## Non-Responsibilities

- do not upload, register, ingest, or delete documents
- do not create or alter workspaces
- do not invent knowledge that is absent from indexed sources

## Workspace Contract

Knowledge queries must stay in the target claw's derived default workspace, not an arbitrary caller-defined workspace.

Default convention:
- `tenant_<tenantId>__claw_<openclawId>`

Rules:
- derive the active workspace from the current `openclaw` context
- do not switch to alternate workspaces unless the platform explicitly does so
- cross-workspace query and compare are not allowed

## Query Contract (same workspace only)

Read/query through auth-service scoped endpoints for the active OpenClaw:

- `GET /auth/openclaws/:id/lightrag-documents`
- `GET /auth/openclaws/:id/lightrag-documents/:documentId/status`
- `GET /auth/openclaws/:id/lightrag-documents/:documentId/chunks`
- `GET /auth/openclaws/:id/lightrag-scope`
- `GET /auth/openclaws/:id/lightrag-search`
- `GET /auth/openclaws/:id/lightrag-label-search`
- `GET /auth/openclaws/:id/lightrag-graph`
- `POST /auth/openclaws/:id/lightrag-query`
- `POST /auth/openclaws/:id/lightrag-compare`

## Auth Modes

Use one of these auth modes depending on caller context:

- user-scoped auth via valid JWT when running from the app UI or user session
- delegation token via `X-Trinity-Delegation` when the caller already minted a scoped delegation token
- claw-runtime service auth via `X-OpenClaw-Gateway-Token` when running inside the claw for the same `openclaw`

Operational rules:
- for claw-runtime calls, prefer `OPENCLAW_ID` env (UUID) for `:id`; name aliases may resolve but UUID is canonical
- use `TRINITY_AUTH_SERVICE_URL` as the base URL for `/auth/openclaws/*` routes
- do not send `/auth/openclaws/*` routes to the OpenClaw gateway port
- workspace is enforced server-side; do not try to override it in request payloads

## Relationship to Ingest Knowledge

- `ingest-knowledge` prepares and indexes knowledge
- `query-knowledge` only reads and compares knowledge that is already present
- downstream skills can depend on `query-knowledge` without taking on ingestion responsibilities

## Relationship to OpenClaw Memory

- this skill uses the LightRAG service and its own workspace-scoped knowledge store
- OpenClaw memory plugin settings do not configure these retrieval endpoints
- both systems are complementary: memory plugin supports agent memory, LightRAG supports indexed document retrieval

## Expected Input

Provide at minimum:
- one active `openclaw` workspace containing indexed knowledge
- one query, comparison task, document id, or label to inspect

Optional:
- preferred handbook version or document ids when multiple sources exist
- retrieval mode, top-k, or graph label when the caller needs tighter control

## Output

Return:
- retrieved evidence and citations
- matched documents or document ids
- relevant chunks or references
- compare results when used
- graph labels or graph metadata when used
- concise summary grounded in indexed evidence

## Notes

- do not ingest or re-index documents here; use `ingest-knowledge` separately when knowledge is missing
- do not claim missing knowledge is present if retrieval returns nothing
- prefer exact quotes and references over paraphrase when supporting a downstream decision
