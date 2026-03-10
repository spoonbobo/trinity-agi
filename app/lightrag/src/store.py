from __future__ import annotations

import json
from datetime import datetime, timezone
from pathlib import Path

from .config import get_settings
from .schemas import ChunkRecord, DocumentRecord, TenderCheckReport


class WorkspaceStore:
    def __init__(self) -> None:
        settings = get_settings()
        self.root = settings.data_dir / "workspaces"
        self.root.mkdir(parents=True, exist_ok=True)

    def workspace_dir(self, workspace_id: str) -> Path:
        path = self.root / workspace_id
        path.mkdir(parents=True, exist_ok=True)
        return path

    def documents_dir(self, workspace_id: str) -> Path:
        path = self.workspace_dir(workspace_id) / "documents"
        path.mkdir(parents=True, exist_ok=True)
        return path

    def runs_dir(self, workspace_id: str) -> Path:
        path = self.workspace_dir(workspace_id) / "runs"
        path.mkdir(parents=True, exist_ok=True)
        return path

    def document_dir(self, workspace_id: str, document_id: str) -> Path:
        path = self.documents_dir(workspace_id) / document_id
        path.mkdir(parents=True, exist_ok=True)
        return path

    def save_source(self, workspace_id: str, document_id: str, filename: str, content: bytes) -> Path:
        path = self.document_dir(workspace_id, document_id) / filename
        path.write_bytes(content)
        return path

    def save_text(self, workspace_id: str, document_id: str, text: str) -> Path:
        path = self.document_dir(workspace_id, document_id) / "extracted.txt"
        path.write_text(text, encoding="utf-8")
        return path

    def save_chunks(self, workspace_id: str, document_id: str, chunks: list[ChunkRecord]) -> Path:
        path = self.document_dir(workspace_id, document_id) / "chunks.json"
        path.write_text(
            json.dumps([chunk.model_dump() for chunk in chunks], ensure_ascii=False, indent=2),
            encoding="utf-8",
        )
        return path

    def load_chunks(self, workspace_id: str, document_id: str) -> list[ChunkRecord]:
        path = self.document_dir(workspace_id, document_id) / "chunks.json"
        if not path.exists():
            return []
        data = json.loads(path.read_text(encoding="utf-8"))
        return [ChunkRecord.model_validate(item) for item in data]

    def save_document(self, record: DocumentRecord) -> DocumentRecord:
        path = self.document_dir(record.workspace_id, record.document_id) / "metadata.json"
        path.write_text(
            json.dumps(record.model_dump(mode="json"), ensure_ascii=False, indent=2),
            encoding="utf-8",
        )
        return record

    def load_document(self, workspace_id: str, document_id: str) -> DocumentRecord | None:
        path = self.document_dir(workspace_id, document_id) / "metadata.json"
        if not path.exists():
            return None
        return DocumentRecord.model_validate_json(path.read_text(encoding="utf-8"))

    def update_document(self, workspace_id: str, document_id: str, **updates) -> DocumentRecord:
        current = self.load_document(workspace_id, document_id)
        if current is None:
            raise FileNotFoundError(f"Document {document_id} not found")
        merged = current.model_copy(
            update={
                **updates,
                "updated_at": datetime.now(timezone.utc),
            }
        )
        return self.save_document(merged)

    def list_documents(self, workspace_id: str) -> list[DocumentRecord]:
        items: list[DocumentRecord] = []
        for path in self.documents_dir(workspace_id).glob("*/metadata.json"):
            items.append(DocumentRecord.model_validate_json(path.read_text(encoding="utf-8")))
        return sorted(items, key=lambda item: item.created_at)

    def save_run_report(self, report: TenderCheckReport) -> Path:
        path = self.runs_dir(report.workspace_id) / f"{report.run_id}.json"
        path.write_text(
            json.dumps(report.model_dump(mode="json"), ensure_ascii=False, indent=2),
            encoding="utf-8",
        )
        return path

    def load_run_report(self, workspace_id: str, run_id: str) -> TenderCheckReport | None:
        path = self.runs_dir(workspace_id) / f"{run_id}.json"
        if not path.exists():
            return None
        return TenderCheckReport.model_validate_json(path.read_text(encoding="utf-8"))
