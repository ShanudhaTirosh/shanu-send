import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:shelf_router/shelf_router.dart';
import 'package:uuid/uuid.dart';

class ReceiverSession {
  final String sessionId;
  final String senderAlias;
  final Map<String, dynamic> files;
  final Map<String, String> tokens;

  ReceiverSession({
    required this.sessionId,
    required this.senderAlias,
    required this.files,
    required this.tokens,
  });
}

class ReceiverEvent {
  final String type; // 'incoming-request', 'upload-progress', 'upload-complete'
  final Map<String, dynamic> data;

  ReceiverEvent(this.type, this.data);
}

class WebDropSharedFile {
  final String name;
  final String path;
  final int size;

  WebDropSharedFile({
    required this.name,
    required this.path,
    required this.size,
  });

  Map<String, dynamic> toJson() => {
        'name': name,
        'size': size,
      };
}

class UnifiedHttpServer {
  HttpServer? _server;
  final _eventController = StreamController<ReceiverEvent>.broadcast();
  final Map<String, ReceiverSession> _sessions = {};
  final Map<String, Completer<bool>> _pendingDecisions = {};
  final List<WebDropSharedFile> _sharedFiles = [];

  String alias = 'ShanuSend Device';
  String fingerprint = '';
  int port = 53317;

  Stream<ReceiverEvent> get eventStream => _eventController.stream;
  bool get isRunning => _server != null;

  void addSharedFile(File file) {
    final name = p.basename(file.path);
    final size = file.lengthSync();
    _sharedFiles.removeWhere((f) => f.name == name);
    _sharedFiles.add(WebDropSharedFile(name: name, path: file.path, size: size));
  }

  void clearSharedFiles() {
    _sharedFiles.clear();
  }

  /// The UI must call this in response to an 'incoming-request' event.
  /// If nothing calls it, _handlePrepareUpload's timeout rejects the
  /// transfer rather than hanging the sender or auto-accepting.
  void respondToRequest(String sessionId, bool accept) {
    final completer = _pendingDecisions.remove(sessionId);
    if (completer != null && !completer.isCompleted) {
      completer.complete(accept);
    }
  }

  Future<void> _initFingerprint() async {
    if (fingerprint.isEmpty) {
      try {
        final docDir = await getApplicationDocumentsDirectory();
        final fpFile = File('${docDir.path}/.shanu_fingerprint');
        if (await fpFile.exists()) {
          fingerprint = await fpFile.readAsString();
        } else {
          final newFp = 'shanu_fp_${const Uuid().v4().replaceAll("-", "").substring(0, 16)}';
          await fpFile.writeAsString(newFp);
          fingerprint = newFp;
        }
      } catch (e) {
        fingerprint = 'shanu_fallback_fp';
      }
    }
  }

  Future<void> startServer({int port = 53317, String? customAlias}) async {
    if (_server != null) return;
    await _initFingerprint();
    this.port = port;
    if (customAlias != null && customAlias.isNotEmpty) {
      alias = customAlias;
    }

    final app = Router();

    // 1. WebDrop Browser Routes
    app.get('/', _webDropHtmlHandler);
    app.get('/webdrop', _webDropHtmlHandler);
    app.get('/api/webdrop/files', _getFilesHandler);
    app.get('/api/webdrop/download/<filename>', _downloadFileHandler);
    app.post('/api/webdrop/upload', _webDropUploadHandler);

    // 2. LocalSend v2.1 API Routes
    app.get('/api/localsend/v2/info', _handleInfo);
    app.post('/api/localsend/v2/register', _handleRegister);
    app.post('/api/localsend/v2/prepare-upload', _handlePrepareUpload);
    app.post('/api/localsend/v2/upload', _handleUpload);
    app.post('/api/localsend/v2/cancel', _handleCancel);

    final handler = Pipeline().addMiddleware(logRequests()).addHandler(app.call);

    try {
      _server = await shelf_io.serve(handler, InternetAddress.anyIPv4, port);
      debugPrint('Unified ShanuSend HTTP Server running on port ${_server!.port}');
    } catch (e) {
      debugPrint('Failed to start Unified ShanuSend HTTP Server on port $port: $e');
    }
  }

  Future<void> stopServer() async {
    await _server?.close(force: true);
    _server = null;
  }

  // =========================================================================
  // LocalSend Handlers
  // =========================================================================

