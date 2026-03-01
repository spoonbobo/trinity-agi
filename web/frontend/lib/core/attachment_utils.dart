import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'dart:html' as html;

/// File size limits aligned with OpenClaw gateway caps.
class AttachmentLimits {
  static const int maxImageBytes = 5 * 1024 * 1024;        // 5 MB
  static const int maxAudioBytes = 5 * 1024 * 1024;        // 5 MB
  static const int maxVideoBytes = 5 * 1024 * 1024;        // 5 MB
  static const int maxDocumentBytes = 5 * 1024 * 1024;     // 5 MB
  static const int maxDefaultBytes = 5 * 1024 * 1024;      // 5 MB
  static const int maxAttachments = 10;

  /// Image compression threshold — compress images above this size.
  static const int imageCompressThreshold = 2 * 1024 * 1024; // 2 MB

  /// Max image dimension after compression (longest side).
  static const int imageMaxDimension = 2048;

  /// JPEG quality for compressed images (0.0-1.0).
  static const double imageCompressQuality = 0.85;

  /// Returns the max allowed bytes for a given MIME type.
  static int maxBytesForMime(String mime) {
    if (mime.startsWith('image/')) return maxImageBytes;
    if (mime.startsWith('audio/')) return maxAudioBytes;
    if (mime.startsWith('video/')) return maxVideoBytes;
    return maxDocumentBytes;
  }

  /// Human-readable limit string.
  static String limitStringForMime(String mime) {
    final bytes = maxBytesForMime(mime);
    return '${(bytes / (1024 * 1024)).round()} MB';
  }
}

/// MIME type validation and classification.
class MimeValidator {
  static const _allowedMimePatterns = [
    'image/',
    'audio/',
    'video/',
    'application/pdf',
    'text/plain',
    'text/markdown',
    'text/csv',
    'application/json',
    'application/yaml',
    'text/yaml',
    'text/x-python',
    'text/javascript',
    'text/typescript',
    'text/x-dart',
    'application/x-yaml',
    // Office Open XML (DOCX, XLSX, PPTX)
    'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
    'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
    'application/vnd.openxmlformats-officedocument.presentationml.presentation',
    // Legacy Office (DOC, XLS, PPT)
    'application/msword',
    'application/vnd.ms-excel',
    'application/vnd.ms-powerpoint',
    // OpenDocument
    'application/vnd.oasis.opendocument.text',
    'application/vnd.oasis.opendocument.spreadsheet',
    'application/vnd.oasis.opendocument.presentation',
    // Other document formats
    'application/rtf',
    'application/epub+zip',
    'application/octet-stream', // fallback for unknown extensions
  ];

  static const _allowedExtensions = {
    // Documents
    '.pdf', '.txt', '.md', '.json', '.csv',
    '.docx', '.xlsx', '.pptx', '.doc', '.xls', '.ppt',
    '.odt', '.ods', '.odp', '.rtf', '.epub',
    // Web & config
    '.html', '.css', '.xml', '.sql', '.yaml', '.yml',
    '.toml', '.ini', '.cfg', '.conf', '.properties',
    '.env', '.log',
    // Code
    '.py', '.js', '.ts', '.dart', '.sh', '.bash', '.zsh',
    '.gradle', '.kt', '.java', '.c', '.cpp', '.h', '.hpp',
    '.rs', '.go', '.rb', '.php', '.swift', '.r', '.m', '.lua',
  };

  /// Validate a file for upload. Returns null if valid, error message if not.
  static String? validate(html.File file) {
    final mime = file.type;
    final name = file.name.toLowerCase();

    // Check MIME type
    if (mime.isNotEmpty) {
      final mimeOk = _allowedMimePatterns.any((p) => mime.startsWith(p));
      if (mimeOk) {
        // Check size limit
        final maxBytes = AttachmentLimits.maxBytesForMime(mime);
        if (file.size > maxBytes) {
          return '${file.name} exceeds ${AttachmentLimits.limitStringForMime(mime)} limit';
        }
        return null; // Valid
      }
    }

    // Fallback: check by extension
    final dotIndex = name.lastIndexOf('.');
    if (dotIndex >= 0) {
      final ext = name.substring(dotIndex);
      if (_allowedExtensions.contains(ext)) {
        if (file.size > AttachmentLimits.maxDefaultBytes) {
          return '${file.name} exceeds 25 MB limit';
        }
        return null; // Valid
      }
    }

    return '${file.name}: unsupported file type';
  }
}

