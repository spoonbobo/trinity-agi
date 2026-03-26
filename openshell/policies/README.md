# Sandbox Policies & Provider Migration

## Policies

OpenShell sandbox policies define what each user's sandbox can access.
Policies are YAML files evaluated by OPA (Open Policy Agent) and enforce:

- **Filesystem**: read-only vs read-write paths (Landlock kernel enforcement)
- **Network**: per-binary allowed egress destinations
- **Process**: user/group isolation

### Policy tiers (mapped to Trinity RBAC roles)

| Trinity Role | Policy file | Network access |
|---|---|---|
| guest | `user-default.yaml` | OpenClaw core + web tools only |
| user | `user-default.yaml` | Same as guest (LLM keys injected via Provider) |
| admin | `admin.yaml` | Full LLM providers + GitHub + messaging channels |
| superadmin | `admin.yaml` | Same as admin |

### Applying policies

```bash
# At sandbox creation
openshell sandbox create --name openclaw-<userId> \
  --from trinity-openclaw-sandbox:latest \
  --policy openshell/policies/user-default.yaml

# Hot-reload on a running sandbox (no restart needed)
openshell policy set openclaw-<userId> \
  --policy openshell/policies/admin.yaml
```

## Provider Migration

Trinity currently injects LLM API keys via environment variables in the pod
spec. OpenShell's Provider system offers better isolation.

### Current flow

```
.env -> docker-compose env_file -> pod spec -> container env vars
```

All secrets visible via `docker inspect` or `kubectl get pod -o yaml`.

### OpenShell Provider flow

```
openshell provider create -> gateway encrypted storage -> runtime injection
```

Secrets never appear in pod specs. Injected at runtime by the sandbox
supervisor.

### Migration steps

1. Create providers for each credential type:

```bash
# LLM provider keys
openshell provider create --type openai --from-existing
openshell provider create --type anthropic --from-existing

# GitHub access
openshell provider create --type github --from-existing
```

2. Configure inference routing:

```bash
openshell cluster inference set --provider openai --model gpt-4o
```

3. Sandboxes automatically receive credentials at startup via the Provider
   system. No env vars needed in the pod spec.