  Response _handleInfo(Request request) {
    return Response.ok(
      jsonEncode({
        'alias': alias,
        'version': '2.1',
        'deviceModel': Platform.operatingSystem,
        'deviceType': (Platform.isAndroid || Platform.isIOS) ? 'mobile' : 'desktop',
        'fingerprint': fingerprint,
        'port': port,
        'protocol': 'http',
        'download': true,
      }),
      headers: {'content-type': 'application/json'},
    );
  }

  Response _handleRegister(Request request) {
    return _handleInfo(request);
  }

  Future<Response> _handlePrepareUpload(Request request) async {
    try {
      final bodyStr = await request.readAsString();
      final body = jsonDecode(bodyStr) as Map<String, dynamic>;

      final info = body['info'] as Map<String, dynamic>? ?? {};
      final senderAlias = info['alias'] as String? ?? 'Unknown';
      final files = body['files'] as Map<String, dynamic>? ?? {};

      final sessionId = const Uuid().v4();
      final completer = Completer<bool>();
      _pendingDecisions[sessionId] = completer;

      if (!_eventController.isClosed) {
        _eventController.add(ReceiverEvent('incoming-request', {
          'sessionId': sessionId,
          'senderAlias': senderAlias,
          'files': files,
        }));
      }

      // Block until the UI calls respondToRequest(). No listener attached
      // (e.g. background isolate with no UI) means this times out and
      // rejects rather than silently writing files to disk.
      final accepted = await completer.future.timeout(
        const Duration(seconds: 30),
        onTimeout: () => false,
      );
      _pendingDecisions.remove(sessionId);

      if (!accepted) {
        return Response.forbidden(
          jsonEncode({'message': 'Transfer was declined by the receiver'}),
          headers: {'content-type': 'application/json'},
        );
      }

      final tokens = <String, String>{};
      for (var fileId in files.keys) {
        tokens[fileId] = const Uuid().v4();
      }

      final session = ReceiverSession(
        sessionId: sessionId,
        senderAlias: senderAlias,
        files: files,
        tokens: tokens,
      );
      _sessions[sessionId] = session;

      return Response.ok(
        jsonEncode({
          'sessionId': sessionId,
          'files': tokens,
        }),
        headers: {'content-type': 'application/json'},
      );
    } catch (e) {
      return Response.internalServerError(body: 'Failed to prepare upload: $e');
    }
  }

  Future<Response> _handleUpload(Request request) async {
    final sessionId = request.url.queryParameters['sessionId'];
    final fileId = request.url.queryParameters['fileId'];
    final token = request.url.queryParameters['token'];

    if (sessionId == null || fileId == null || token == null) {
      return Response.badRequest(body: 'Missing parameters');
    }

    final session = _sessions[sessionId];
    if (session == null || session.tokens[fileId] != token) {
      return Response.forbidden('Invalid token or session');
    }

    final fileMeta = session.files[fileId] as Map<String, dynamic>? ?? {};
    final fileName = fileMeta['fileName'] as String? ?? 'received_file_${const Uuid().v4()}';
    final fileSize = fileMeta['size'] as int? ?? 0;

    try {
      final dir = await getApplicationDocumentsDirectory();
      final saveDir = Directory(p.join(dir.path, 'ShanuSendDownloads'));
      await saveDir.create(recursive: true);

      var savePath = p.join(saveDir.path, fileName);
      var file = File(savePath);
      int counter = 1;
      while (await file.exists()) {
        final dotIndex = fileName.lastIndexOf('.');
        if (dotIndex != -1) {
          final nameNoExt = fileName.substring(0, dotIndex);
          final ext = fileName.substring(dotIndex);
          savePath = p.join(saveDir.path, '${nameNoExt}_($counter)$ext');
        } else {
          savePath = p.join(saveDir.path, '${fileName}_($counter)');
        }
        file = File(savePath);
        counter++;
      }
      final sink = file.openWrite();

      int receivedBytes = 0;
      await for (var chunk in request.read()) {
        sink.add(chunk);
        receivedBytes += chunk.length;

        if (!_eventController.isClosed) {
          _eventController.add(ReceiverEvent('upload-progress', {
            'sessionId': sessionId,
            'fileId': fileId,
            'receivedBytes': receivedBytes,
            'totalBytes': fileSize,
          }));
        }
      }

      await sink.flush();
      await sink.close();

      if (!_eventController.isClosed) {
        _eventController.add(ReceiverEvent('upload-complete', {
          'sessionId': sessionId,
          'fileId': fileId,
          'savePath': savePath,
          'fileName': fileName,
        }));
      }

      return Response.ok('Upload complete');
    } catch (e) {
      return Response.internalServerError(body: 'Upload failed: $e');
    }
  }

