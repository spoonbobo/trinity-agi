---
name: tender-check
description: Check an indexed RSS tender document against indexed handbook knowledge and return an evidence-backed compliance report.
homepage: https://github.com/trinityagi/trinity
metadata:
  {
    "openclaw":
      {
        "emoji": "📘",
      },
  }
---

# Tender Check

Analyze one indexed Resident Site Staff tender document against indexed handbook knowledge and return a structured compliance report.

## Scope

This skill is intentionally narrow. It does **not** ingest or index documents itself.

It assumes:
- the tender document is already indexed
- the handbook corpus is already indexed
- retrieval and citations are available through the retrieval layer
- both corpora are available in the claw's derived default workspace

## What It Does

- profiles the tender to detect relevant handbook topics
- selects applicable handbook requirements
- checks requirement compliance against tender clauses
- detects contradictions within the same tender
- reports omissions, confidence, and supporting evidence

## Expected Input

Provide:
- an indexed tender document reference
- one or more indexed handbook document references or an approved handbook version

## Output

Always return structured output with:
- requirement
- status
- evidence
- confidence
- suggested fix when non-compliant
- contradiction findings when present

## Notes

- Do not use this skill for cross-document consistency analysis outside the same tender.
- Do not re-ingest the tender or handbook here. Use the separate ingestion capability first if needed.
- Use the platform-derived claw workspace contract rather than inventing a workspace per request.
