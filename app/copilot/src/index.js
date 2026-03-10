import express from "express";
import cors from "cors";
import { spawn } from "node:child_process";
import { createOpencodeClient } from "@opencode-ai/sdk";

const PORT = parseInt(process.env.COPILOT_PORT || "18802", 10);
const OPENCODE_PORT = parseInt(process.env.OPENCODE_PORT || "4096", 10);
const AUTH_SERVICE_URL =
  process.env.AUTH_SERVICE_URL || "http://auth-service:18791";
const ALLOWED_ORIGINS = (process.env.ALLOWED_ORIGINS || "http://localhost")
  .split(",")
  .map((value) => value.trim())
  .filter(Boolean);
const WORKSPACE_DIR = process.env.COPILOT_WORKSPACE || "/workspace";
const ZEN_API_KEY = process.env.ZEN_API_KEY || "";
const DESIRED_DEFAULT_MODEL =
  process.env.COPILOT_DEFAULT_MODEL || "moonshotai/kimi-k2.5";
const ORCHESTRATOR_URL =
  process.env.ORCHESTRATOR_URL || "http://gateway-orchestrator:18801";
const ORCHESTRATOR_SERVICE_TOKEN =
  process.env.ORCHESTRATOR_SERVICE_TOKEN || "";
const COPILOT_PROMPT_TIMEOUT_MS = parseInt(
  process.env.COPILOT_PROMPT_TIMEOUT_MS || "120000",
  10,
);

process.chdir(WORKSPACE_DIR);
process.env.PATH = `/app/node_modules/.bin:${process.env.PATH || ""}`;

function unwrap(result) {
  return result?.data ?? result;
}

function textFromParts(parts = []) {
  return parts
    .filter((part) => part?.type === "text" && typeof part.text === "string")
    .map((part) => part.text)
    .join("\n\n")
    .trim();
}

function normalizeMessages(entries = []) {
  return entries
    .map((entry) => {
      const info = entry?.info ?? {};
      const parts = entry?.parts ?? [];
      const role =
        info.role ||
        info.type ||
        info.kind ||
        (info.userID ? "user" : "assistant");
      const content = textFromParts(parts);
      return {
        id: info.id || `${role}-${Math.random().toString(36).slice(2)}`,
        role,
        content,
        createdAt: info.createdAt || info.created_at || new Date().toISOString(),
      };
    })
    .filter((entry) => entry.content.length > 0)
    .filter((entry) => entry.role === "user" || entry.role === "assistant");
}

function buildMessagesPayload(entries = []) {
  return {
    messages: normalizeMessages(entries),
  };
}

function buildContext(user, selectedOpenClaw, openclawReachable) {
  const lines = [
    "You are Trinity Copilot, a superadmin-only assistant for the Trinity platform.",
    "You are running inside an OpenCode-backed copilot service.",
    "Prefer the project's available OpenCode config, AGENT/AGENTS guidance, skills, tools, and commands when the runtime supports them.",
    "Do not assume access beyond the authenticated superadmin's current allowed OpenClaw scope.",
  ];
  if (selectedOpenClaw) {
    lines.push(
      `Current selected OpenClaw: ${selectedOpenClaw.name} (${selectedOpenClaw.id}).`,
    );
    if (openclawReachable) {
      lines.push(
        "The user has an interactive PTY terminal side-by-side with this chat.",
        "Do not claim you executed commands unless the user pasted command output.",
        "Prefer giving exact `openclaw ...` commands for the user to run in PTY.",
        "Available openclaw CLI commands:",
        "  status, health [--json], skills list [--json], crons list [--json],",
        "  hooks list [--json], hooks check [--json], sessions [--json], logs,",
        "  channels, tools, memory, config get, config validate, doctor, models.",
        "Do not assume a channel is available just because docs mention it.",
        "For channel setup, first ask the user to run `openclaw channels capabilities --channel <name>` and inspect the result.",
        "When the user asks about live state (health/skills/channels/etc), provide the command(s) to run and then interpret results they share.",
        "Always add --json flag when available to get structured output.",
        "If WhatsApp channel is unsupported in this runtime, say so clearly and offer alternatives (for example `wacli` skill for history/send workflows, or upgrading to a runtime with WhatsApp Web channel support).",
      );
    } else {
      lines.push(
        "The OpenClaw backend could not be resolved. Operational commands are unavailable.",
        "Limit to guidance and advice only.",
      );
    }
  } else {
    lines.push(
      "No OpenClaw is currently selected. Ask the user to select one if a task depends on OpenClaw-specific context.",
    );
  }
  if (user?.email) {
    lines.push(`Authenticated superadmin: ${user.email}.`);
  }
  if (user?.role) {
    lines.push(`RBAC role: ${user.role}.`);
  }
  if (Array.isArray(user?.permissions) && user.permissions.length > 0) {
    lines.push(`Effective permissions: ${user.permissions.join(", ")}.`);
  }
  return lines.join("\n");
}

