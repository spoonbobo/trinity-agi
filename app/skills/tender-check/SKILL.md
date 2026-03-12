---
name: tender-check
description: Check an RSS tender against handbook guidance and return an evidence-backed compliance report.
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

Analyze one Resident Site Staff tender document against handbook knowledge in the active `openclaw` workspace and return a structured compliance report.

## Scope

This skill is domain-specific to RSS tender compliance against the government management handbook.

It should produce an end-to-end compliance result for one tender, but it relies on the platform retrieval layer and the claw's internal plugin/tooling system for evidence lookup, document reading, analysis, and structured output.

It does not own handbook ingestion. It assumes the relevant handbook knowledge is already available in the active `openclaw` workspace through LightRAG.

It also does not need to ingest the tender. If the tender file is already available to the current run, it may be read directly and compared against the indexed handbook evidence in the active workspace.

The tender itself may be provided either as:
- a direct file attachment or workspace file that the claw can read line by line, or
- an indexed tender document already present in the active workspace

## What It Does

- profiles the tender to detect relevant handbook topics
- selects applicable handbook requirements
- checks requirement compliance against tender clauses
- detects contradictions within the same tender
- reports omissions, confidence, and supporting evidence
- highlights compliant and non-compliant areas with justification
- surfaces other important findings that materially affect tender quality, risk, or reviewability

## Retrieval Contract

Use the `openclaw`-scoped LightRAG workspace for handbook knowledge and use the claw's internal plugin/tooling system to read the tender, retrieve evidence, structure comparisons, and format output.

If retrieval is delegated to another skill, prefer `query-knowledge` rather than mixing tender compliance logic with raw retrieval orchestration.

Operational rules:
- rely on existing indexed handbook knowledge in the active `openclaw` workspace
- derive the active workspace from the current `openclaw` context; do not invent alternate workspaces
- the tender does not have to be indexed if the claw can read it directly from the current agentic workspace or attachment context
- never ingest or re-index the tender or handbook as part of this skill run
- use workspace-scoped retrieval only for handbook evidence
- use exact evidence from indexed tender or handbook chunks whenever possible
- when tender evidence comes from direct file reading, cite file section, heading, page, or line range as precisely as available
- do not claim a requirement is applicable unless retrieval evidence supports that conclusion
- keep contradiction analysis limited to the same tender document

## Expected Input

Provide at minimum:
- one tender document reference, file, or upload
- one active `openclaw` workspace that already contains the relevant indexed handbook knowledge

Optional but recommended:
- handbook document id or approved handbook version when the workspace contains multiple handbook sources

The tender may be analyzed directly from the uploaded file or workspace file. Handbook compliance requirements should come from knowledge already present in the active `openclaw` LightRAG workspace.

## Intake Behavior

When the user asks a setup question such as "what shall I provide" or "what do you need from me", respond minimally:
- ask for the tender document first
- mention that extra context is optional, not required
- do not block on consultancy/work contract type, RSS type, or special concerns if the tender file is already available
- once the tender file is available, proceed with analysis rather than repeating the full workflow

## Analysis Workflow

Recommended flow:
- read the tender directly from the provided file or indexed tender source
- retrieve the handbook requirements relevant to the tender scope
- map tender clauses against those requirements
- classify each requirement as compliant, non-compliant, missing, or unclear
- detect internal contradictions inside the tender
- assign confidence per requirement based on evidence quality and specificity
- summarize other important findings worth reviewer attention

## Evidence Requirements

For every major conclusion, provide:
- exact requirement text or a faithful requirement summary grounded in handbook evidence
- exact tender evidence
- clause, section, line range, chunk, or page references when available
- a short explanation of why the evidence supports the result

## Output

Always return structured output with:
- requirement
- status (`compliant`, `non-compliant`, `missing`, or `unclear`)
- handbook evidence
- tender evidence
- reference locations
- confidence
- reasoning
- suggested fix when non-compliant
- contradiction findings when present
- other important findings when relevant

Produce two deliverables when file output is supported by the caller:
- a machine-friendly JSON report using the stable schema below
- a structured `.docx` report containing summary, requirements, contradictions, and other findings