  Future<Response> _handleCancel(Request request) async {
    final sessionId = request.url.queryParameters['sessionId'];
    if (sessionId != null) {
      _sessions.remove(sessionId);
    }
    return Response.ok('Session cancelled');
  }

  // =========================================================================
  // WebDrop Browser Handlers
  // =========================================================================

  Response _getFilesHandler(Request request) {
    final listJson = jsonEncode(_sharedFiles.map((f) => f.toJson()).toList());
    return Response.ok(listJson, headers: {'content-type': 'application/json'});
  }

  Future<Response> _downloadFileHandler(Request request, String filename) async {
    final decodedName = Uri.decodeComponent(filename);
    final shared = _sharedFiles.firstWhere(
      (f) => f.name == decodedName,
      orElse: () => WebDropSharedFile(name: '', path: '', size: 0),
    );

    if (shared.path.isEmpty) {
      return Response.notFound('File not found');
    }

    final file = File(shared.path);
    if (!await file.exists()) {
      return Response.notFound('File not found on disk');
    }

    final stream = file.openRead();
    return Response.ok(
      stream,
      headers: {
        'content-type': 'application/octet-stream',
        'content-length': shared.size.toString(),
        'content-disposition': 'attachment; filename="${Uri.encodeComponent(shared.name)}"',
      },
    );
  }

  Future<Response> _webDropUploadHandler(Request request) async {
    try {
      final contentType = request.headers['content-type'] ?? '';
      if (!contentType.contains('multipart/form-data')) {
        return Response.badRequest(body: 'Expected multipart/form-data');
      }

      final boundaryMatch = RegExp(r'boundary=(?:"([^"]+)"|([^;]+))').firstMatch(contentType);
      final boundaryStr = boundaryMatch?.group(1) ?? boundaryMatch?.group(2);
      if (boundaryStr == null) {
        return Response.badRequest(body: 'No boundary found');
      }

      final docs = await getApplicationDocumentsDirectory();
      final saveDir = Directory(p.join(docs.path, 'ShanuSendDownloads'));
      await saveDir.create(recursive: true);

      final bodyBytes = await request.read().fold<List<int>>([], (a, b) => a..addAll(b));
      final boundaryBytes = utf8.encode('--$boundaryStr');
      final delimiter = Uint8List.fromList(boundaryBytes);

      int search(List<int> haystack, List<int> needle, int start) {
        for (int i = start; i <= haystack.length - needle.length; i++) {
          bool match = true;
          for (int j = 0; j < needle.length; j++) {
            if (haystack[i + j] != needle[j]) {
              match = false;
              break;
            }
          }
          if (match) return i;
        }
        return -1;
      }

      int pos = 0;
      while (true) {
        final idx = search(bodyBytes, delimiter, pos);
        if (idx == -1) break;
        pos = idx + delimiter.length;

        final nextIdx = search(bodyBytes, delimiter, pos);
        if (nextIdx == -1) break;

        final partBytes = bodyBytes.sublist(pos, nextIdx);

        int headerEnd = -1;
        for (int i = 0; i < partBytes.length - 3; i++) {
          if (partBytes[i] == 13 && partBytes[i + 1] == 10 && partBytes[i + 2] == 13 && partBytes[i + 3] == 10) {
            headerEnd = i;
            break;
          }
        }

        if (headerEnd != -1) {
          final headersText = utf8.decode(partBytes.sublist(0, headerEnd));
          final filenameMatch = RegExp(r'filename="([^"]+)"').firstMatch(headersText);
          if (filenameMatch != null) {
            final rawName = filenameMatch.group(1)!;
            final fileName = p.basename(rawName.replaceAll('/', '_').replaceAll('\\', '_'));

            int contentStart = headerEnd + 4;
            int contentEnd = partBytes.length;
            if (contentEnd >= 2 && partBytes[contentEnd - 2] == 13 && partBytes[contentEnd - 1] == 10) {
              contentEnd -= 2;
            }

            final fileData = partBytes.sublist(contentStart, contentEnd);
            final destPath = p.join(saveDir.path, fileName);
            final destFile = File(destPath);
            await destFile.writeAsBytes(fileData);

            if (!_eventController.isClosed) {
              _eventController.add(ReceiverEvent('upload-complete', {
                'sessionId': 'webdrop-${const Uuid().v4()}',
                'fileName': fileName,
                'savePath': destPath,
              }));
            }
          }
        }
      }

      return Response.ok(
        jsonEncode({'status': 'ok', 'message': 'Files uploaded successfully'}),
        headers: {'content-type': 'application/json'},
      );
    } catch (e) {
      return Response.internalServerError(body: jsonEncode({'error': e.toString()}));
    }
  }

