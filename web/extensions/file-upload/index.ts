/**
 * file-upload – OpenClaw extension plugin
 *
 * Two HTTP endpoints for webchat file handling:
 *
 * 1. POST /__openclaw__/upload
 *    Upload files to the agent workspace (media/inbound/).
 *    Auth: Authorization: Bearer <gateway-token>
 *    Headers: Content-Type, X-File-Name
 *    Body: raw file bytes
 *    Response: { ok, path, name, size, contentType }
 *
 * 2. GET /__openclaw__/media/<workspace-relative-path>
 *    Serve workspace files over HTTP (for <img src>, A2UI Image, markdown).
 *    Auth: same-origin only (behind nginx reverse proxy).
 *    Serves with correct Content-Type, Cache-Control, path traversal guard.
 */

import { IncomingMessage, ServerResponse } from "node:http";
import * as fs from "node:fs/promises";
import * as fsSync from "node:fs";
import * as path from "node:path";
import * as crypto from "node:crypto";

const MAX_BYTES = 5 * 1024 * 1024; // 5 MB per file
const UPLOAD_PATH = "/__openclaw__/upload";
const MEDIA_PREFIX = "/__openclaw__/media/";

// ─── MIME type resolution ──────────────────────────────────────────────

const MIME_MAP: Record<string, string> = {
  ".png": "image/png",
  ".jpg": "image/jpeg",
  ".jpeg": "image/jpeg",
  ".gif": "image/gif",
  ".webp": "image/webp",
  ".svg": "image/svg+xml",
  ".ico": "image/x-icon",
  ".bmp": "image/bmp",
  ".tiff": "image/tiff",
  ".tif": "image/tiff",
  ".pdf": "application/pdf",
  ".json": "application/json",
  ".xml": "application/xml",
  ".csv": "text/csv",
  ".txt": "text/plain",
  ".md": "text/markdown",
  ".html": "text/html",
  ".css": "text/css",
  ".js": "text/javascript",
  ".mp3": "audio/mpeg",
  ".wav": "audio/wav",
  ".ogg": "audio/ogg",
  ".mp4": "video/mp4",
  ".webm": "video/webm",
  ".zip": "application/zip",
  ".gz": "application/gzip",
  ".tar": "application/x-tar",
};

function resolveMime(filePath: string): string {
  const ext = path.extname(filePath).toLowerCase();
  return MIME_MAP[ext] ?? "application/octet-stream";
}

// ─── Shared helpers ────────────────────────────────────────────────────

/** Sanitize a filename: strip directory separators, limit length, fallback. */
function sanitizeFilename(raw: string): string {
  let name = raw.replace(/[/\\:\x00]/g, "").trim();
  name = name.replace(/\s+/g, " ");
  if (name.length > 200) {
    const ext = path.extname(name);
    const base = path.basename(name, ext).slice(0, 200 - ext.length);
    name = base + ext;
  }
  return name || "upload";
}

/** Read the full request body into a Buffer, enforcing a byte limit. */
function readBody(req: IncomingMessage, maxBytes: number): Promise<Buffer> {
  return new Promise((resolve, reject) => {
    const chunks: Buffer[] = [];
    let total = 0;
    req.on("data", (chunk: Buffer) => {
      total += chunk.length;
      if (total > maxBytes) {
        req.destroy();
        reject(
          new Error(
            `File exceeds ${(maxBytes / 1024 / 1024).toFixed(0)}MB limit`
          )
        );
        return;
      }
      chunks.push(chunk);
    });
    req.on("end", () => resolve(Buffer.concat(chunks)));
    req.on("error", reject);
  });
}

/** Send a JSON response with CORS headers. */
function jsonResponse(
  res: ServerResponse,
  status: number,
  body: Record<string, unknown>
) {
  res.statusCode = status;
  res.setHeader("Content-Type", "application/json; charset=utf-8");
  res.setHeader("Access-Control-Allow-Origin", "*");
  res.setHeader(
    "Access-Control-Allow-Headers",
    "Authorization, Content-Type, X-File-Name"
  );
  res.setHeader("Access-Control-Allow-Methods", "POST, GET, OPTIONS");
  res.end(JSON.stringify(body));
}

