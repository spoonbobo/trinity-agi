from fastapi import Header, HTTPException, status

from .config import get_settings
from .schemas import RequestScope
from .workspace import build_claw_workspace_id


def require_scope(
    authorization: str | None = Header(default=None),
    x_trinity_tenant: str | None = Header(default=None),
    x_trinity_workspace: str | None = Header(default=None),
    x_trinity_user: str | None = Header(default=None),
    x_trinity_openclaw: str | None = Header(default=None),
) -> RequestScope:
    settings = get_settings()
    expected = settings.internal_token.strip()
    if not expected:
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail="LIGHTRAG_INTERNAL_TOKEN is not configured",
        )

    if not authorization or not authorization.startswith("Bearer "):
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Missing bearer token",
        )

    token = authorization.removeprefix("Bearer ").strip()
    if token != expected:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Invalid internal token",
        )

    if not x_trinity_tenant or not x_trinity_user:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Missing Trinity tenant or user headers",
        )

    derived_workspace = None
    if x_trinity_openclaw:
        derived_workspace = build_claw_workspace_id(x_trinity_tenant, x_trinity_openclaw)

    if derived_workspace and x_trinity_workspace and x_trinity_workspace != derived_workspace:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Workspace does not match derived claw workspace",
        )

    effective_workspace = derived_workspace or x_trinity_workspace
    if not effective_workspace:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Missing Trinity workspace or openclaw headers",
        )

    return RequestScope(
        tenant_id=x_trinity_tenant,
        workspace_id=effective_workspace,
        user_id=x_trinity_user,
        openclaw_id=x_trinity_openclaw,
    )
