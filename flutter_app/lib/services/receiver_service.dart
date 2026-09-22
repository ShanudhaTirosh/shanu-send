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

class ReceiverService {
  HttpServer? _server;
  final _eventController = StreamController<ReceiverEvent>.broadcast();
  final Map<String, ReceiverSession> _sessions = {};
  final Map<String, Completer<bool>> _pendingDecisions = {};

  String alias = 'ShanuSend Mobile';
  String fingerprint = '';
  int port = 53317;

  Stream<ReceiverEvent> get eventStream => _eventController.stream;
  bool get isRunning => _server != null;

  /// The UI must call this in response to an 'incoming-request' event.
  void respondToRequest(String sessionId, bool accept) {
    final completer = _pendingDecisions.remove(sessionId);
    if (completer != null && !completer.isCompleted) {
      completer.complete(accept);
    }
  }

  Future<void> _initFingerprint() async {
    if (fingerprint.isEmpty) {
      final docDir = await getApplicationDocumentsDirectory();
      final fpFile = File('${docDir.path}/.shanu_fingerprint');
      if (await fpFile.exists()) {
        fingerprint = await fpFile.readAsString();
      } else {
        final newFp = 'shanu_fp_${const Uuid().v4().replaceAll("-", "").substring(0, 16)}';
        await fpFile.writeAsString(newFp);
        fingerprint = newFp;
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
      final completer = Completer<bool>();
      _pendingDecisions[sessionId] = completer;

      if (!_eventController.isClosed) {
        _eventController.add(ReceiverEvent('incoming-request', {
          'sessionId': sessionId,
          'senderAlias': senderAlias,
          'files': files,
        }));
      }

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

  void dispose() {
    _eventController.close();
    stopServer();
  }
}
