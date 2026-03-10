from __future__ import annotations

import logging
from datetime import datetime, timezone
from uuid import uuid4

from fastapi import Depends, FastAPI, File, Form, HTTPException, UploadFile, status
from fastapi import Query

from .auth import require_scope
from .config import get_settings
from .extractors import build_chunks, extract_text, score_query_against_chunks
from .rag_adapter import LightRAGAdapter
from .schemas import (
    CompareRequest,
    CompareResponse,
    DocumentRecord,
    KnowledgeGraphEdge,
    KnowledgeGraphNode,
    KnowledgeGraphResponse,
    RequestScope,
    SearchHit,
    SearchRequest,
    SearchResponse,
    TenderCheckReport,
    TenderCheckRequest,
)
from .store import WorkspaceStore
from .tender_check import generate_report


logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

settings = get_settings()
store = WorkspaceStore()
rag = LightRAGAdapter()
app = FastAPI(title="Trinity LightRAG Sidecar", version="0.1.0")


@app.get("/health")
async def health():
    return {
        "status": "ok",
        "service": settings.service_name,
        "lightrag_configured": rag.is_configured(),
        "data_dir": str(settings.data_dir),
    }


@app.post("/documents", response_model=DocumentRecord)
async def create_document(
    file: UploadFile = File(...),
    document_type: str = Form(default="other"),
    source_version: str | None = Form(default=None),
    document_id: str | None = Form(default=None),
    scope: RequestScope = Depends(require_scope),
):
    content = await file.read()
    if not content:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="Uploaded file is empty")

    document_id = document_id or str(uuid4())
    now = datetime.now(timezone.utc)
    source_path = store.save_source(scope.workspace_id, document_id, file.filename, content)
    record = DocumentRecord(
        document_id=document_id,
        tenant_id=scope.tenant_id,
        workspace_id=scope.workspace_id,
        user_id=scope.user_id,
        openclaw_id=scope.openclaw_id,
        document_type=document_type if document_type in {"tender", "handbook", "other"} else "other",
        filename=file.filename,
        content_type=file.content_type,
        source_version=source_version,
        created_at=now,
        updated_at=now,
        status="uploaded",
        source_path=str(source_path),
    )
    return store.save_document(record)


@app.post("/documents/{document_id}/ingest", response_model=DocumentRecord)
async def ingest_document(
    document_id: str,
    scope: RequestScope = Depends(require_scope),
):
    record = _require_document(scope.workspace_id, document_id)
    if record.tenant_id != scope.tenant_id:
        raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="Document tenant mismatch")

    try:
        if not record.source_path:
            raise ValueError("Document source path is missing")

        content = store.document_dir(scope.workspace_id, document_id).joinpath(record.filename).read_bytes()
        extracted = extract_text(record.filename, content)
        chunks = build_chunks(document_id, scope.workspace_id, extracted)
        extracted_path = store.save_text(scope.workspace_id, document_id, extracted)
        chunks_path = store.save_chunks(scope.workspace_id, document_id, chunks)
        await rag.ingest(scope.workspace_id, extracted, document_id)
        return store.update_document(
            scope.workspace_id,
            document_id,
            status="indexed",
            error=None,
            extracted_text_path=str(extracted_path),
            chunks_path=str(chunks_path),
            chunk_count=len(chunks),
        )
    except Exception as exc:
        logger.exception("Failed to ingest document %s", document_id)
        return store.update_document(
            scope.workspace_id,
            document_id,
            status="failed",
            error=str(exc),
        )


@app.get("/documents/{document_id}/status", response_model=DocumentRecord)
async def document_status(
    document_id: str,
    scope: RequestScope = Depends(require_scope),
):
    record = _require_document(scope.workspace_id, document_id)
    _ensure_tenant(scope, record)
    return record


@app.get("/documents/{document_id}/chunks")
async def document_chunks(
    document_id: str,
    scope: RequestScope = Depends(require_scope),
):
    record = _require_document(scope.workspace_id, document_id)
    _ensure_tenant(scope, record)
    chunks = store.load_chunks(scope.workspace_id, document_id)
    return {
        "document_id": document_id,
        "workspace_id": scope.workspace_id,
        "chunks": [chunk.model_dump() for chunk in chunks],
    }


