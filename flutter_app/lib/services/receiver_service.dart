import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
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

class ReceiverService {
  HttpServer? _server;
  final _eventController = StreamController<ReceiverEvent>.broadcast();
  final Map<String, ReceiverSession> _sessions = {};
  
  String alias = 'ShanuSend Phone';
  String fingerprint = 'shanu_mobile_fp';
  int port = 53317;

  Stream<ReceiverEvent> get eventStream => _eventController.stream;
  bool get isRunning => _server != null;

  Future<void> startServer({int port = 53317, String? customAlias}) async {
    if (_server != null) return;
    this.port = port;
    if (customAlias != null && customAlias.isNotEmpty) {
      alias = customAlias;
    }

    final app = Router();

    app.get('/api/localsend/v2/info', _handleInfo);
    app.post('/api/localsend/v2/register', _handleRegister);
    app.post('/api/localsend/v2/prepare-upload', _handlePrepareUpload);
    app.post('/api/localsend/v2/upload', _handleUpload);
    app.post('/api/localsend/v2/cancel', _handleCancel);

    final handler = Pipeline().addMiddleware(logRequests()).addHandler(app.call);

    try {
      _server = await shelf_io.serve(handler, InternetAddress.anyIPv4, port);
      debugPrint('ShanuSend Mobile LocalSend Receiver running on port ${_server!.port}');
    } catch (e) {
      debugPrint('Failed to start LocalSend receiver server: $e');
    }
  }

  Future<void> stopServer() async {
    await _server?.close(force: true);
    _server = null;
  }

  Response _handleInfo(Request request) {
    return Response.ok(
      jsonEncode({
        'alias': alias,
        'version': '2.1',
        'deviceModel': 'Mobile',
        'deviceType': 'mobile',
        'fingerprint': fingerprint,
        'port': port,
        'protocol': 'http',
        'download': false,
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

      _eventController.add(ReceiverEvent('incoming-request', {
        'sessionId': sessionId,
        'senderAlias': senderAlias,
        'files': files,
      }));

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
      final savePath = '${dir.path}/$fileName';
      final file = File(savePath);
      final sink = file.openWrite();

      int receivedBytes = 0;
      await for (var chunk in request.read()) {
        sink.add(chunk);
        receivedBytes += chunk.length;

        _eventController.add(ReceiverEvent('upload-progress', {
          'sessionId': sessionId,
          'fileId': fileId,
          'receivedBytes': receivedBytes,
          'totalBytes': fileSize,
        }));
      }

      await sink.flush();
      await sink.close();

      _eventController.add(ReceiverEvent('upload-complete', {
        'sessionId': sessionId,
        'fileId': fileId,
        'savePath': savePath,
        'fileName': fileName,
      }));

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

  void dispose() {
    _eventController.close();
    stopServer();
  }
}