/// Client-side image compression using HTML Canvas.
///
/// Resizes images to [AttachmentLimits.imageMaxDimension] max side
/// and recompresses to JPEG at [AttachmentLimits.imageCompressQuality].
class ImageCompressor {
  /// Compress an image file. Returns a new File-like blob, or null on failure.
  /// The returned record contains (base64Data, mimeType, size).
  static Future<({String base64, String mimeType, int size})?> compress(
    html.File file,
  ) async {
    try {
      // Load image into an Image element
      final url = html.Url.createObjectUrlFromBlob(file);
      final img = html.ImageElement();
      final completer = Completer<void>();
      img.onLoad.first.then((_) => completer.complete());
      img.onError.first.then((_) => completer.completeError('Failed to load image'));
      img.src = url;
      await completer.future;
      html.Url.revokeObjectUrl(url);

      final origW = img.naturalWidth;
      final origH = img.naturalHeight;

      // Calculate target dimensions
      final maxDim = AttachmentLimits.imageMaxDimension;
      int targetW = origW;
      int targetH = origH;
      if (origW > maxDim || origH > maxDim) {
        if (origW >= origH) {
          targetW = maxDim;
          targetH = (origH * maxDim / origW).round();
        } else {
          targetH = maxDim;
          targetW = (origW * maxDim / origH).round();
        }
      } else if (file.size <= AttachmentLimits.imageCompressThreshold) {
        // Image is small enough and within dimensions — skip compression
        return null;
      }

      // Draw to canvas
      final canvas = html.CanvasElement(width: targetW, height: targetH);
      final ctx = canvas.context2D;
      ctx.drawImageScaled(img, 0, 0, targetW, targetH);

      // Export as JPEG data URL via canvas.toDataUrl
      // (toBlob has limited quality parameter support in dart:html)
      final dataUrl = canvas.toDataUrl('image/jpeg', AttachmentLimits.imageCompressQuality);
      final commaIndex = dataUrl.indexOf(',');
      if (commaIndex <= 0) return null;
      final base64 = dataUrl.substring(commaIndex + 1);

      // Estimate size from base64 length (base64 is ~4/3 of binary)
      final estimatedSize = (base64.length * 3 / 4).round();

      return (base64: base64, mimeType: 'image/jpeg', size: estimatedSize);
    } catch (_) {
      return null; // Compression failed — caller should use original
    }
  }

  /// Whether an image file should be compressed.
  static bool shouldCompress(html.File file) {
    final mime = file.type;
    if (!mime.startsWith('image/')) return false;
    // Don't compress SVGs or GIFs (they lose quality or animation)
    if (mime == 'image/svg+xml' || mime == 'image/gif') return false;
    return file.size > AttachmentLimits.imageCompressThreshold;
  }
}

/// Result of a file upload to the gateway workspace.
class FileUploadResult {
  final bool ok;
  final String? path;
  final String? name;
  final int? size;
  final String? error;
  const FileUploadResult({required this.ok, this.path, this.name, this.size, this.error});
}

/// Upload a non-image file to the OpenClaw workspace via the /__openclaw__/upload
/// HTTP endpoint. Returns the workspace-relative path for use in chat.send messages.
///
/// Protocol: POST raw bytes with metadata in headers.
///   Authorization: Bearer <gateway-token>
///   Content-Type: <mime-type>
///   X-File-Name: <url-encoded-filename>
Future<FileUploadResult> uploadFileToWorkspace({
  required Uint8List bytes,
  required String fileName,
  required String mimeType,
  required String gatewayToken,
}) async {
  // Build the upload URL relative to the current origin
  final uri = Uri.parse('${html.window.location.origin}/__openclaw__/upload');

  final request = html.HttpRequest();
  request.open('POST', uri.toString());
  request.setRequestHeader('Authorization', 'Bearer $gatewayToken');
  request.setRequestHeader('Content-Type', mimeType);
  request.setRequestHeader('X-File-Name', Uri.encodeComponent(fileName));

  final completer = Completer<FileUploadResult>();

  request.onLoadEnd.first.then((_) {
    if (request.status! >= 200 && request.status! < 300) {
      try {
        final body = jsonDecode(request.responseText ?? '{}') as Map<String, dynamic>;
        completer.complete(FileUploadResult(
          ok: body['ok'] == true,
          path: body['path'] as String?,
          name: body['name'] as String?,
          size: body['size'] as int?,
          error: body['error'] as String?,
        ));
      } catch (e) {
        completer.complete(FileUploadResult(
          ok: false,
          error: 'Invalid response: $e',
        ));
      }
    } else {
      String errorMsg = 'Upload failed (HTTP ${request.status})';
      try {
        final body = jsonDecode(request.responseText ?? '{}') as Map<String, dynamic>;
        if (body['error'] != null) errorMsg = body['error'] as String;
      } catch (_) {}
      completer.complete(FileUploadResult(ok: false, error: errorMsg));
    }
  });

  // Send raw bytes as a Blob
  request.send(html.Blob([bytes], mimeType));

  return completer.future;
}