@app.get("/knowledge/graph", response_model=KnowledgeGraphResponse)
async def knowledge_graph(
    scope: RequestScope = Depends(require_scope),
):
    documents = [
        document
        for document in store.list_documents(scope.workspace_id)
        if document.tenant_id == scope.tenant_id
        and (scope.openclaw_id is None or document.openclaw_id in {None, scope.openclaw_id})
    ]

    nodes: list[KnowledgeGraphNode] = [
        KnowledgeGraphNode(
            id=f"workspace:{scope.workspace_id}",
            label=scope.workspace_id,
            kind="workspace",
            metadata={
                "tenant_id": scope.tenant_id,
                "openclaw_id": scope.openclaw_id or "",
            },
        )
    ]
    edges: list[KnowledgeGraphEdge] = []

    for document in documents:
        document_node_id = f"document:{document.document_id}"
        nodes.append(
            KnowledgeGraphNode(
                id=document_node_id,
                label=document.filename,
                kind="document",
                parent_id=f"workspace:{scope.workspace_id}",
                metadata={
                    "document_id": document.document_id,
                    "document_type": document.document_type,
                    "status": document.status,
                },
            )
        )
        edges.append(
            KnowledgeGraphEdge(
                source=f"workspace:{scope.workspace_id}",
                target=document_node_id,
                kind="contains",
            )
        )

        chunks = store.load_chunks(scope.workspace_id, document.document_id)[:12]
        for chunk in chunks:
            chunk_node_id = f"chunk:{chunk.chunk_id}"
            nodes.append(
                KnowledgeGraphNode(
                    id=chunk_node_id,
                    label=(chunk.section_label or chunk.heading_path[0]) if (chunk.section_label or chunk.heading_path) else f"chunk {chunk.index + 1}",
                    kind="chunk",
                    parent_id=document_node_id,
                    metadata={
                        "chunk_id": chunk.chunk_id,
                        "preview": chunk.text[:180],
                    },
                )
            )
            edges.append(
                KnowledgeGraphEdge(
                    source=document_node_id,
                    target=chunk_node_id,
                    kind="contains",
                )
            )

    workspace_runs = []
    runs_dir = store.runs_dir(scope.workspace_id)
    for path in sorted(runs_dir.glob("*.json")):
        report = store.load_run_report(scope.workspace_id, path.stem)
        if report is None or report.tenant_id != scope.tenant_id:
            continue
        workspace_runs.append(report)

    for report in workspace_runs[:10]:
        run_node_id = f"run:{report.run_id}"
        nodes.append(
            KnowledgeGraphNode(
                id=run_node_id,
                label=f"run {report.run_id[:8]}",
                kind="run",
                parent_id=f"document:{report.document_id}",
                metadata={
                    "overall_status": report.summary.overall_status,
                    "contradictions": str(report.summary.contradiction_count),
                },
            )
        )
        edges.append(
            KnowledgeGraphEdge(
                source=f"document:{report.document_id}",
                target=run_node_id,
                kind="generated",
            )
        )

    return KnowledgeGraphResponse(
        tenant_id=scope.tenant_id,
        workspace_id=scope.workspace_id,
        openclaw_id=scope.openclaw_id,
        nodes=nodes,
        edges=edges,
    )


@app.get("/graph/label/list")
async def graph_label_list(
    scope: RequestScope = Depends(require_scope),
):
    return await rag.get_graph_labels(scope.workspace_id)


@app.get("/graph/label/popular")
async def graph_label_popular(
    limit: int = Query(default=300, ge=1, le=1000),
    scope: RequestScope = Depends(require_scope),
):
    return await rag.get_popular_labels(scope.workspace_id, limit)


@app.get("/graph/label/search")
async def graph_label_search(
    q: str = Query(..., min_length=1),
    limit: int = Query(default=50, ge=1, le=100),
    scope: RequestScope = Depends(require_scope),
):
    return await rag.search_labels(scope.workspace_id, q, limit)


@app.get("/graphs")
async def official_knowledge_graph(
    label: str = Query(..., min_length=1),
    max_depth: int = Query(default=3, ge=1),
    max_nodes: int = Query(default=1000, ge=1),
    scope: RequestScope = Depends(require_scope),
):
    return await rag.get_knowledge_graph(
        scope.workspace_id,
        label=label,
        max_depth=max_depth,
        max_nodes=max_nodes,
    )


@app.post("/retrieval/search", response_model=SearchResponse)
async def retrieval_search(
    request: SearchRequest,
    scope: RequestScope = Depends(require_scope),
):
    if request.workspace_id != scope.workspace_id:
        raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="Workspace mismatch")

    chunks = []
    document_ids = request.document_ids or [doc.document_id for doc in store.list_documents(scope.workspace_id)]
    for document_id in document_ids:
        record = store.load_document(scope.workspace_id, document_id)
        if record is None:
            continue
        _ensure_tenant(scope, record)
        chunks.extend(store.load_chunks(scope.workspace_id, document_id))

    scored = score_query_against_chunks(request.query, chunks)[: request.top_k]
    hits = [
        SearchHit(
            document_id=chunk.document_id,
            chunk_id=chunk.chunk_id,
            score=round(score, 4),
            page=chunk.page,
            section_label=chunk.section_label,
            heading_path=chunk.heading_path,
            text=chunk.text,
        )
        for chunk, score in scored
    ]
    lightrag_response, retrieval_context = await rag.query(
        scope.workspace_id,
        request.query,
        request.mode,
        request.top_k,
        request.response_type,
    )
    return SearchResponse(
        workspace_id=scope.workspace_id,
        query=request.query,
        mode=request.mode,
        hits=hits,
        lightrag_response=lightrag_response,
        retrieval_context=retrieval_context,
    )


