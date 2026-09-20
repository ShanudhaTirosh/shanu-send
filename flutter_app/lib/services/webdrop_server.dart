import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as io;
import 'package:shelf_router/shelf_router.dart';

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

class WebDropServer {
  HttpServer? _server;
  int get port => _server?.port ?? 53317;

  final List<WebDropSharedFile> _sharedFiles = [];
  final Function(String fileName, String savedPath)? onFileReceived;

  WebDropServer({this.onFileReceived});

  void addSharedFile(File file) {
    final name = p.basename(file.path);
    final size = file.lengthSync();
    _sharedFiles.removeWhere((f) => f.name == name);
    _sharedFiles.add(WebDropSharedFile(name: name, path: file.path, size: size));
  }

  void clearSharedFiles() {
    _sharedFiles.clear();
  }

  Future<void> startServer() async {
    final app = Router();

    app.get('/', _webDropHandler);
    app.get('/webdrop', _webDropHandler);
    app.get('/api/webdrop/files', _getFilesHandler);
    app.get('/api/webdrop/download/<filename>', _downloadFileHandler);
    app.post('/api/webdrop/upload', _uploadHandler);

    final handler = const Pipeline()
        .addMiddleware(logRequests())
        .addHandler(app.call);

    try {
      _server = await io.serve(handler, InternetAddress.anyIPv4, 53317);
    } catch (_) {
      // Port might already be bound or in use
    }
  }

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

