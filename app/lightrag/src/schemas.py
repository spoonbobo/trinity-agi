from __future__ import annotations

from datetime import datetime
from typing import Literal

from pydantic import BaseModel, Field


class RequestScope(BaseModel):
    tenant_id: str
    workspace_id: str
    user_id: str
    openclaw_id: str | None = None


class DocumentRecord(BaseModel):
    document_id: str
    tenant_id: str
    workspace_id: str
    user_id: str
    openclaw_id: str | None = None
    document_type: Literal["tender", "handbook", "other"] = "other"
    filename: str
    content_type: str | None = None
    source_version: str | None = None
    created_at: datetime
    updated_at: datetime
    status: Literal["uploaded", "indexed", "failed"] = "uploaded"
    error: str | None = None
    extracted_text_path: str | None = None
    chunks_path: str | None = None
    source_path: str | None = None
    chunk_count: int = 0


class ChunkRecord(BaseModel):
    chunk_id: str
    document_id: str
    workspace_id: str
    index: int
    heading_path: list[str] = Field(default_factory=list)
    page: int | None = None
    section_label: str | None = None
    text: str


class SearchRequest(BaseModel):
    query: str
    workspace_id: str
    document_ids: list[str] = Field(default_factory=list)
    mode: Literal["local", "global", "hybrid", "naive", "mix", "bypass"] = "hybrid"
    top_k: int = 8
    response_type: str = "Bullet Points"


class SearchHit(BaseModel):
    document_id: str
    chunk_id: str
    score: float
    page: int | None = None
    section_label: str | None = None
    heading_path: list[str] = Field(default_factory=list)
    text: str


class SearchResponse(BaseModel):
    workspace_id: str
    query: str
    mode: str
    hits: list[SearchHit]
    lightrag_response: str | None = None
    retrieval_context: str | None = None


class DocumentRef(BaseModel):
    workspace_id: str
    document_id: str


class CompareRequest(BaseModel):
    query: str
    left: DocumentRef
    right: DocumentRef
    mode: Literal["local", "global", "hybrid", "naive", "mix", "bypass"] = "hybrid"
    top_k: int = 5


class CompareResponse(BaseModel):
    query: str
    mode: str
    left: SearchResponse
    right: SearchResponse


class TenderCheckRequest(BaseModel):
    workspace_id: str
    tender_document_id: str
    handbook_document_ids: list[str] = Field(default_factory=list)
    requirement_ids: list[str] = Field(default_factory=list)
    top_k: int = 5
    retrieval_mode: Literal["local", "global", "hybrid", "naive", "mix", "bypass"] = "hybrid"


class DocumentProfile(BaseModel):
    project_type: str = "rss_tender"
    rss_roles_present: list[str] = Field(default_factory=list)
    employment_admin_topics: list[str] = Field(default_factory=list)
    handbook_sections_likely_relevant: list[str] = Field(default_factory=list)


class EvidenceQuote(BaseModel):
    document_id: str
    chunk_id: str
    score: float
    page: int | None = None
    section_label: str | None = None
    heading_path: list[str] = Field(default_factory=list)
    text: str


class RequirementFinding(BaseModel):
    requirement_id: str
    handbook_section: str
    title: str
    status: Literal["compliant", "partially_compliant", "missing", "contradictory", "not_applicable"]
    confidence: Literal["high", "medium", "low"]
    severity: Literal["low", "medium", "high", "critical"]
    tender_evidence: list[EvidenceQuote] = Field(default_factory=list)
    handbook_evidence: list[EvidenceQuote] = Field(default_factory=list)
    why: str
    missing_elements: list[str] = Field(default_factory=list)
    suggested_fix: str | None = None


class ContradictionFinding(BaseModel):
    topic: str
    severity: Literal["low", "medium", "high", "critical"]
    description: str
    evidence: list[EvidenceQuote] = Field(default_factory=list)


class TenderCheckSummary(BaseModel):
    overall_status: Literal["compliant", "partially_compliant", "non_compliant", "needs_review"]
    compliant_count: int = 0
    partial_count: int = 0
    missing_count: int = 0
    contradiction_count: int = 0
    low_confidence_count: int = 0
    high_risk_missing_items: list[str] = Field(default_factory=list)


class TenderCheckAudit(BaseModel):
    retrieval_mode: str
    handbook_version: str | None = None
    generated_at: datetime


class TenderCheckReport(BaseModel):
    run_id: str
    tenant_id: str
    workspace_id: str
    openclaw_id: str | None = None
    document_id: str
    handbook_version: str | None = None
    document_profile: DocumentProfile
    summary: TenderCheckSummary
    requirements: list[RequirementFinding]
    contradictions: list[ContradictionFinding]
    audit: TenderCheckAudit


class KnowledgeGraphNode(BaseModel):
    id: str
    label: str
    kind: Literal["workspace", "document", "chunk", "run"]
    parent_id: str | None = None
    metadata: dict[str, str] = Field(default_factory=dict)


class KnowledgeGraphEdge(BaseModel):
    source: str
    target: str
    kind: Literal["contains", "generated"]


class KnowledgeGraphResponse(BaseModel):
    tenant_id: str
    workspace_id: str
    openclaw_id: str | None = None
    nodes: list[KnowledgeGraphNode]
    edges: list[KnowledgeGraphEdge]