@app.post("/retrieval/compare", response_model=CompareResponse)
async def retrieval_compare(
    request: CompareRequest,
    scope: RequestScope = Depends(require_scope),
):
    left_scope = RequestScope(
        tenant_id=scope.tenant_id,
        workspace_id=request.left.workspace_id,
        user_id=scope.user_id,
    )
    right_scope = RequestScope(
        tenant_id=scope.tenant_id,
        workspace_id=request.right.workspace_id,
        user_id=scope.user_id,
    )
    left = await _search_single_document(request.query, request.mode, request.top_k, request.left.document_id, left_scope)
    right = await _search_single_document(request.query, request.mode, request.top_k, request.right.document_id, right_scope)
    return CompareResponse(query=request.query, mode=request.mode, left=left, right=right)


@app.post("/tender-check/runs", response_model=TenderCheckReport)
async def tender_check_run(
    request: TenderCheckRequest,
    scope: RequestScope = Depends(require_scope),
):
    if request.workspace_id != scope.workspace_id:
        raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="Workspace mismatch")

    tender_record = _require_document(scope.workspace_id, request.tender_document_id)
    _ensure_tenant(scope, tender_record)
    if tender_record.status != "indexed":
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Tender document must be indexed before tender-check runs",
        )

    handbook_records = []
    for handbook_document_id in request.handbook_document_ids:
        handbook_record = _require_document(scope.workspace_id, handbook_document_id)
        _ensure_tenant(scope, handbook_record)
        if handbook_record.status != "indexed":
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail=f"Handbook document {handbook_document_id} must be indexed before tender-check runs",
            )
        handbook_records.append(handbook_record)

    if not handbook_records:
        handbook_records = [
            document
            for document in store.list_documents(scope.workspace_id)
            if document.document_type == "handbook" and document.status == "indexed"
        ]

    if not handbook_records:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="No indexed handbook documents are available for tender-check",
        )

    tender_chunks = store.load_chunks(scope.workspace_id, request.tender_document_id)
    handbook_chunks = []
    for handbook_record in handbook_records:
        handbook_chunks.extend(store.load_chunks(scope.workspace_id, handbook_record.document_id))

    report = generate_report(
        request=request,
        tenant_id=scope.tenant_id,
        tender_record=tender_record,
        handbook_records=handbook_records,
        tender_chunks=tender_chunks,
        handbook_chunks=handbook_chunks,
    )
    store.save_run_report(report)
    return report


@app.get("/tender-check/runs/{run_id}", response_model=TenderCheckReport)
async def tender_check_run_status(
    run_id: str,
    scope: RequestScope = Depends(require_scope),
):
    report = store.load_run_report(scope.workspace_id, run_id)
    if report is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Run not found")
    if report.tenant_id != scope.tenant_id:
        raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="Tenant mismatch")
    return report


@app.get("/tender-check/runs/{run_id}/report", response_model=TenderCheckReport)
async def tender_check_run_report(
    run_id: str,
    scope: RequestScope = Depends(require_scope),
):
    report = store.load_run_report(scope.workspace_id, run_id)
    if report is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Run not found")
    if report.tenant_id != scope.tenant_id:
        raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="Tenant mismatch")
    return report


async def _search_single_document(
    query: str,
    mode: str,
    top_k: int,
    document_id: str,
    scope: RequestScope,
) -> SearchResponse:
    record = _require_document(scope.workspace_id, document_id)
    _ensure_tenant(scope, record)
    chunks = store.load_chunks(scope.workspace_id, document_id)
    scored = score_query_against_chunks(query, chunks)[:top_k]
    hits = [
        SearchHit(
            document_id=chunk.document_id,
            chunk_id=chunk.chunk_id,
            score=round(score, 4),
            page=chunk.page,
            section_label=chunk.section_label,
            heading_path=chunk.heading_path,
            text=chunk.text,
        )
        for chunk, score in scored
    ]
    lightrag_response, retrieval_context = await rag.query(
        scope.workspace_id,
        query,
        mode,
        top_k,
        "Bullet Points",
    )
    return SearchResponse(
        workspace_id=scope.workspace_id,
        query=query,
        mode=mode,
        hits=hits,
        lightrag_response=lightrag_response,
        retrieval_context=retrieval_context,
    )


def _require_document(workspace_id: str, document_id: str) -> DocumentRecord:
    record = store.load_document(workspace_id, document_id)
    if record is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Document not found")
    return record


def _ensure_tenant(scope: RequestScope, record: DocumentRecord) -> None:
    if record.tenant_id != scope.tenant_id:
        raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="Tenant mismatch")
