from functools import lru_cache
from pathlib import Path

from pydantic import Field
from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    model_config = SettingsConfigDict(case_sensitive=False, extra="ignore")

    service_name: str = "trinity-lightrag"
    port: int = Field(default=18803, alias="LIGHTRAG_PORT")
    data_dir: Path = Field(default=Path("/data"), alias="LIGHTRAG_DATA_DIR")
    internal_token: str = Field(default="", alias="LIGHTRAG_INTERNAL_TOKEN")

    openai_api_key: str = Field(default="", alias="OPENAI_API_KEY")
    openai_base_url: str = Field(default="", alias="OPENAI_BASE_URL")
    llm_api_key: str = Field(default="", alias="LIGHTRAG_LLM_API_KEY")
    llm_base_url: str = Field(default="", alias="LIGHTRAG_LLM_BASE_URL")
    llm_model: str = Field(default="gpt-4o-mini", alias="LIGHTRAG_LLM_MODEL")
    embedding_api_key: str = Field(default="", alias="LIGHTRAG_EMBEDDING_API_KEY")
    embedding_base_url: str = Field(default="", alias="LIGHTRAG_EMBEDDING_BASE_URL")
    embedding_model: str = Field(
        default="text-embedding-3-large",
        alias="LIGHTRAG_EMBEDDING_MODEL",
    )
    embedding_dim: int = Field(default=3072, alias="LIGHTRAG_EMBEDDING_DIM")
    embedding_max_tokens: int = Field(
        default=8192,
        alias="LIGHTRAG_EMBEDDING_MAX_TOKENS",
    )

    default_query_mode: str = Field(default="hybrid", alias="LIGHTRAG_DEFAULT_QUERY_MODE")
    max_parallel_insert: int = Field(default=2, alias="LIGHTRAG_MAX_PARALLEL_INSERT")
    chunk_char_size: int = Field(default=1800, alias="LIGHTRAG_CHUNK_CHAR_SIZE")
    chunk_char_overlap: int = Field(default=200, alias="LIGHTRAG_CHUNK_CHAR_OVERLAP")
    enable_rerank: bool = Field(default=True, alias="LIGHTRAG_ENABLE_RERANK")


@lru_cache(maxsize=1)
def get_settings() -> Settings:
    settings = Settings()
    settings.data_dir.mkdir(parents=True, exist_ok=True)
    return settings