function withTimeout(promise, ms, label) {
  return Promise.race([
    promise,
    new Promise((_, reject) => {
      setTimeout(() => reject(new Error(`${label} timed out after ${ms}ms`)), ms);
    }),
  ]);
}

async function requireSuperadmin(req, res, next) {
  const authHeader = req.headers.authorization;
  if (!authHeader?.startsWith("Bearer ")) {
    return res.status(401).json({ error: "missing bearer token" });
  }

  try {
    const authResp = await fetch(`${AUTH_SERVICE_URL}/auth/me`, {
      headers: { Authorization: authHeader },
    });
    if (!authResp.ok) {
      return res.status(401).json({ error: "authentication failed" });
    }
    const user = await authResp.json();
    if (user.role !== "superadmin") {
      return res.status(403).json({ error: "superadmin access required" });
    }
    if (!Array.isArray(user.permissions)) {
      user.permissions = [];
    }
    req.authHeader = authHeader;
    req.user = user;
    next();
  } catch (error) {
    console.error("[copilot] auth error:", error);
    res.status(502).json({ error: "failed to verify superadmin access" });
  }
}

async function resolveSelectedOpenClaw(req, res, next) {
  const openclawId =
    req.headers["x-openclaw-id"] ||
    req.query.openclawId ||
    req.body?.openclawId ||
    null;

  if (!openclawId) {
    req.selectedOpenClaw = null;
    return next();
  }

  try {
    const openclawsResp = await fetch(`${AUTH_SERVICE_URL}/auth/openclaws`, {
      headers: { Authorization: req.authHeader },
    });
    if (!openclawsResp.ok) {
      return res
        .status(502)
        .json({ error: "failed to resolve accessible openclaws" });
    }
    const openclaws = await openclawsResp.json();
    const selected = (Array.isArray(openclaws) ? openclaws : []).find(
      (item) => item?.id === openclawId,
    );
    if (!selected) {
      return res
        .status(403)
        .json({ error: "selected openclaw is not accessible to this superadmin" });
    }
    req.selectedOpenClaw = selected;
    next();
  } catch (error) {
    console.error("[copilot] openclaw resolution error:", error);
    res.status(502).json({ error: "failed to validate selected openclaw" });
  }
}

const openclawBackendCache = new Map();

async function resolveOpenClawBackend(openclawId) {
  if (!ORCHESTRATOR_SERVICE_TOKEN) return null;
  const cached = openclawBackendCache.get(openclawId);
  if (cached && Date.now() - cached.ts < 60000) return cached.backend;

  try {
    const resp = await fetch(
      `${ORCHESTRATOR_URL}/openclaws/${openclawId}/resolve`,
      {
        headers: {
          Authorization: `Bearer ${ORCHESTRATOR_SERVICE_TOKEN}`,
          "Content-Type": "application/json",
        },
      },
    );
    if (!resp.ok) {
      console.error(`[copilot] orchestrator resolve failed: ${resp.status}`);
      return null;
    }
    const backend = await resp.json();
    openclawBackendCache.set(openclawId, { backend, ts: Date.now() });
    return backend;
  } catch (error) {
    console.error("[copilot] orchestrator resolve error:", error);
    return null;
  }
}

