from __future__ import annotations

import re
from collections import Counter, defaultdict
from datetime import datetime, timezone
from uuid import uuid4

from .extractors import score_query_against_chunks
from .requirement_library import RequirementDefinition, list_requirements
from .schemas import (
    ChunkRecord,
    ContradictionFinding,
    DocumentProfile,
    DocumentRecord,
    EvidenceQuote,
    RequirementFinding,
    TenderCheckAudit,
    TenderCheckReport,
    TenderCheckRequest,
    TenderCheckSummary,
)


ROLE_KEYWORDS = {
    "lro": ["labour relation officer", "lro"],
    "rss_manual": ["rss manual"],
    "site_supervision": ["site supervision", "supervise the works", "works contracts"],
}

TOPIC_KEYWORDS = {
    "approval_requirements": ["approval", "approved", "consent", "submit"],
    "reporting_intervals": ["half-yearly", "quarterly", "monthly", "annual", "within"],
    "roles_and_responsibilities": ["responsible for", "duties", "carry out"],
    "employment_conditions": ["employment", "conditions of employment", "special conditions"],
    "deadlines": ["within", "prior to", "before", "after"],
    "approving_authority": ["dr", "managing department", "engineer", "consultant"],
}

TIME_PATTERNS = [
    re.compile(r"\bwithin\s+\d+\s+(?:day|days|week|weeks|month|months|year|years)\b", re.I),
    re.compile(r"\b\d+\s*-\s*(?:day|days|week|weeks|month|months|year|years)\b", re.I),
    re.compile(r"\b(?:half-yearly|quarterly|monthly|weekly|annually|yearly)\b", re.I),
]


def generate_report(
    request: TenderCheckRequest,
    tenant_id: str,
    tender_record: DocumentRecord,
    handbook_records: list[DocumentRecord],
    tender_chunks: list[ChunkRecord],
    handbook_chunks: list[ChunkRecord],
) -> TenderCheckReport:
    profile = build_profile(tender_chunks)
    requirements = select_requirements(profile, request.requirement_ids, tender_chunks)
    findings = [
        evaluate_requirement(requirement, tender_chunks, handbook_chunks, request.top_k)
        for requirement in requirements
    ]
    contradictions = detect_contradictions(tender_chunks)
    summary = build_summary(findings, contradictions)
    handbook_version = _resolve_handbook_version(handbook_records)
    return TenderCheckReport(
        run_id=str(uuid4()),
        tenant_id=tenant_id,
        workspace_id=request.workspace_id,
        openclaw_id=tender_record.openclaw_id,
        document_id=request.tender_document_id,
        handbook_version=handbook_version,
        document_profile=profile,
        summary=summary,
        requirements=findings,
        contradictions=contradictions,
        audit=TenderCheckAudit(
            retrieval_mode=request.retrieval_mode,
            handbook_version=handbook_version,
            generated_at=datetime.now(timezone.utc),
        ),
    )


def build_profile(tender_chunks: list[ChunkRecord]) -> DocumentProfile:
    full_text = "\n".join(chunk.text for chunk in tender_chunks).lower()
    roles = [name for name, keywords in ROLE_KEYWORDS.items() if any(keyword in full_text for keyword in keywords)]

    topic_counts: Counter[str] = Counter()
    for requirement in list_requirements():
        for keyword in requirement.trigger_conditions:
            if keyword.lower() in full_text:
                topic_counts[requirement.handbook_section] += 1

    likely_sections = [section for section, _ in topic_counts.most_common()] or [
        requirement.handbook_section for requirement in list_requirements()
    ]

    topic_names = []
    for topic, keywords in TOPIC_KEYWORDS.items():
        if any(keyword in full_text for keyword in keywords):
            topic_names.append(topic)

    return DocumentProfile(
        project_type="rss_tender",
        rss_roles_present=roles,
        employment_admin_topics=topic_names,
        handbook_sections_likely_relevant=likely_sections,
    )


def select_requirements(
    profile: DocumentProfile,
    explicit_requirement_ids: list[str],
    tender_chunks: list[ChunkRecord],
) -> list[RequirementDefinition]:
    requirements = list_requirements(explicit_requirement_ids)
    if explicit_requirement_ids:
        return requirements

    full_text = "\n".join(chunk.text for chunk in tender_chunks).lower()
    selected = []
    likely_sections = set(profile.handbook_sections_likely_relevant)
    for requirement in requirements:
        trigger_match = any(trigger.lower() in full_text for trigger in requirement.trigger_conditions)
        section_match = requirement.handbook_section in likely_sections
        if trigger_match or section_match:
            selected.append(requirement)

    return selected or requirements