/** Resolve the workspace root directory. */
function resolveWorkspace(api: any): string {
  const workspace =
    api.config?.agents?.defaults?.workspace ??
    path.join(process.env.HOME ?? "/home/node", ".openclaw", "workspace");
  return api.resolvePath
    ? api.resolvePath(workspace)
    : workspace.replace(/^~/, process.env.HOME ?? "/home/node");
}

/** Validate gateway token from Authorization header. */
function validateAuth(req: IncomingMessage, api: any): boolean {
  const authHeader = req.headers["authorization"] ?? "";
  const token = authHeader.startsWith("Bearer ")
    ? authHeader.slice(7).trim()
    : "";
  const expectedToken =
    api.config?.gateway?.auth?.token ??
    process.env.OPENCLAW_GATEWAY_TOKEN ??
    "";
  return Boolean(token && expectedToken && token === expectedToken);
}

// ─── Plugin registration ───────────────────────────────────────────────

export default function register(api: any) {
  const log = api.logger;

  // ── 1. POST /__openclaw__/upload  (file upload) ───────────────────

  api.registerHttpRoute({
    path: UPLOAD_PATH,
    handler: async (req: IncomingMessage, res: ServerResponse) => {
      // CORS preflight
      if (req.method === "OPTIONS") {
        res.statusCode = 204;
        res.setHeader("Access-Control-Allow-Origin", "*");
        res.setHeader(
          "Access-Control-Allow-Headers",
          "Authorization, Content-Type, X-File-Name"
        );
        res.setHeader("Access-Control-Allow-Methods", "POST, OPTIONS");
        res.end();
        return;
      }

      if (req.method !== "POST") {
        jsonResponse(res, 405, { ok: false, error: "Method not allowed" });
        return;
      }

      if (!validateAuth(req, api)) {
        jsonResponse(res, 401, { ok: false, error: "Unauthorized" });
        return;
      }

      // Parse metadata from headers
      const rawFileName =
        (req.headers["x-file-name"] as string) ??
        (req.headers["x-filename"] as string) ??
        "upload";
      const fileName = sanitizeFilename(decodeURIComponent(rawFileName));
      const contentType =
        (req.headers["content-type"] as string) ?? "application/octet-stream";

      // Read body
      let body: Buffer;
      try {
        body = await readBody(req, MAX_BYTES);
      } catch (err: any) {
        jsonResponse(res, 413, {
          ok: false,
          error: err.message ?? "File too large",
        });
        return;
      }

      if (body.length === 0) {
        jsonResponse(res, 400, { ok: false, error: "Empty body" });
        return;
      }

      // Write to workspace/media/inbound/
      const resolvedWorkspace = resolveWorkspace(api);
      const inboundDir = path.join(resolvedWorkspace, "media", "inbound");

      try {
        await fs.mkdir(inboundDir, { recursive: true, mode: 0o700 });
      } catch (err: any) {
        log.error(`file-upload: failed to create inbound dir: ${err.message}`);
        jsonResponse(res, 500, {
          ok: false,
          error: "Failed to create upload directory",
        });
        return;
      }

      const uuid = crypto.randomUUID().slice(0, 8);
      const ext = path.extname(fileName);
      const base = path.basename(fileName, ext);
      const safeId = `${base}---${uuid}${ext}`;
      const destPath = path.join(inboundDir, safeId);

      // Path traversal guard
      if (!destPath.startsWith(inboundDir)) {
        jsonResponse(res, 400, { ok: false, error: "Invalid filename" });
        return;
      }

      try {
        await fs.writeFile(destPath, body, { mode: 0o600 });
      } catch (err: any) {
        log.error(`file-upload: write failed: ${err.message}`);
        jsonResponse(res, 500, {
          ok: false,
          error: "Failed to write file",
        });
        return;
      }

      const relativePath = `media/inbound/${safeId}`;
      log.info(
        `file-upload: ${fileName} (${contentType}) -> ${relativePath} (${body.length} bytes)`
      );
      jsonResponse(res, 200, {
        ok: true,
        path: relativePath,
        name: fileName,
        size: body.length,
        contentType,
      });
    },
  });

  // ── 2. GET /__openclaw__/media/*  (file serving) ──────────────────
  //
  // Serves workspace files over HTTP so that:
  //   - A2UI Image components can display generated images
  //   - Markdown image syntax in chat renders workspace images
  //   - Browser <img src> tags work for workspace files
  //
  // Auth: same-origin behind nginx. No token required for GET reads
  // since the endpoint is only reachable via the reverse proxy.
  // Security: path traversal prevention, symlink rejection, workspace-confined.

  api.registerHttpHandler(
    async (req: IncomingMessage, res: ServerResponse): Promise<boolean> => {
      const url = new URL(req.url ?? "/", "http://localhost");
      const pathname = url.pathname;

      // Only handle requests under /__openclaw__/media/
      if (!pathname.startsWith(MEDIA_PREFIX)) return false;

      // Only GET and HEAD
      if (req.method !== "GET" && req.method !== "HEAD") {
        res.statusCode = 405;
        res.setHeader("Content-Type", "text/plain; charset=utf-8");
        res.end("Method Not Allowed");
        return true;
      }

      // Extract the relative path after the prefix
      const rawRelative = decodeURIComponent(
        pathname.slice(MEDIA_PREFIX.length)
      );

      // Reject empty path
      if (!rawRelative || rawRelative === "/") {
        res.statusCode = 400;
        res.setHeader("Content-Type", "text/plain; charset=utf-8");
        res.end("Missing file path");
        return true;
      }

      // Path traversal guard: reject ".." segments, absolute paths, null bytes
      const segments = rawRelative.split("/");
      if (
        segments.some((s) => s === ".." || s === "." || s === "") ||
        rawRelative.includes("\x00") ||
        path.isAbsolute(rawRelative)
      ) {
        res.statusCode = 400;
        res.setHeader("Content-Type", "text/plain; charset=utf-8");
        res.end("Invalid path");
        return true;
      }

      // Resolve to absolute path within workspace
      const resolvedWorkspace = resolveWorkspace(api);
      const filePath = path.join(resolvedWorkspace, rawRelative);

      // Ensure the resolved path stays within the workspace (realpath check)
      try {
        const realPath = await fs.realpath(filePath);
        if (!realPath.startsWith(resolvedWorkspace)) {
          log.warn(
            `media-serve: path escaped workspace: ${rawRelative} -> ${realPath}`
          );
          res.statusCode = 403;
          res.setHeader("Content-Type", "text/plain; charset=utf-8");
          res.end("Forbidden");
          return true;
        }

        // Reject symlinks (stat the lstat first)
        const lstat = await fs.lstat(filePath);
        if (lstat.isSymbolicLink()) {
          res.statusCode = 403;
          res.setHeader("Content-Type", "text/plain; charset=utf-8");
          res.end("Forbidden");
          return true;
        }

        if (!lstat.isFile()) {
          res.statusCode = 404;
          res.setHeader("Content-Type", "text/plain; charset=utf-8");
          res.end("Not found");
          return true;
        }

        // Serve the file
        const mime = resolveMime(filePath);
        const data = await fs.readFile(filePath);

        res.statusCode = 200;
        res.setHeader("Content-Type", mime);
        res.setHeader("Content-Length", data.length.toString());
        // Cache for 5 minutes (generated images are immutable once created)
        res.setHeader("Cache-Control", "public, max-age=300");
        // CORS for same-origin <img> requests
        res.setHeader("Access-Control-Allow-Origin", "*");

        if (req.method === "HEAD") {
          res.end();
        } else {
          res.end(data);
        }
        return true;
      } catch (err: any) {
        if (err.code === "ENOENT") {
          res.statusCode = 404;
          res.setHeader("Content-Type", "text/plain; charset=utf-8");
          res.end("Not found");
          return true;
        }
        log.error(`media-serve: error serving ${rawRelative}: ${err.message}`);
        res.statusCode = 500;
        res.setHeader("Content-Type", "text/plain; charset=utf-8");
        res.end("Internal error");
        return true;
      }
    }
  );

  log.info(
    "file-upload: registered /__openclaw__/upload + /__openclaw__/media/ endpoints"
  );
}