  Response _webDropHtmlHandler(Request request) {
    const htmlContent = r'''<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<title>ShanuSend WebDrop Portal</title>
<link rel="preconnect" href="https://fonts.googleapis.com">
<link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
<link href="https://fonts.googleapis.com/css2?family=Plus+Jakarta+Sans:wght@400;500;600;700;800&display=swap" rel="stylesheet">
<style>
  :root {
    --bg-dark: #07090e;
    --card-bg: rgba(18, 26, 42, 0.85);
    --border-color: rgba(255, 255, 255, 0.1);
    --border-hover: rgba(56, 189, 248, 0.4);
    --accent: #00d285; /* LocalSend Emerald */
    --accent-glow: rgba(0, 210, 133, 0.25);
    --sky: #38bdf8;
    --indigo: #6366f1;
    --text-primary: #f8fafc;
    --text-muted: #94a3b8;
    --card-radius: 24px;
  }

  * { box-sizing: border-box; margin: 0; padding: 0; }

  body {
    font-family: 'Plus Jakarta Sans', -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif;
    background: radial-gradient(circle at 50% 0%, #172554 0%, #07090e 65%);
    color: var(--text-primary);
    display: flex;
    flex-direction: column;
    align-items: center;
    justify-content: center;
    min-height: 100vh;
    padding: 20px;
    -webkit-font-smoothing: antialiased;
  }

  .container {
    background: var(--card-bg);
    backdrop-filter: blur(24px);
    -webkit-backdrop-filter: blur(24px);
    border: 1px solid var(--border-color);
    border-radius: var(--card-radius);
    padding: 36px 28px;
    max-width: 520px;
    width: 100%;
    text-align: center;
    box-shadow: 0 30px 60px -12px rgba(0, 0, 0, 0.7), 0 0 40px rgba(0, 210, 133, 0.08);
  }

  .brand {
    display: flex;
    align-items: center;
    justify-content: center;
    gap: 12px;
    margin-bottom: 8px;
  }

  .brand-icon {
    width: 44px;
    height: 44px;
    background: linear-gradient(135deg, #00d285, #0284c7);
    border-radius: 14px;
    display: flex;
    align-items: center;
    justify-content: center;
    box-shadow: 0 8px 20px var(--accent-glow);
  }

  .brand-icon svg { width: 24px; height: 24px; stroke: #ffffff; fill: none; stroke-width: 2.5; }

  h1 {
    font-size: 24px;
    font-weight: 800;
    letter-spacing: -0.5px;
    background: linear-gradient(135deg, #ffffff 30%, #94a3b8);
    -webkit-background-clip: text;
    -webkit-text-fill-color: transparent;
  }

  .subtitle {
    color: var(--text-muted);
    font-size: 13.5px;
    font-weight: 500;
    margin-bottom: 24px;
    line-height: 1.5;
  }

  .nav-tabs {
    display: flex;
    background: rgba(15, 23, 42, 0.8);
    padding: 5px;
    border-radius: 16px;
    margin-bottom: 24px;
    border: 1px solid var(--border-color);
  }

  .tab-btn {
    flex: 1;
    padding: 12px;
    border: none;
    background: transparent;
    color: var(--text-muted);
    font-weight: 700;
    font-size: 13.5px;
    border-radius: 12px;
    cursor: pointer;
    transition: all 0.25s ease;
    display: flex;
    align-items: center;
    justify-content: center;
    gap: 8px;
  }

  .tab-btn.active {
    background: linear-gradient(135deg, #1e293b, #0f172a);
    color: var(--accent);
    box-shadow: 0 4px 12px rgba(0, 0, 0, 0.3), 0 0 12px var(--accent-glow);
    border: 1px solid rgba(0, 210, 133, 0.2);
  }

  .tab-content { display: none; }
  .tab-content.active { display: block; animation: fadeIn 0.3s cubic-bezier(0.16, 1, 0.3, 1); }

  @keyframes fadeIn {
    from { opacity: 0; transform: translateY(6px); }
    to { opacity: 1; transform: translateY(0); }
  }

  .dropzone {
    border: 2px dashed rgba(255, 255, 255, 0.15);
    border-radius: 20px;
    padding: 36px 20px;
    cursor: pointer;
    transition: all 0.25s ease;
    background: rgba(15, 23, 42, 0.6);
    display: flex;
    flex-direction: column;
    align-items: center;
  }

  .dropzone:hover, .dropzone.dragover {
    border-color: var(--accent);
    background: rgba(0, 210, 133, 0.06);
    transform: scale(1.01);
  }

  .dropzone-icon {
    width: 56px;
    height: 56px;
    background: rgba(0, 210, 133, 0.12);
    border-radius: 16px;
    display: flex;
    align-items: center;
    justify-content: center;
    margin-bottom: 12px;
    color: var(--accent);
  }

  .btn-primary {
    background: linear-gradient(135deg, #00d285, #059669);
    color: #ffffff;
    border: none;
    padding: 15px 24px;
    border-radius: 14px;
    font-weight: 700;
    cursor: pointer;
    width: 100%;
    margin-top: 18px;
    font-size: 15px;
    transition: all 0.2s ease;
    box-shadow: 0 8px 24px var(--accent-glow);
  }

  .btn-primary:hover {
    transform: translateY(-1px);
    box-shadow: 0 12px 28px var(--accent-glow);
  }

  .btn-primary:disabled {
    opacity: 0.4;
    cursor: not-allowed;
    transform: none;
    box-shadow: none;
  }

  .progress-wrap {
    width: 100%;
    background: rgba(30, 41, 59, 0.8);
    border-radius: 999px;
    height: 10px;
    margin-top: 18px;
    overflow: hidden;
    display: none;
    border: 1px solid var(--border-color);
  }

  .progress-bar {
    height: 100%;
    background: linear-gradient(90deg, #00d285, #38bdf8);
    width: 0%;
    transition: width 0.15s ease-out;
    border-radius: 999px;
  }

  #status {
    margin-top: 14px;
    font-size: 13.5px;
    font-weight: 600;
    color: var(--accent);
    min-height: 20px;
  }

  .queue-list {
    margin-top: 16px;
    display: flex;
    flex-direction: column;
    gap: 8px;
    max-height: 160px;
    overflow-y: auto;
    text-align: left;
  }

  .queue-item {
    display: flex;
    align-items: center;
    justify-content: space-between;
    background: rgba(15, 23, 42, 0.7);
    padding: 10px 14px;
    border-radius: 12px;
    font-size: 13px;
    border: 1px solid var(--border-color);
  }

  .queue-name { font-weight: 600; color: #e2e8f0; white-space: nowrap; overflow: hidden; text-overflow: ellipsis; max-width: 260px; }
  .queue-size { color: var(--text-muted); font-size: 11.5px; }

  .file-list {
    display: flex;
    flex-direction: column;
    gap: 10px;
    text-align: left;
    max-height: 320px;
    overflow-y: auto;
  }

  .file-item {
    display: flex;
    align-items: center;
    justify-content: space-between;
    background: rgba(15, 23, 42, 0.7);
    padding: 14px 16px;
    border-radius: 14px;
    border: 1px solid var(--border-color);
    transition: border-color 0.2s;
  }

  .file-item:hover { border-color: rgba(56, 189, 248, 0.3); }

  .file-info { display: flex; flex-direction: column; gap: 2px; overflow: hidden; }
  .file-name { font-size: 14px; font-weight: 600; color: #f1f5f9; white-space: nowrap; overflow: hidden; text-overflow: ellipsis; max-width: 260px; }
  .file-meta { font-size: 12px; color: var(--text-muted); }

  .dl-btn {
    background: linear-gradient(135deg, rgba(56, 189, 248, 0.15), rgba(99, 102, 241, 0.15));
    color: var(--sky);
    border: 1px solid rgba(56, 189, 248, 0.3);
    padding: 8px 16px;
    border-radius: 10px;
    font-size: 12.5px;
    font-weight: 700;
    text-decoration: none;
    cursor: pointer;
    transition: all 0.2s ease;
    display: flex;
    align-items: center;
    gap: 6px;
  }

  .dl-btn:hover {
    background: var(--sky);
    color: #07090e;
    box-shadow: 0 4px 12px rgba(56, 189, 248, 0.3);
  }

  .empty-state {
    padding: 36px 16px;
    color: var(--text-muted);
    font-size: 13.5px;
    display: flex;
    flex-direction: column;
    align-items: center;
    gap: 12px;
  }

  .empty-state svg { opacity: 0.4; }

  footer {
    margin-top: 24px;
    font-size: 12px;
    color: rgba(148, 163, 184, 0.6);
  }
</style>
</head>
<body>

<div class="container">
  <div class="brand">
    <div class="brand-icon">
      <svg viewBox="0 0 24 24"><polygon points="13 2 3 14 12 14 11 22 21 10 12 10 13 2"/></svg>
    </div>
    <h1>ShanuSend WebDrop</h1>
  </div>
  <div class="subtitle">Fast cross-platform file transfer via local browser</div>

  <div class="nav-tabs">
    <button class="tab-btn active" onclick="switchTab('send')">
      <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5"><line x1="12" y1="19" x2="12" y2="5"/><polyline points="5 12 12 5 19 12"/></svg>
      Send Files
    </button>
    <button class="tab-btn" onclick="switchTab('receive')">
      <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5"><line x1="12" y1="5" x2="12" y2="19"/><polyline points="19 12 12 19 5 12"/></svg>
      Shared Files
    </button>
  </div>

  <!-- TAB: SEND -->
  <div id="tab-send" class="tab-content active">
    <div class="dropzone" id="dz" onclick="document.getElementById('fi').click()">
      <div class="dropzone-icon">
        <svg width="28" height="28" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M21 15v4a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2v-4"/><polyline points="17 8 12 3 7 8"/><line x1="12" y1="3" x2="12" y2="15"/></svg>
      </div>
      <div style="font-weight: 700; color: #f1f5f9; font-size: 15px;">Choose or Drag files here</div>
      <div style="font-size: 12.5px; color: var(--text-muted); margin-top: 4px;">Supports videos, photos, archives & documents</div>
    </div>
    <input type="file" id="fi" multiple style="display:none" onchange="handleFileSelect()">

    <div id="queue" class="queue-list"></div>

    <button class="btn-primary" id="sbtn" onclick="uploadFiles()" disabled>Send to Host Device</button>
    <div class="progress-wrap" id="prg"><div class="progress-bar" id="bar"></div></div>
    <div id="status"></div>
  </div>

  <!-- TAB: RECEIVE -->
  <div id="tab-receive" class="tab-content">
    <div id="file-container" class="file-list">
      <div class="empty-state">
        <svg width="40" height="40" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.5"><path d="M14.5 2H6a2 2 0 0 0-2 2v16a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2V7.5L14.5 2z"/><polyline points="14 2 14 8 20 8"/></svg>
        <div>No files shared yet by host device.</div>
      </div>
    </div>
  </div>

  <footer>Connected via Secure High-Speed Local Wi-Fi / LAN</footer>
</div>

<script>
  let selectedFiles = [];
  let pollInterval = null;

  // Drag and drop setup
  const dz = document.getElementById('dz');
  ['dragenter', 'dragover', 'dragleave', 'drop'].forEach(eventName => {
    dz.addEventListener(eventName, preventDefaults, false);
  });
  function preventDefaults(e) { e.preventDefault(); e.stopPropagation(); }

  ['dragenter', 'dragover'].forEach(e => dz.addEventListener(e, () => dz.classList.add('dragover')));
  ['dragleave', 'drop'].forEach(e => dz.addEventListener(e, () => dz.classList.remove('dragover')));
  dz.addEventListener('drop', handleDrop);

  function handleDrop(e) {
    const dt = e.dataTransfer;
    if (dt && dt.files.length) {
      selectedFiles = Array.from(dt.files);
      renderQueue();
    }
  }

  function handleFileSelect() {
    selectedFiles = Array.from(document.getElementById('fi').files);
    renderQueue();
  }

  function formatSize(bytes) {
    if (bytes === 0) return '0 B';
    const k = 1024;
    const sizes = ['B', 'KB', 'MB', 'GB'];
    const i = Math.floor(Math.log(bytes) / Math.log(k));
    return parseFloat((bytes / Math.pow(k, i)).toFixed(1)) + ' ' + sizes[i];
  }

  function renderQueue() {
    const q = document.getElementById('queue');
    const btn = document.getElementById('sbtn');
    if (selectedFiles.length === 0) {
      q.innerHTML = '';
      btn.disabled = true;
      return;
    }
    btn.disabled = false;
    q.innerHTML = selectedFiles.map((f, i) => `
      <div class="queue-item">
        <div>
          <div class="queue-name">${f.name}</div>
          <div class="queue-size">${formatSize(f.size)}</div>
        </div>
        <div style="cursor:pointer;color:#ef4444;font-weight:bold;" onclick="removeFile(${i})">✕</div>
      </div>
    `).join('');
  }

  function removeFile(index) {
    selectedFiles.splice(index, 1);
    renderQueue();
  }

  function switchTab(tab) {
    document.querySelectorAll('.tab-btn').forEach(b => b.classList.remove('active'));
    document.querySelectorAll('.tab-content').forEach(c => c.classList.remove('active'));
    if (tab === 'send') {
      document.querySelectorAll('.tab-btn')[0].classList.add('active');
      document.getElementById('tab-send').classList.add('active');
      if (pollInterval) clearInterval(pollInterval);
    } else {
      document.querySelectorAll('.tab-btn')[1].classList.add('active');
      document.getElementById('tab-receive').classList.add('active');
      fetchSharedFiles();
      if (!pollInterval) pollInterval = setInterval(fetchSharedFiles, 3000);
    }
  }

  async function uploadFiles() {
    if (!selectedFiles.length) return;
    const btn = document.getElementById('sbtn');
    const prg = document.getElementById('prg');
    const bar = document.getElementById('bar');
    const status = document.getElementById('status');

    btn.disabled = true;
    prg.style.display = 'block';
    bar.style.width = '0%';
    status.innerHTML = 'Preparing upload...';

    const formData = new FormData();
    for (const f of selectedFiles) formData.append('files', f);

    const xhr = new XMLHttpRequest();
    xhr.open('POST', '/api/webdrop/upload');

    xhr.upload.onprogress = (e) => {
      if (e.lengthComputable) {
        const pct = Math.round((e.loaded / e.total) * 100);
        bar.style.width = pct + '%';
        status.innerHTML = `Uploading ${selectedFiles.length} file(s): ${pct}% (${formatSize(e.loaded)} / ${formatSize(e.total)})`;
      }
    };

    xhr.onload = () => {
      if (xhr.status === 200) {
        status.innerHTML = `<span style="color:#00d285">✓ Files uploaded successfully! Saved to ShanuSend Downloads.</span>`;
        bar.style.width = '100%';
        selectedFiles = [];
        renderQueue();
        document.getElementById('fi').value = '';
      } else {
        status.innerHTML = `<span style="color:#f87171">Upload failed. Please check network.</span>`;
      }
    };

    xhr.onerror = () => {
      status.innerHTML = `<span style="color:#f87171">Network error during upload.</span>`;
      btn.disabled = false;
    };

    xhr.send(formData);
  }

  async function fetchSharedFiles() {
    const container = document.getElementById('file-container');
    try {
      const res = await fetch('/api/webdrop/files');
      const list = await res.json();
      if (!list || !list.length) {
        container.innerHTML = `
          <div class="empty-state">
            <svg width="40" height="40" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.5"><path d="M14.5 2H6a2 2 0 0 0-2 2v16a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2V7.5L14.5 2z"/><polyline points="14 2 14 8 20 8"/></svg>
            <div>No files shared yet by host device.</div>
          </div>`;
        return;
      }
      container.innerHTML = list.map(f => `
        <div class="file-item">
          <div class="file-info">
            <div class="file-name">${f.name}</div>
            <div class="file-meta">${formatSize(f.size)}</div>
          </div>
          <a class="dl-btn" href="/api/webdrop/download/${encodeURIComponent(f.name)}" download>
            <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5"><path d="M21 15v4a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2v-4"/><polyline points="7 10 12 15 17 10"/><line x1="12" y1="15" x2="12" y2="3"/></svg>
            Download
          </a>
        </div>
      `).join('');
    } catch (e) {
      container.innerHTML = '<div style="color:#f87171; font-size:13px; padding: 20px;">Error loading file list.</div>';
    }
  }
</script>
</body>
</html>''';

    return Response.ok(htmlContent, headers: {'content-type': 'text/html; charset=utf-8'});
  }

  void dispose() {
    _eventController.close();
    stopServer();
  }
}