def evaluate_requirement(
    requirement: RequirementDefinition,
    tender_chunks: list[ChunkRecord],
    handbook_chunks: list[ChunkRecord],
    top_k: int,
) -> RequirementFinding:
    tender_hits = _search_requirement(requirement, tender_chunks, top_k)
    handbook_hits = _search_requirement(requirement, handbook_chunks, min(top_k, 3))

    tender_text = "\n".join(hit.text for hit in tender_hits).lower()
    matched_patterns = [
        pattern for pattern in requirement.expected_evidence_patterns if pattern.lower() in tender_text
    ]
    missing_patterns = [
        pattern for pattern in requirement.expected_evidence_patterns if pattern.lower() not in tender_text
    ]

    if not handbook_hits:
        return RequirementFinding(
            requirement_id=requirement.requirement_id,
            handbook_section=requirement.handbook_section,
            title=requirement.title,
            status="not_applicable",
            confidence="low",
            severity=requirement.severity,  # type: ignore[arg-type]
            tender_evidence=tender_hits,
            handbook_evidence=[],
            why="No supporting handbook evidence was available in the indexed corpus for this rule.",
            missing_elements=missing_patterns,
            suggested_fix=requirement.suggested_fix_template or None,
        )

    if not tender_hits:
        return RequirementFinding(
            requirement_id=requirement.requirement_id,
            handbook_section=requirement.handbook_section,
            title=requirement.title,
            status="missing",
            confidence="medium",
            severity=requirement.severity,  # type: ignore[arg-type]
            tender_evidence=[],
            handbook_evidence=handbook_hits,
            why="No relevant tender clause was retrieved for this handbook requirement.",
            missing_elements=missing_patterns or requirement.expected_evidence_patterns,
            suggested_fix=requirement.suggested_fix_template or None,
        )

    coverage = len(matched_patterns) / max(len(requirement.expected_evidence_patterns), 1)
    top_score = tender_hits[0].score

    if coverage >= 0.6 or top_score >= 0.9:
        status = "compliant"
        confidence = "high" if coverage >= 0.75 or top_score >= 1.0 else "medium"
        why = "Tender clauses align strongly with the handbook requirement and include multiple expected signals."
    elif coverage > 0 or top_score >= 0.45:
        status = "partially_compliant"
        confidence = "medium" if coverage > 0 else "low"
        why = "Tender clauses partially align with the handbook requirement, but some expected details are missing."
    else:
        status = "missing"
        confidence = "low"
        why = "Retrieved clauses are weakly related and do not satisfy the expected handbook requirement details."

    return RequirementFinding(
        requirement_id=requirement.requirement_id,
        handbook_section=requirement.handbook_section,
        title=requirement.title,
        status=status,  # type: ignore[arg-type]
        confidence=confidence,  # type: ignore[arg-type]
        severity=requirement.severity,  # type: ignore[arg-type]
        tender_evidence=tender_hits,
        handbook_evidence=handbook_hits,
        why=why,
        missing_elements=missing_patterns,
        suggested_fix=None if status == "compliant" else requirement.suggested_fix_template or None,
    )


def detect_contradictions(tender_chunks: list[ChunkRecord]) -> list[ContradictionFinding]:
    contradictions: list[ContradictionFinding] = []
    for topic, keywords in TOPIC_KEYWORDS.items():
        topic_chunks = [
            chunk
            for chunk in tender_chunks
            if any(keyword in chunk.text.lower() for keyword in keywords)
        ]
        if len(topic_chunks) < 2:
            continue

        markers_to_chunks: defaultdict[str, list[ChunkRecord]] = defaultdict(list)
        for chunk in topic_chunks:
            for marker in _extract_time_markers(chunk.text):
                markers_to_chunks[marker].append(chunk)

        if len(markers_to_chunks) > 1:
            evidence = []
            for marker_chunks in list(markers_to_chunks.values())[:2]:
                evidence.append(_to_evidence(marker_chunks[0], 1.0))
            contradictions.append(
                ContradictionFinding(
                    topic=topic,
                    severity="medium",
                    description=f"Multiple timing expressions were found for {topic.replace('_', ' ')}: {', '.join(sorted(markers_to_chunks))}.",
                    evidence=evidence,
                )
            )

    return contradictions


def build_summary(
    findings: list[RequirementFinding],
    contradictions: list[ContradictionFinding],
) -> TenderCheckSummary:
    compliant_count = sum(1 for item in findings if item.status == "compliant")
    partial_count = sum(1 for item in findings if item.status == "partially_compliant")
    missing_count = sum(1 for item in findings if item.status == "missing")
    low_confidence_count = sum(1 for item in findings if item.confidence == "low")
    high_risk_missing = [
        item.title
        for item in findings
        if item.status == "missing" and item.severity in {"high", "critical"}
    ]

    if contradictions or high_risk_missing:
        overall_status = "non_compliant"
    elif partial_count or missing_count:
        overall_status = "partially_compliant"
    elif low_confidence_count:
        overall_status = "needs_review"
    else:
        overall_status = "compliant"

    return TenderCheckSummary(
        overall_status=overall_status,  # type: ignore[arg-type]
        compliant_count=compliant_count,
        partial_count=partial_count,
        missing_count=missing_count,
        contradiction_count=len(contradictions),
        low_confidence_count=low_confidence_count,
        high_risk_missing_items=high_risk_missing,
    )


def _search_requirement(
    requirement: RequirementDefinition,
    chunks: list[ChunkRecord],
    top_k: int,
) -> list[EvidenceQuote]:
    query = " ".join(
        part
        for part in [
            requirement.retrieval_query,
            requirement.requirement_text,
            " ".join(requirement.expected_evidence_patterns),
        ]
        if part
    )
    scored = score_query_against_chunks(query, chunks)[:top_k]
    return [_to_evidence(chunk, score) for chunk, score in scored]


def _to_evidence(chunk: ChunkRecord, score: float) -> EvidenceQuote:
    return EvidenceQuote(
        document_id=chunk.document_id,
        chunk_id=chunk.chunk_id,
        score=round(score, 4),
        page=chunk.page,
        section_label=chunk.section_label,
        heading_path=chunk.heading_path,
        text=chunk.text,
    )


def _extract_time_markers(text: str) -> set[str]:
    found: set[str] = set()
    for pattern in TIME_PATTERNS:
        for match in pattern.findall(text):
            found.add(match.lower())
    return found


def _resolve_handbook_version(handbook_records: list[DocumentRecord]) -> str | None:
    versions = [record.source_version for record in handbook_records if record.source_version]
    if versions:
        return versions[0]
    if handbook_records:
        return handbook_records[0].filename
    return None