async function startOpencodeServer() {
  const args = [
    "serve",
    "--hostname=127.0.0.1",
    `--port=${OPENCODE_PORT}`,
    "--print-logs",
  ];
  const proc = spawn("opencode", args, {
    env: process.env,
    cwd: WORKSPACE_DIR,
  });

  const url = await new Promise((resolve, reject) => {
    const timeoutId = setTimeout(() => {
      reject(new Error("Timed out waiting for copilot OpenCode server"));
    }, 15000);

    let output = "";
    const onChunk = (chunk) => {
      output += chunk.toString();
      const lines = output.split("\n");
      for (const line of lines) {
        if (line.startsWith("opencode server listening")) {
          const match = line.match(/on\s+(https?:\/\/[^\s]+)/);
          if (match) {
            clearTimeout(timeoutId);
            resolve(match[1]);
            return;
          }
        }
      }
    };

    proc.stdout?.on("data", onChunk);
    proc.stderr?.on("data", onChunk);
    proc.on("exit", (code) => {
      clearTimeout(timeoutId);
      reject(new Error(`OpenCode server exited early with code ${code}`));
    });
    proc.on("error", (error) => {
      clearTimeout(timeoutId);
      reject(error);
    });
  });

  return {
    url,
    close() {
      proc.kill();
    },
  };
}

const opencodeServer = await startOpencodeServer();
const opencodeClient = createOpencodeClient({
  baseUrl: opencodeServer.url,
  directory: WORKSPACE_DIR,
});

if (ZEN_API_KEY) {
  try {
    await opencodeClient.auth.set({
      path: { id: "zen" },
      body: { type: "api", key: ZEN_API_KEY },
      query: { directory: WORKSPACE_DIR },
    });
    console.log("[copilot] configured zen provider auth");
  } catch (error) {
    console.error("[copilot] failed to configure zen provider auth:", error);
  }
}

async function getProviderState() {
  const providers = unwrap(await opencodeClient.config.providers());
  const providerList = Array.isArray(providers?.providers)
    ? providers.providers
    : [];
  const defaults = providers?.default ?? {};
  const availableModels = [];
  for (const provider of providerList) {
    const providerId = provider?.id;
    const models = provider?.models ?? {};
    for (const modelId of Object.keys(models)) {
      availableModels.push(`${providerId}/${modelId}`);
    }
  }
  const desiredAvailable = availableModels.includes(DESIRED_DEFAULT_MODEL);
  return {
    defaults,
    providerList,
    availableModels,
    desiredAvailable,
  };
}

async function ensureDefaultModelIfAvailable() {
  const state = await getProviderState();
  if (!state.desiredAvailable) {
    const actual = state.defaults?.default || state.defaults?.chat || state.defaults?.opencode || "(none)";
    console.log(
      `[copilot] desired default model not available: ${DESIRED_DEFAULT_MODEL} -- using ${actual}`,
    );
    return;
  }
  const currentDefault = state.defaults?.default || state.defaults?.chat || state.defaults?.opencode;
  if (currentDefault === DESIRED_DEFAULT_MODEL) return;
  try {
    await opencodeClient.config.update({
      body: { model: DESIRED_DEFAULT_MODEL },
      query: { directory: WORKSPACE_DIR },
    });
    console.log(`[copilot] default model set to ${DESIRED_DEFAULT_MODEL}`);
  } catch (error) {
    console.error("[copilot] failed to set default model:", error);
  }
}

await ensureDefaultModelIfAvailable();

const sessionMap = new Map();
const modelMap = new Map();

function sessionScopeKey(userId, openclawId) {
  return `${userId}:${openclawId || "none"}`;
}

function parseModelId(qualified) {
  if (!qualified) return null;
  const slash = qualified.indexOf("/");
  if (slash === -1) return null;
  return { providerID: qualified.slice(0, slash), modelID: qualified.slice(slash + 1) };
}

function getSelectedModel(user, selectedOpenClaw) {
  const key = sessionScopeKey(user.id, selectedOpenClaw?.id || null);
  return modelMap.get(key) || null;
}

function setSelectedModel(user, selectedOpenClaw, qualified) {
  const key = sessionScopeKey(user.id, selectedOpenClaw?.id || null);
  modelMap.set(key, qualified);
}

async function ensureSession(user, selectedOpenClaw) {
  const key = sessionScopeKey(user.id, selectedOpenClaw?.id || null);
  let sessionId = sessionMap.get(key);
  if (sessionId) return sessionId;

  const created = unwrap(
    await opencodeClient.session.create({
      body: {
        title: selectedOpenClaw
          ? `copilot:${user.email || user.id}:${selectedOpenClaw.name}`
          : `copilot:${user.email || user.id}`,
      },
    }),
  );
  sessionId = created.id;
  sessionMap.set(key, sessionId);
  return sessionId;
}

