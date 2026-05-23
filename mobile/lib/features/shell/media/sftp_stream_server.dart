import 'dart:async';
import 'dart:io';

import '../sftp_session_manager.dart';

/// Tiny localhost HTTP server that proxies HTTP Range requests onto an SFTP
/// file. Used to stream remote videos directly into ExoPlayer / AVPlayer
/// without pre-downloading multi-GB files.
///
/// Lifecycle is owned by the caller (video page): [start] binds, [stop]
/// closes the server (forcing any in-flight responses to terminate). Closing
/// the server releases the underlying [SftpReadHandle].
class SftpStreamServer {
  SftpStreamServer({
    required this.manager,
    required this.remotePath,
    required this.fileName,
  });

  final SftpSessionManager manager;
  final String remotePath;
  final String fileName;

  HttpServer? _server;
  SftpReadHandle? _handle;

  /// Binds the server, opens the SFTP handle, and returns a URL the video
  /// player can hit.
  Future<Uri> start() async {
    _handle = await manager.openRemoteForRead(remotePath);
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    _server = server;
    final fileSize = _handle!.size;
    final mime = _guessMime(fileName);
    unawaited(_acceptLoop(server, fileSize, mime));
    return Uri.parse('http://127.0.0.1:${server.port}/v');
  }

  Future<void> stop() async {
    final handle = _handle;
    _handle = null;
    final server = _server;
    _server = null;
    if (server != null) {
      try {
        await server.close(force: true);
      } catch (_) {}
    }
    if (handle != null) {
      await handle.close();
    }
  }

  Future<void> _acceptLoop(
    HttpServer server,
    int fileSize,
    String contentType,
  ) async {
    try {
      await for (final request in server) {
        unawaited(_handleRequest(request, fileSize, contentType));
      }
    } catch (_) {
      // Server closed mid-iteration.
    }
  }

  Future<void> _handleRequest(
    HttpRequest request,
    int fileSize,
    String contentType,
  ) async {
    final response = request.response;
    try {
      final isHead = request.method == 'HEAD';
      final range = _parseRange(
        request.headers.value(HttpHeaders.rangeHeader),
        fileSize,
      );

      if (range == null) {
        response.statusCode = HttpStatus.requestedRangeNotSatisfiable;
        response.headers.set('Content-Range', 'bytes */$fileSize');
        await response.close();
        return;
      }

      final start = range.start;
      final end = range.end;
      final length = end - start + 1;
      final isPartial = range.isPartial;

      response
        ..statusCode = isPartial ? HttpStatus.partialContent : HttpStatus.ok
        ..headers.set(HttpHeaders.acceptRangesHeader, 'bytes')
        ..headers.set(HttpHeaders.contentTypeHeader, contentType)
        ..headers.contentLength = length;
      if (isPartial) {
        response.headers.set('Content-Range', 'bytes $start-$end/$fileSize');
      }

      if (isHead || length == 0) {
        await response.close();
        return;
      }

      final handle = _handle;
      if (handle == null || handle.isClosed) {
        await response.close();
        return;
      }

      final completer = Completer<void>();
      late StreamSubscription<List<int>> sub;
      var finished = false;
      void finish([Object? error, StackTrace? stack]) {
        if (finished) return;
        finished = true;
        sub.cancel();
        if (!completer.isCompleted) {
          if (error == null) {
            completer.complete();
          } else {
            completer.completeError(error, stack);
          }
        }
      }

      sub = handle
          .read(offset: start, length: length)
          .listen(
            (chunk) {
              try {
                response.add(chunk);
              } catch (e, st) {
                finish(e, st);
              }
            },
            onError: finish,
            onDone: finish,
            cancelOnError: true,
          );
      // If the client (player) disconnects, response.done resolves and we
      // tear the SFTP read down immediately.
      response.done.then((_) => finish(), onError: (_) => finish());

      try {
        await completer.future;
      } catch (_) {
        // Swallow — the response is already aborted.
      }
      try {
        await response.close();
      } catch (_) {}
    } catch (_) {
      try {
        response.statusCode = HttpStatus.internalServerError;
      } catch (_) {}
      try {
        await response.close();
      } catch (_) {}
    }
  }
}

class _ResolvedRange {
  const _ResolvedRange(this.start, this.end, this.isPartial);

  final int start;
  final int end;
  final bool isPartial;
}

_ResolvedRange? _parseRange(String? header, int fileSize) {
  if (fileSize <= 0) return _ResolvedRange(0, 0, false);
  if (header == null || !header.startsWith('bytes=')) {
    return _ResolvedRange(0, fileSize - 1, false);
  }
  final spec = header.substring(6).trim();
  if (spec.isEmpty || spec.contains(',')) {
    // Multi-range not supported; reject.
    return null;
  }
  final dash = spec.indexOf('-');
  if (dash < 0) return null;
  final startStr = spec.substring(0, dash).trim();
  final endStr = spec.substring(dash + 1).trim();
  int start;
  int end;
  if (startStr.isEmpty) {
    // Suffix range: "bytes=-N" → last N bytes.
    final n = int.tryParse(endStr);
    if (n == null || n <= 0) return null;
    start = fileSize - n;
    if (start < 0) start = 0;
    end = fileSize - 1;
  } else {
    final s = int.tryParse(startStr);
    if (s == null || s < 0 || s >= fileSize) return null;
    start = s;
    if (endStr.isEmpty) {
      end = fileSize - 1;
    } else {
      final e = int.tryParse(endStr);
      if (e == null || e < start) return null;
      end = e >= fileSize ? fileSize - 1 : e;
    }
  }
  return _ResolvedRange(start, end, true);
}

String _guessMime(String name) {
  final dot = name.lastIndexOf('.');
  if (dot < 0 || dot == name.length - 1) return 'application/octet-stream';
  switch (name.substring(dot + 1).toLowerCase()) {
    case 'mp4':
    case 'm4v':
      return 'video/mp4';
    case 'mov':
      return 'video/quicktime';
    case 'webm':
      return 'video/webm';
    case 'mkv':
      return 'video/x-matroska';
    case 'ts':
      return 'video/mp2t';
    case '3gp':
      return 'video/3gpp';
    default:
      return 'application/octet-stream';
  }
}
