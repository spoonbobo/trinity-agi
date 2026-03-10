from __future__ import annotations

from io import BytesIO
from pathlib import Path
from typing import Iterable

from docx import Document as DocxDocument
from pypdf import PdfReader

from .config import get_settings
from .schemas import ChunkRecord


TEXT_EXTENSIONS = {".txt", ".md", ".markdown"}


def extract_text(filename: str, content: bytes) -> str:
    suffix = Path(filename).suffix.lower()
    if suffix in TEXT_EXTENSIONS:
        return content.decode("utf-8", errors="ignore")
    if suffix == ".pdf":
        reader = PdfReader(BytesIO(content))
        pages = [page.extract_text() or "" for page in reader.pages]
        return "\n\n".join(pages)
    if suffix == ".docx":
        doc = DocxDocument(BytesIO(content))
        paragraphs = [para.text.strip() for para in doc.paragraphs if para.text.strip()]
        return "\n\n".join(paragraphs)
    raise ValueError(f"Unsupported file type: {suffix or 'unknown'}")


def build_chunks(document_id: str, workspace_id: str, text: str) -> list[ChunkRecord]:
    settings = get_settings()
    paragraphs = [part.strip() for part in text.split("\n\n") if part.strip()]
    chunks: list[ChunkRecord] = []
    buffer = ""
    buffer_heading: list[str] = []
    def flush(index: int, chunk_text: str, heading_path: list[str]) -> None:
        if not chunk_text.strip():
            return
        chunks.append(
            ChunkRecord(
                chunk_id=f"{document_id}:chunk:{index}",
                document_id=document_id,
                workspace_id=workspace_id,
                index=index,
                heading_path=heading_path,
                text=chunk_text.strip(),
            )
        )

    chunk_size = max(settings.chunk_char_size, 400)
    overlap = max(min(settings.chunk_char_overlap, chunk_size // 2), 0)

    for paragraph in paragraphs:
        if _looks_like_heading(paragraph):
            buffer_heading = [paragraph]

        addition = f"{paragraph}\n\n"
        if len(buffer) + len(addition) <= chunk_size:
            buffer += addition
            continue

        flush(len(chunks), buffer, buffer_heading)
        if overlap and buffer:
            buffer = buffer[-overlap:] + addition
        else:
            buffer = addition

    flush(len(chunks), buffer, buffer_heading)
    return chunks


def _looks_like_heading(value: str) -> bool:
    if len(value) > 120:
        return False
    if value.endswith(":"):
        return True
    upper_ratio = sum(1 for ch in value if ch.isupper()) / max(len(value), 1)
    return upper_ratio > 0.55


def tokenize(value: str) -> list[str]:
    cleaned = "".join(ch.lower() if ch.isalnum() else " " for ch in value)
    return [token for token in cleaned.split() if token]


def score_query_against_chunks(query: str, chunks: Iterable[ChunkRecord]) -> list[tuple[ChunkRecord, float]]:
    query_tokens = set(tokenize(query))
    if not query_tokens:
        return []

    scored: list[tuple[ChunkRecord, float]] = []
    for chunk in chunks:
        tokens = tokenize(chunk.text)
        if not tokens:
            continue
        token_set = set(tokens)
        overlap = len(query_tokens & token_set)
        density = overlap / len(query_tokens)
        exact_bonus = 0.2 if query.lower() in chunk.text.lower() else 0.0
        score = density + exact_bonus
        if score > 0:
            scored.append((chunk, score))

    scored.sort(key=lambda item: item[1], reverse=True)
    return scored