async function getSystemContext(user, selectedOpenClaw) {
  let openclawReachable = false;
  if (selectedOpenClaw && ORCHESTRATOR_SERVICE_TOKEN) {
    const backend = await resolveOpenClawBackend(selectedOpenClaw.id);
    openclawReachable = !!backend;
  }
  return buildContext(user, selectedOpenClaw, openclawReachable);
}

const app = express();
app.use(
  cors({
    origin: (origin, callback) => {
      if (!origin || ALLOWED_ORIGINS.includes(origin)) {
        callback(null, true);
      } else {
        callback(new Error(`origin ${origin} not allowed`));
      }
    },
    credentials: true,
  }),
);
app.use(express.json({ limit: "256kb" }));

app.get("/health", (_req, res) => {
  res.json({
    status: "ok",
    service: "copilot",
    workspace: WORKSPACE_DIR,
    opencodePort: OPENCODE_PORT,
  });
});

app.use(requireSuperadmin);
app.use(resolveSelectedOpenClaw);

app.get("/status", async (req, res) => {
  try {
    const state = await getProviderState();
    const defaultModel = state.defaults?.opencode || state.defaults?.chat || state.defaults?.default || null;
    const selected = getSelectedModel(req.user, req.selectedOpenClaw);
    res.json({
      workspace: WORKSPACE_DIR,
      desiredDefaultModel: DESIRED_DEFAULT_MODEL,
      desiredDefaultAvailable: state.desiredAvailable,
      actualModel: selected || defaultModel,
      defaults: state.defaults,
      connectedProviders: state.providerList
        .filter((provider) => provider?.id && Object.keys(provider?.models ?? {}).length > 0)
        .map((provider) => provider.id),
      user: {
        id: req.user.id,
        email: req.user.email,
        role: req.user.role,
        permissions: req.user.permissions,
      },
      openclaw: req.selectedOpenClaw,
    });
  } catch (error) {
    console.error("[copilot] status error:", error);
    res.status(500).json({ error: "failed to load copilot status" });
  }
});

app.get("/session", async (req, res) => {
  try {
    const sessionId = await ensureSession(req.user, req.selectedOpenClaw);
    res.json({
      sessionId,
      openclaw: req.selectedOpenClaw,
      user: {
        id: req.user.id,
        email: req.user.email,
        role: req.user.role,
        permissions: req.user.permissions,
      },
    });
  } catch (error) {
    console.error("[copilot] ensure session error:", error);
    res.status(500).json({ error: "failed to create or load copilot session" });
  }
});

app.get("/messages", async (req, res) => {
  try {
    const sessionId = await ensureSession(req.user, req.selectedOpenClaw);
    const result = unwrap(
      await opencodeClient.session.messages({ path: { id: sessionId } }),
    );
    const payload = buildMessagesPayload(Array.isArray(result) ? result : []);
    res.json({
      sessionId,
      messages: payload.messages,
    });
  } catch (error) {
    console.error("[copilot] messages error:", error);
    res.status(500).json({ error: "failed to load copilot messages" });
  }
});

app.post("/prompt", async (req, res) => {
  const message = req.body?.message?.toString().trim() || "";
  if (!message) {
    return res.status(400).json({ error: "message is required" });
  }

  try {
    const providers = unwrap(await opencodeClient.config.providers());
    const defaults = providers?.default ?? {};
    if (Object.keys(defaults).length === 0) {
      return res.status(503).json({
        error:
          "copilot has no configured default OpenCode model/provider yet",
      });
    }

    const sessionId = await ensureSession(req.user, req.selectedOpenClaw);
    const systemContext = await getSystemContext(req.user, req.selectedOpenClaw);
    const selectedModel = getSelectedModel(req.user, req.selectedOpenClaw);
    const modelParam = parseModelId(selectedModel);
    const promptBody = {
      system: systemContext,
      parts: [{ type: "text", text: message }],
    };
    if (modelParam) promptBody.model = modelParam;
    let promptTimedOut = false;
    try {
      await withTimeout(
        opencodeClient.session.prompt({
          path: { id: sessionId },
          body: promptBody,
        }),
        COPILOT_PROMPT_TIMEOUT_MS,
        "copilot prompt",
      );
    } catch (error) {
      if (error instanceof Error && error.message.includes("timed out")) {
        promptTimedOut = true;
        console.warn(`[copilot] ${error.message}; returning latest available messages`);
      } else {
        throw error;
      }
    }

    const result = unwrap(
      await opencodeClient.session.messages({ path: { id: sessionId } }),
    );
    const payload = buildMessagesPayload(Array.isArray(result) ? result : []);
    const responseBody = {
      sessionId,
      messages: payload.messages,
    };
    if (promptTimedOut) {
      return res.status(202).json({
        ...responseBody,
        pending: true,
        warning: `copilot response still processing after ${COPILOT_PROMPT_TIMEOUT_MS}ms`,
      });
    }
    res.json(responseBody);
  } catch (error) {
    console.error("[copilot] prompt error:", error);
    res.status(500).json({ error: "failed to send copilot prompt" });
  }
});

