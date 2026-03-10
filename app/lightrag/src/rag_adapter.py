from __future__ import annotations

import asyncio
import logging
from functools import partial
from typing import Any

from .config import get_settings

logger = logging.getLogger(__name__)

try:
    from lightrag import LightRAG, QueryParam
    from lightrag.llm.openai import openai_complete_if_cache, openai_embed
    from lightrag.utils import EmbeddingFunc
except Exception:  # pragma: no cover - soft dependency guard
    LightRAG = None
    QueryParam = None
    openai_complete_if_cache = None
    openai_embed = None
    EmbeddingFunc = None


class LightRAGAdapter:
    def __init__(self) -> None:
        self.settings = get_settings()
        self._instances: dict[str, Any] = {}
        self._locks: dict[str, asyncio.Lock] = {}

    def is_configured(self) -> bool:
        return (
            LightRAG is not None
            and QueryParam is not None
            and bool(self._llm_api_key())
            and bool(self._embedding_api_key())
        )

    async def ensure_workspace(self, workspace_id: str):
        if not self.is_configured():
            return None
        if workspace_id in self._instances:
            return self._instances[workspace_id]

        lock = self._locks.setdefault(workspace_id, asyncio.Lock())
        async with lock:
            if workspace_id in self._instances:
                return self._instances[workspace_id]

            working_dir = self.settings.data_dir / "rag" / workspace_id
            working_dir.mkdir(parents=True, exist_ok=True)

            async def llm_model_func(
                prompt,
                system_prompt=None,
                history_messages=None,
                keyword_extraction=False,
                **kwargs,
            ) -> str:
                return await openai_complete_if_cache(
                    self.settings.llm_model,
                    prompt,
                    system_prompt=system_prompt,
                    history_messages=history_messages or [],
                    keyword_extraction=keyword_extraction,
                    api_key=self._llm_api_key(),
                    base_url=self._llm_base_url(),
                    **kwargs,
                )

            embedding_func = EmbeddingFunc(
                embedding_dim=self.settings.embedding_dim,
                max_token_size=self.settings.embedding_max_tokens,
                model_name=self.settings.embedding_model,
                func=partial(
                    openai_embed.func,
                    model=self.settings.embedding_model,
                    api_key=self._embedding_api_key(),
                    base_url=self._embedding_base_url(),
                ),
            )

            rag = LightRAG(
                working_dir=str(working_dir),
                workspace=workspace_id,
                llm_model_func=llm_model_func,
                llm_model_name=self.settings.llm_model,
                embedding_func=embedding_func,
                max_parallel_insert=self.settings.max_parallel_insert,
            )
            await rag.initialize_storages()
            self._instances[workspace_id] = rag
            return rag

    async def ingest(self, workspace_id: str, text: str, document_id: str) -> None:
        rag = await self.ensure_workspace(workspace_id)
        if rag is None:
            return

        try:
            if hasattr(rag, "ainsert"):
                await rag.ainsert(text, ids=[document_id])
            else:
                await asyncio.to_thread(rag.insert, text, ids=[document_id])
        except TypeError:
            if hasattr(rag, "ainsert"):
                await rag.ainsert(text)
            else:
                await asyncio.to_thread(rag.insert, text)

    async def query(
        self,
        workspace_id: str,
        query: str,
        mode: str,
        top_k: int,
        response_type: str,
    ) -> tuple[str | None, str | None]:
        rag = await self.ensure_workspace(workspace_id)
        if rag is None:
            return None, None

        param = QueryParam(
            mode=mode,
            top_k=max(top_k, 5),
            chunk_top_k=top_k,
            response_type=response_type,
            enable_rerank=self.settings.enable_rerank,
        )
        context_param = QueryParam(
            mode=mode,
            top_k=max(top_k, 5),
            chunk_top_k=top_k,
            only_need_context=True,
            enable_rerank=self.settings.enable_rerank,
        )

        response = await self._call_query(rag, query, param)
        context = await self._call_query(rag, query, context_param)
        return self._stringify(response), self._stringify(context)

    async def _call_query(self, rag, query: str, param):
        if hasattr(rag, "aquery"):
            return await rag.aquery(query, param=param)
        return await asyncio.to_thread(rag.query, query, param)

    def _stringify(self, value: Any) -> str | None:
        if value is None:
            return None
        if isinstance(value, str):
            return value
        if hasattr(value, "response"):
            return str(value.response)
        return str(value)

    async def get_graph_labels(self, workspace_id: str):
        rag = await self.ensure_workspace(workspace_id)
        if rag is None:
            return []
        return await rag.get_graph_labels()

    async def get_popular_labels(self, workspace_id: str, limit: int = 300):
        rag = await self.ensure_workspace(workspace_id)
        if rag is None:
            return []
        return await rag.chunk_entity_relation_graph.get_popular_labels(limit)

    async def search_labels(self, workspace_id: str, query: str, limit: int = 50):
        rag = await self.ensure_workspace(workspace_id)
        if rag is None:
            return []
        return await rag.chunk_entity_relation_graph.search_labels(query, limit)

    async def get_knowledge_graph(
        self,
        workspace_id: str,
        label: str,
        max_depth: int = 3,
        max_nodes: int = 1000,
    ):
        rag = await self.ensure_workspace(workspace_id)
        if rag is None:
            return {"nodes": [], "edges": []}
        return await rag.get_knowledge_graph(
            node_label=label,
            max_depth=max_depth,
            max_nodes=max_nodes,
        )

    def _llm_api_key(self) -> str:
        return self.settings.llm_api_key or self.settings.openai_api_key

    def _llm_base_url(self) -> str | None:
        return self.settings.llm_base_url or self.settings.openai_base_url or None

    def _embedding_api_key(self) -> str:
        return self.settings.embedding_api_key or self.settings.openai_api_key

    def _embedding_base_url(self) -> str | None:
        return self.settings.embedding_base_url or self.settings.openai_base_url or None