The `.docx` should mirror the JSON result rather than introducing different conclusions.

## Stable Output Schema

Return the final result in a machine-friendly JSON object with this shape:

```json
{
  "tender": {
    "document_id": "string",
    "title": "string"
  },
  "handbook": {
    "document_ids": ["string"],
    "version": "string"
  },
  "summary": {
    "overall_status": "compliant|mixed|non-compliant|unclear",
    "requirement_count": 0,
    "compliant_count": 0,
    "non_compliant_count": 0,
    "missing_count": 0,
    "unclear_count": 0
  },
  "requirements": [
    {
      "requirement_id": "string",
      "requirement": "string",
      "status": "compliant|non-compliant|missing|unclear",
      "confidence": 0.0,
      "reasoning": "string",
      "suggested_fix": "string|null",
      "handbook_evidence": [
        {
          "quote": "string",
          "reference": "string",
          "page": "string|null",
          "chunk_id": "string|null"
        }
      ],
      "tender_evidence": [
        {
          "quote": "string",
          "reference": "string",
          "page": "string|null",
          "chunk_id": "string|null"
        }
      ]
    }
  ],
  "contradictions": [
    {
      "topic": "string",
      "description": "string",
      "confidence": 0.0,
      "evidence": [
        {
          "quote": "string",
          "reference": "string",
          "page": "string|null",
          "chunk_id": "string|null"
        }
      ]
    }
  ],
  "other_findings": [
    {
      "title": "string",
      "severity": "low|medium|high",
      "description": "string",
      "evidence": [
        {
          "quote": "string",
          "reference": "string",
          "page": "string|null",
          "chunk_id": "string|null"
        }
      ]
    }
  ]
}
```

Formatting rules:
- return valid JSON only for the final structured result unless the caller explicitly asks for prose
- keep `confidence` normalized to `0.0`-`1.0`
- use empty arrays instead of omitting keys
- use `null` rather than placeholder strings for unknown optional fields
- keep evidence quotes concise and exact

## DOCX Output Contract

When generating a `.docx` file, structure it with these sections in order:
- title block containing tender title, tender document id, handbook version, and handbook document ids
- `Summary`
- `Requirements`
- `Contradictions`
- `Other Findings`

For each requirement entry in the `.docx`, include:
- requirement title
- requirement id
- status
- confidence
- reasoning
- suggested fix when present
- handbook evidence bullets
- tender evidence bullets

For each contradiction or other finding, include:
- title or topic
- confidence or severity
- description
- supporting evidence bullets when available

## JSON to DOCX Conversion Path

Use this conversion flow when the caller asks for a `.docx` deliverable:

1. produce the stable JSON result first
2. render that JSON into a deterministic markdown report that mirrors the same conclusions
3. convert the markdown report to `.docx` with `pandoc`
4. if `pandoc` formatting is insufficient for a specific requirement, use `/opt/doctools/bin/python` with `python-docx` as a fallback

Preferred command path:

```bash
pandoc report.md -o report.docx
```

Fallback path:

```bash
/opt/doctools/bin/python build_report.py
```

Rules:
- the `.docx` must be derived from the stable JSON result, not from a separate second-pass analysis
- do not introduce findings in the `.docx` that are absent from the JSON
- keep section order and requirement status labels consistent between JSON and `.docx`
- save the generated `.docx` into the current workspace and return it as a generated file artifact when the caller expects a file
- when returning generated report files in chat, emit explicit workspace file references or `MEDIA:` lines so the shell can render clickable links to the `.json` and `.docx` outputs

## Notes

- Do not use this skill for cross-document consistency analysis outside the same tender.
- Do not use static or hardcoded handbook logic; requirements must come from retrieval-backed evidence.
- Do not ingest or re-index the handbook here; rely on the knowledge already present in LightRAG for this `openclaw`.
- Do not ingest the tender as part of this skill unless a caller explicitly overrides this contract.
- Prefer direct tender reading when the tender file is already available in the current agentic environment.
- Use the claw's internal plugin/tooling system when it helps with retrieval, comparison, or result formatting.
- Use the platform-derived `openclaw` workspace contract rather than inventing a workspace per request.