function connectedModels(state) {
  const connected = [];
  for (const provider of state.providerList) {
    if (!provider?.id) continue;
    const models = provider?.models ?? {};
    if (Object.keys(models).length === 0) continue;
    for (const modelId of Object.keys(models)) {
      connected.push(`${provider.id}/${modelId}`);
    }
  }
  return connected;
}

app.get("/models", async (req, res) => {
  try {
    const state = await getProviderState();
    const selected = getSelectedModel(req.user, req.selectedOpenClaw);
    const defaultModel =
      state.defaults?.opencode ||
      state.defaults?.chat ||
      state.defaults?.default ||
      null;
    res.json({
      current: selected || defaultModel,
      default: defaultModel,
      available: connectedModels(state),
    });
  } catch (error) {
    console.error("[copilot] models error:", error);
    res.status(500).json({ error: "failed to list models" });
  }
});

app.post("/model", async (req, res) => {
  const model = req.body?.model?.toString().trim() || "";
  if (!model) {
    return res.status(400).json({ error: "model is required" });
  }

  try {
    const parsed = parseModelId(model);
    if (!parsed) {
      return res.status(400).json({ error: "model must be in provider/model format" });
    }
    setSelectedModel(req.user, req.selectedOpenClaw, model);
    console.log(`[copilot] model selected: ${model} (user=${req.user.email})`);
    const state = await getProviderState();
    const defaultModel =
      state.defaults?.opencode ||
      state.defaults?.chat ||
      state.defaults?.default ||
      null;
    res.json({
      current: model,
      default: defaultModel,
      available: connectedModels(state),
    });
  } catch (error) {
    console.error("[copilot] set model error:", error);
    res.status(500).json({ error: "failed to set model" });
  }
});

app.post("/session/reset", async (req, res) => {
  try {
    const key = sessionScopeKey(req.user.id, req.selectedOpenClaw?.id || null);
    const existing = sessionMap.get(key);
    if (existing) {
      await opencodeClient.session.delete({ path: { id: existing } });
      sessionMap.delete(key);
    }
    const sessionId = await ensureSession(req.user, req.selectedOpenClaw);
    res.json({ sessionId, messages: [] });
  } catch (error) {
    console.error("[copilot] reset error:", error);
    res.status(500).json({ error: "failed to reset copilot session" });
  }
});

app.get("/openclaw/info", async (req, res) => {
  if (!req.selectedOpenClaw) {
    return res.status(400).json({ error: "no openclaw selected" });
  }
  try {
    const backend = await resolveOpenClawBackend(req.selectedOpenClaw.id);
    if (!backend) {
      return res.status(502).json({ error: "could not resolve openclaw backend" });
    }
    res.json({
      name: req.selectedOpenClaw.name,
      id: req.selectedOpenClaw.id,
      host: backend.host,
      port: backend.port,
      reachable: true,
    });
  } catch (error) {
    console.error("[copilot] openclaw info error:", error);
    res.status(500).json({ error: "failed to get openclaw info" });
  }
});

app.post("/openclaw/exec", async (req, res) => {
  res.status(410).json({
    error: "endpoint disabled",
    message:
      "Run commands in the side-by-side PTY terminal and paste output here for analysis.",
  });
});

const server = app.listen(PORT, "0.0.0.0", () => {
  console.log(
    `[copilot] listening on ${PORT} (workspace=${WORKSPACE_DIR}, opencode=${OPENCODE_PORT})`,
  );
});

function shutdown(signal) {
  console.log(`[copilot] received ${signal}, shutting down`);
  server.close(() => {
    try {
      opencodeServer.close?.();
    } catch (_) {}
    process.exit(0);
  });
  setTimeout(() => process.exit(1), 10000).unref();
}

process.on("SIGTERM", () => shutdown("SIGTERM"));
process.on("SIGINT", () => shutdown("SIGINT"));
