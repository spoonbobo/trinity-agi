/// Shared safe XHR helper for all browser HTTP requests.
///
/// Handles `onLoad`, `onError`, and `onAbort` with a configurable timeout
/// so that no request can hang indefinitely.
library;

import 'dart:async';
import 'dart:html' as html;

/// Default timeout for XHR requests (10 seconds).
const Duration kDefaultXhrTimeout = Duration(seconds: 10);

/// Perform a safe XHR request that is guaranteed to complete or fail.
///
/// Sets up `onLoad`, `onError`, and `onAbort` listeners before calling
/// [html.HttpRequest.send], and applies a [timeout] (defaults to 10 s).
///
/// Returns the response text on success (status 2xx).
/// Throws on HTTP errors, network errors, aborts, and timeouts.
///
/// Usage:
/// ```dart
/// final request = html.HttpRequest();
/// request.open('GET', url);
/// request.setRequestHeader('Authorization', 'Bearer $token');
/// final responseText = await safeXhr(request);
/// ```
///
/// To send a body:
/// ```dart
/// final responseText = await safeXhr(request, body: jsonEncode(payload));
/// ```
Future<String> safeXhr(
  html.HttpRequest request, {
  dynamic body,
  Duration timeout = kDefaultXhrTimeout,
}) {
  final c = Completer<String>();

  request.onLoad.listen((_) {
    if (c.isCompleted) return;
    final status = request.status ?? 0;
    if (status >= 200 && status < 300) {
      c.complete(request.responseText ?? '{}');
    } else {
      c.completeError(Exception('HTTP $status: ${request.responseText}'));
    }
  });

  request.onError.listen((_) {
    if (!c.isCompleted) {
      c.completeError(Exception('XHR network error'));
    }
  });

  request.onAbort.listen((_) {
    if (!c.isCompleted) {
      c.completeError(Exception('XHR aborted'));
    }
  });

  request.send(body);

  return c.future.timeout(timeout, onTimeout: () {
    request.abort();
    throw TimeoutException('XHR timed out after $timeout', timeout);
  });
}

/// Convenience wrapper around [html.HttpRequest.request] that adds a timeout.
///
/// Use this for simple one-off requests where you don't need to set custom
/// headers beyond what the static helper supports.
Future<html.HttpRequest> safeHttpRequest(
  String url, {
  String method = 'GET',
  Map<String, String>? requestHeaders,
  dynamic sendData,
  String? responseType,
  Duration timeout = kDefaultXhrTimeout,
}) {
  return html.HttpRequest.request(
    url,
    method: method,
    requestHeaders: requestHeaders,
    sendData: sendData,
    responseType: responseType,
  ).timeout(timeout, onTimeout: () {
    throw TimeoutException('HTTP request timed out after $timeout', timeout);
  });
}
