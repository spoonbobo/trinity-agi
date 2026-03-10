from __future__ import annotations

import re


_INVALID_CHARS = re.compile(r"[^a-z0-9]+")


def normalize_workspace_part(value: str) -> str:
    normalized = _INVALID_CHARS.sub("-", value.strip().lower()).strip("-")
    return normalized or "default"


def build_claw_workspace_id(tenant_id: str, openclaw_id: str, suffix: str | None = None) -> str:
    tenant = normalize_workspace_part(tenant_id)
    claw = normalize_workspace_part(openclaw_id)
    workspace = f"tenant_{tenant}__claw_{claw}"
    if suffix:
        workspace = f"{workspace}__{normalize_workspace_part(suffix)}"
    return workspace
