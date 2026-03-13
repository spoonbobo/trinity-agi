/**
 * File attachment utilities — 1:1 port of core/attachment_utils.dart
 */

/* ------------------------------------------------------------------ */
/*  Limits                                                             */
/* ------------------------------------------------------------------ */

export const AttachmentLimits = {
  maxImageBytes: 5 * 1024 * 1024,
  maxAudioBytes: 5 * 1024 * 1024,
  maxVideoBytes: 5 * 1024 * 1024,
  maxDocumentBytes: 5 * 1024 * 1024,
  maxAttachments: 10,
  imageCompressionThreshold: 2 * 1024 * 1024,
  imageMaxDimension: 2048,
  jpegQuality: 0.85,

  maxBytesForMime(mime: string): number {
    if (mime.startsWith('image/')) return this.maxImageBytes;
    if (mime.startsWith('audio/')) return this.maxAudioBytes;
    if (mime.startsWith('video/')) return this.maxVideoBytes;
    return this.maxDocumentBytes;
  },

  limitStringForMime(mime: string): string {
    const bytes = this.maxBytesForMime(mime);
    return `${(bytes / (1024 * 1024)).toFixed(0)} MB`;
  },
};

/* ------------------------------------------------------------------ */
/*  MIME validation                                                    */
/* ------------------------------------------------------------------ */

const ALLOWED_MIME_PATTERNS = [
  /^image\//,
  /^audio\//,
  /^video\//,
  /^application\/pdf$/,
  /^text\//,
  /^application\/msword$/,
  /^application\/vnd\.openxmlformats/,
  /^application\/vnd\.ms-/,
  /^application\/vnd\.oasis\.opendocument/,
  /^application\/rtf$/,
  /^application\/epub\+xml$/,
  /^application\/octet-stream$/,
];

const ALLOWED_EXTENSIONS = new Set([
  // Documents
  'pdf', 'doc', 'docx', 'xls', 'xlsx', 'ppt', 'pptx', 'odt', 'ods', 'odp', 'rtf', 'epub',
  // Text / config
  'txt', 'md', 'csv', 'json', 'yaml', 'yml', 'xml', 'html', 'htm', 'css', 'toml', 'ini', 'cfg', 'conf',
  // Code
  'js', 'ts', 'jsx', 'tsx', 'py', 'rb', 'go', 'rs', 'java', 'kt', 'swift', 'c', 'cpp', 'h', 'hpp',
  'cs', 'php', 'sh', 'bash', 'zsh', 'fish', 'ps1', 'sql', 'r', 'lua', 'pl', 'dart', 'scala',
  'ex', 'exs', 'erl', 'hs', 'ml', 'fs', 'clj', 'vim', 'el', 'lisp',
  // Images
  'jpg', 'jpeg', 'png', 'gif', 'webp', 'svg', 'bmp', 'ico', 'tiff',
  // Audio/video
  'mp3', 'wav', 'ogg', 'flac', 'mp4', 'webm', 'mkv', 'avi', 'mov',
]);

/**
 * Validate a file for upload. Returns null if valid, or an error message.
 */
export function validateFile(file: File): string | null {
  const mime = file.type || 'application/octet-stream';
  const ext = file.name.split('.').pop()?.toLowerCase() ?? '';

  const mimeOk = ALLOWED_MIME_PATTERNS.some((p) => p.test(mime));
  const extOk = ALLOWED_EXTENSIONS.has(ext);

  if (!mimeOk && !extOk) {
    return `File type not supported: ${mime || ext}`;
  }

  const maxBytes = AttachmentLimits.maxBytesForMime(mime);
  if (file.size > maxBytes) {
    return `File too large: ${(file.size / (1024 * 1024)).toFixed(1)} MB (max ${AttachmentLimits.limitStringForMime(mime)})`;
  }

  return null;
}

/* ------------------------------------------------------------------ */
/*  Image compression                                                  */
/* ------------------------------------------------------------------ */

export function shouldCompressImage(file: File): boolean {
  const mime = file.type;
  if (mime === 'image/svg+xml' || mime === 'image/gif') return false;
  return file.size > AttachmentLimits.imageCompressionThreshold;
}

export async function compressImage(
  file: File,
): Promise<{ base64: string; mimeType: string; size: number }> {
  return new Promise((resolve, reject) => {
    const img = new Image();
    const url = URL.createObjectURL(file);

    img.onload = () => {
      URL.revokeObjectURL(url);
      let { width, height } = img;
      const max = AttachmentLimits.imageMaxDimension;

      if (width > max || height > max) {
        const ratio = Math.min(max / width, max / height);
        width = Math.round(width * ratio);
        height = Math.round(height * ratio);
      }

      const canvas = document.createElement('canvas');
      canvas.width = width;
      canvas.height = height;
      const ctx = canvas.getContext('2d');
      if (!ctx) {
        reject(new Error('Canvas context unavailable'));
        return;
      }
      ctx.drawImage(img, 0, 0, width, height);

      const dataUrl = canvas.toDataURL('image/jpeg', AttachmentLimits.jpegQuality);
      const base64 = dataUrl.split(',')[1];
      const size = Math.round((base64.length * 3) / 4);

      resolve({ base64, mimeType: 'image/jpeg', size });
    };

    img.onerror = () => {
      URL.revokeObjectURL(url);
      reject(new Error('Failed to load image'));
    };

    img.src = url;
  });
}

/* ------------------------------------------------------------------ */
/*  File reading                                                       */
/* ------------------------------------------------------------------ */

export function readFileAsBase64(file: File): Promise<string> {
  return new Promise((resolve, reject) => {
    const reader = new FileReader();
    reader.onload = () => {
      const result = reader.result as string;
      // Strip data URL prefix
      const base64 = result.includes(',') ? result.split(',')[1] : result;
      resolve(base64);
    };
    reader.onerror = () => reject(new Error('Failed to read file'));
    reader.readAsDataURL(file);
  });
}

/* ------------------------------------------------------------------ */
/*  Upload to workspace                                                */
/* ------------------------------------------------------------------ */

export interface FileUploadResult {
  ok: boolean;
  path?: string;
  name?: string;
  size?: number;
  error?: string;
}

export async function uploadFileToWorkspace(
  file: File,
  token: string,
  openclawId?: string,
): Promise<FileUploadResult> {
  try {
    const url = new URL('/__openclaw__/upload', window.location.origin);
    if (openclawId) url.searchParams.set('openclaw', openclawId);

    const res = await fetch(url.toString(), {
      method: 'POST',
      headers: {
        'Content-Type': file.type || 'application/octet-stream',
        'X-File-Name': file.name,
        Authorization: `Bearer ${token}`,
      },
      body: file,
      signal: AbortSignal.timeout(30000),
    });

    if (!res.ok) {
      return { ok: false, error: `Upload failed: ${res.status}` };
    }

    const data = await res.json();
    return {
      ok: true,
      path: data.path,
      name: data.name ?? file.name,
      size: data.size ?? file.size,
    };
  } catch (err: any) {
    return { ok: false, error: err.message ?? 'Upload failed' };
  }
}
