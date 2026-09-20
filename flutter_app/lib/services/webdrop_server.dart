import 'dart:io';
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as io;
import 'package:shelf_router/shelf_router.dart';

class WebDropServer {
  HttpServer? _server;
  int get port => _server?.port ?? 53317;

  Future<void> startServer() async {
    final app = Router();

    app.get('/', _webDropHandler);
    app.get('/webdrop', _webDropHandler);

    final handler = const Pipeline()
        .addMiddleware(logRequests())
        .addHandler(app.call);

    try {
      _server = await io.serve(handler, InternetAddress.anyIPv4, 53317);
    } catch (_) {
      // Port might already be bound or in use
    }
  }

  Response _webDropHandler(Request request) {
    const htmlContent = r'''<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8"><meta name="viewport" content="width=device-width, initial-scale=1.0">
<title>ShanuSend WebDrop</title>
<style>
  body { font-family: system-ui, -apple-system, sans-serif; background: #0b0f19; color: #f8fafc; display: flex; flex-direction: column; align-items: center; justify-content: center; min-height: 100vh; margin: 0; padding: 20px; }
  .card { background: #161e2e; border: 1px solid #283548; border-radius: 20px; padding: 36px; max-width: 480px; width: 100%; text-align: center; box-shadow: 0 25px 50px -12px rgba(0,0,0,0.6); }
  h1 { font-size: 24px; margin: 0 0 8px 0; display: flex; align-items: center; justify-content: center; gap: 8px; background: linear-gradient(135deg, #38bdf8, #818cf8); -webkit-background-clip: text; -webkit-text-fill-color: transparent; }
  p { color: #94a3b8; font-size: 14px; margin: 0 0 24px 0; }
  .dropzone { border: 2px dashed #334155; border-radius: 14px; padding: 40px 20px; cursor: pointer; transition: all 0.2s; background: #0f172a; display: flex; flex-direction: column; align-items: center; }
  .dropzone:hover { border-color: #6366f1; background: #1e1b4b; }
  .btn { background: linear-gradient(135deg, #6366f1, #4f46e5); color: white; border: none; padding: 14px 24px; border-radius: 10px; font-weight: 600; cursor: pointer; width: 100%; margin-top: 20px; font-size: 16px; transition: opacity 0.2s; }
  .btn:disabled { opacity: 0.4; cursor: not-allowed; }
  .icon-svg { width: 44px; height: 44px; stroke: #38bdf8; fill: none; stroke-width: 2; stroke-linecap: round; stroke-linejoin: round; }
  .icon-small { width: 20px; height: 20px; vertical-align: middle; }
</style>
</head>
<body>
<div class="card">
  <h1>
    <svg class="icon-small" viewBox="0 0 24 24" fill="none" stroke="#38bdf8" stroke-width="2.5" stroke-linecap="round" stroke-linejoin="round"><polygon points="13 2 3 14 12 14 11 22 21 10 12 10 13 2"/></svg>
    ShanuSend WebDrop
  </h1>
  <p>AirDrop & Nearby Share Portal. Send files directly to this device from Safari / Chrome!</p>
  <div class="dropzone" id="dz" onclick="document.getElementById('fi').click()">
    <svg class="icon-svg" viewBox="0 0 24 24"><path d="M22 19a2 2 0 0 1-2 2H4a2 2 0 0 1-2-2V5a2 2 0 0 1 2-2h5l2 3h9a2 2 0 0 1 2 2z"/></svg>
    <div style="margin-top: 12px; font-weight: 500; color: #cbd5e1;">Tap or Drag files here to send</div>
  </div>
  <input type="file" id="fi" multiple style="display:none">
  <button class="btn" id="sbtn" disabled>Select Files to Send</button>
</div>
</body>
</html>''';

    return Response.ok(htmlContent, headers: {'content-type': 'text/html; charset=utf-8'});
  }

  Future<void> stopServer() async {
    await _server?.close();
  }
}
