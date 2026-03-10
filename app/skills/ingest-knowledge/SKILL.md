---
name: ingest-knowledge
description: Ingest and index documents into the retrieval layer for a specific claw, workspace, or knowledge corpus.
homepage: https://github.com/trinityagi/trinity
metadata:
  {
    "openclaw":
      {
        "emoji": "📥",
      },
  }
---

# Ingest Knowledge

Register, extract, chunk, and index documents into the retrieval layer for later use by other claws.

## Purpose

Use this capability when a claw needs knowledge to be available in the retrieval layer but should not own ingestion itself.

Examples:
- pre-index a handbook corpus
- index a tender document before running `tender-check`
- load workspace-specific reference materials for another claw

## Responsibilities

- register documents
- extract normalized text
- chunk content with stable identifiers
- index content into the retrieval subsystem
- maintain document metadata, status, and workspace scoping

## Workspace Contract

Knowledge should be ingested into the target claw's default workspace, not an arbitrary caller-defined workspace.

Default convention:
- `tenant_<tenantId>__claw_<openclawId>`

Guidelines:
- the ingestion caller should provide claw identity
- Trinity should derive the workspace before calling the retrieval layer
- downstream claws should consume the same derived workspace

## What This Skill Does Not Do

- domain-specific compliance analysis
- tender-specific contradiction checking
- requirement classification

Those belong to downstream claws such as `tender-check`.

## Output

Return:
- document references
- workspace or corpus identifiers
- indexing status
- chunk and citation availability