  Future<Response> _uploadHandler(Request request) async {
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

      Directory saveDir;
      if (Platform.isAndroid) {
        saveDir = Directory('/storage/emulated/0/Download/ShanuSend');
        if (!await saveDir.exists()) {
          saveDir = await getApplicationDocumentsDirectory();
        }
      } else {
        final docs = await getApplicationDocumentsDirectory();
        saveDir = Directory(p.join(docs.path, 'ShanuSendDownloads'));
      }
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

            onFileReceived?.call(fileName, destPath);
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

  Response _webDropHandler(Request request) {
    const htmlContent = r'''<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<title>ShanuSend AirDrop Portal</title>
<style>
  :root {
    --bg-dark: #0b0f19;
    --card-bg: #161e2e;
    --border-color: #283548;
    --accent: #38bdf8;
    --indigo: #6366f1;
    --text-primary: #f8fafc;
    --text-muted: #94a3b8;
  }
  * { box-sizing: border-box; }
  body { font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, Helvetica, Arial, sans-serif; background: var(--bg-dark); color: var(--text-primary); display: flex; flex-direction: column; align-items: center; justify-content: center; min-height: 100vh; margin: 0; padding: 16px; }
  .card { background: var(--card-bg); border: 1px solid var(--border-color); border-radius: 24px; padding: 32px 24px; max-width: 480px; width: 100%; text-align: center; box-shadow: 0 25px 50px -12px rgba(0,0,0,0.6); }
  h1 { font-size: 22px; margin: 0 0 6px 0; display: flex; align-items: center; justify-content: center; gap: 8px; background: linear-gradient(135deg, #38bdf8, #818cf8); -webkit-background-clip: text; -webkit-text-fill-color: transparent; }
  p { color: var(--text-muted); font-size: 13px; margin: 0 0 20px 0; }
  
  .nav-tabs { display: flex; background: #0f172a; padding: 4px; border-radius: 14px; margin-bottom: 20px; border: 1px solid var(--border-color); }
  .tab-btn { flex: 1; padding: 10px; border: none; background: transparent; color: var(--text-muted); font-weight: 600; font-size: 14px; border-radius: 10px; cursor: pointer; transition: all 0.2s; }
  .tab-btn.active { background: #1e293b; color: var(--text-primary); box-shadow: 0 2px 8px rgba(0,0,0,0.2); }

  .tab-content { display: none; }
  .tab-content.active { display: block; }

  .dropzone { border: 2px dashed #334155; border-radius: 16px; padding: 36px 20px; cursor: pointer; transition: all 0.2s; background: #0f172a; display: flex; flex-direction: column; align-items: center; }
  .dropzone:hover { border-color: var(--indigo); background: #1e1b4b; }
  
  .btn { background: linear-gradient(135deg, #6366f1, #4f46e5); color: white; border: none; padding: 14px 24px; border-radius: 12px; font-weight: 600; cursor: pointer; width: 100%; margin-top: 16px; font-size: 15px; transition: opacity 0.2s; }
  .btn:disabled { opacity: 0.4; cursor: not-allowed; }
  
  .progress { width: 100%; background: #1e293b; border-radius: 999px; height: 8px; margin-top: 16px; overflow: hidden; display: none; }
  .bar { height: 100%; background: linear-gradient(90deg, #38bdf8, #818cf8); width: 0%; transition: width 0.1s; }
  #status { margin-top: 12px; font-size: 13px; font-weight: 500; color: var(--accent); }

  .file-list { display: flex; flex-direction: column; gap: 10px; text-align: left; max-height: 240px; overflow-y: auto; }
  .file-item { display: flex; align-items: center; justify-content: space-between; background: #0f172a; padding: 12px 16px; border-radius: 12px; border: 1px solid var(--border-color); }
  .file-info { display: flex; flex-direction: column; overflow: hidden; }
  .file-name { font-size: 14px; font-weight: 500; color: #e2e8f0; white-space: nowrap; overflow: hidden; text-overflow: ellipsis; max-width: 260px; }
  .file-size { font-size: 12px; color: var(--text-muted); }
  .dl-btn { background: #1e293b; color: var(--accent); border: 1px solid var(--border-color); padding: 6px 12px; border-radius: 8px; font-size: 12px; font-weight: 600; text-decoration: none; cursor: pointer; transition: background 0.2s; }
  .dl-btn:hover { background: #334155; color: white; }

  .icon-svg { width: 44px; height: 44px; stroke: var(--accent); fill: none; stroke-width: 2; stroke-linecap: round; stroke-linejoin: round; }
  .icon-small { width: 20px; height: 20px; vertical-align: middle; }
</style>
</head>
<body>
<div class="card">
  <h1>
    <svg class="icon-small" viewBox="0 0 24 24" fill="none" stroke="#38bdf8" stroke-width="2.5" stroke-linecap="round" stroke-linejoin="round"><polygon points="13 2 3 14 12 14 11 22 21 10 12 10 13 2"/></svg>
    ShanuSend WebDrop
  </h1>
  <p>Send and Receive files on Apple iOS / Mac Safari without installing any app.</p>

  <div class="nav-tabs">
    <button class="tab-btn active" onclick="switchTab('send')">Send to Device</button>
    <button class="tab-btn" onclick="switchTab('receive')">Receive Files</button>
  </div>

  <div id="tab-send" class="tab-content active">
    <div class="dropzone" id="dz" onclick="document.getElementById('fi').click()">
      <svg class="icon-svg" viewBox="0 0 24 24"><path d="M22 19a2 2 0 0 1-2 2H4a2 2 0 0 1-2-2V5a2 2 0 0 1 2-2h5l2 3h9a2 2 0 0 1 2 2z"/></svg>
      <div style="margin-top: 12px; font-weight: 500; color: #cbd5e1;">Tap or Drag files here to send</div>
    </div>
    <input type="file" id="fi" multiple style="display:none" onchange="updateFiles()">
    <button class="btn" id="sbtn" onclick="upload()" disabled>Send Files</button>
    <div class="progress" id="prg"><div class="bar" id="bar"></div></div>
    <div id="status"></div>
  </div>

  <div id="tab-receive" class="tab-content">
    <div id="file-container" class="file-list">
      <div style="color:var(--text-muted); font-size:13px; padding: 20px;">No files shared yet by host device.</div>
    </div>
  </div>
</div>

<script>
  let files = [];
  function switchTab(tab) {
    document.querySelectorAll('.tab-btn').forEach(b => b.classList.remove('active'));
    document.querySelectorAll('.tab-content').forEach(c => c.classList.remove('active'));
    if (tab === 'send') {
      document.querySelectorAll('.tab-btn')[0].classList.add('active');
      document.getElementById('tab-send').classList.add('active');
    } else {
      document.querySelectorAll('.tab-btn')[1].classList.add('active');
      document.getElementById('tab-receive').classList.add('active');
      fetchSharedFiles();
    }
  }

  function updateFiles() {
    files = Array.from(document.getElementById('fi').files);
    if(files.length > 0) {
      document.getElementById('dz').innerHTML = `<svg class="icon-svg" viewBox="0 0 24 24"><path d="M14.5 2H6a2 2 0 0 0-2 2v16a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2V7.5L14.5 2z"/><polyline points="14 2 14 8 20 8"/></svg><div style="margin-top:12px;font-weight:600;color:#e2e8f0">${files.length} file(s) selected</div>`;
      document.getElementById('sbtn').disabled = false;
    }
  }

  async function upload() {
    if(!files.length) return;
    document.getElementById('sbtn').disabled = true;
    document.getElementById('prg').style.display = 'block';
    const status = document.getElementById('status');
    const formData = new FormData();
    for(const f of files) formData.append('files', f);
    
    const xhr = new XMLHttpRequest();
    xhr.open('POST', '/api/webdrop/upload');
    xhr.upload.onprogress = (e) => {
      if(e.lengthComputable) {
        const pct = Math.round((e.loaded / e.total) * 100);
        document.getElementById('bar').style.width = pct + '%';
        status.innerHTML = `Uploading: ${pct}% (${(e.loaded/1048576).toFixed(1)} MB / ${(e.total/1048576).toFixed(1)} MB)`;
      }
    };
    xhr.onload = () => {
      if(xhr.status === 200) {
        status.innerHTML = `<span style="color:#34d399">Files transferred successfully!</span>`;
        document.getElementById('bar').style.width = '100%';
        files = [];
      } else {
        status.innerHTML = `<span style="color:#f87171">Upload failed</span>`;
      }
    };
    xhr.send(formData);
  }

  async function fetchSharedFiles() {
    const container = document.getElementById('file-container');
    try {
      const res = await fetch('/api/webdrop/files');
      const list = await res.json();
      if(!list || !list.length) {
        container.innerHTML = '<div style="color:var(--text-muted); font-size:13px; padding: 20px;">No files shared yet by host device.</div>';
        return;
      }
      container.innerHTML = list.map(f => `
        <div class="file-item">
          <div class="file-info">
            <div class="file-name">${f.name}</div>
            <div class="file-size">${(f.size / 1048576).toFixed(1)} MB</div>
          </div>
          <a class="dl-btn" href="/api/webdrop/download/${encodeURIComponent(f.name)}" download>Download</a>
        </div>
      `).join('');
    } catch(e) {
      container.innerHTML = '<div style="color:#f87171; font-size:13px;">Error loading file list.</div>';
    }
  }
</script>
</body>
</html>''';

    return Response.ok(htmlContent, headers: {'content-type': 'text/html; charset=utf-8'});
  }

  Future<void> stopServer() async {
    await _server?.close();
  }
}

