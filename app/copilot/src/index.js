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

function buildContext(user, selectedOpenClaw) {
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
    lines.push(
      "Limit any operational guidance or control context to that selected OpenClaw.",
    );
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

const sessionMap = new Map();

function sessionScopeKey(userId, openclawId) {
  return `${userId}:${openclawId || "none"}`;
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

async function injectContext(sessionId, user, selectedOpenClaw) {
  await opencodeClient.session.prompt({
    path: { id: sessionId },
    body: {
      noReply: true,
      parts: [{ type: "text", text: buildContext(user, selectedOpenClaw) }],
    },
  });
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
    res.json({
      sessionId,
      messages: normalizeMessages(Array.isArray(result) ? result : []),
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
    await injectContext(sessionId, req.user, req.selectedOpenClaw);
    await withTimeout(
      opencodeClient.session.prompt({
        path: { id: sessionId },
        body: {
          parts: [{ type: "text", text: message }],
        },
      }),
      30000,
      "copilot prompt",
    );

    const result = unwrap(
      await opencodeClient.session.messages({ path: { id: sessionId } }),
    );
    res.json({
      sessionId,
      messages: normalizeMessages(Array.isArray(result) ? result : []),
    });
  } catch (error) {
    console.error("[copilot] prompt error:", error);
    res.status(500).json({ error: "failed to send copilot prompt" });
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
