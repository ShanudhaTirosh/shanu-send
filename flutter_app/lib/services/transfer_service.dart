import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:dio/dio.dart';
import 'package:dio/io.dart';
import 'package:uuid/uuid.dart';
import '../models/device_dto.dart';
import '../models/file_dto.dart';

class TransferService {
  final Dio _dio = Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 15),
    receiveTimeout: const Duration(hours: 2),
    sendTimeout: const Duration(hours: 2),
  ));

  final _statusController = StreamController<TransferStatus>.broadcast();
  Stream<TransferStatus> get statusStream => _statusController.stream;

  CancelToken? _activeCancelToken;

  TransferService() {
    if (!kIsWeb) {
      _dio.httpClientAdapter = IOHttpClientAdapter(
        createHttpClient: () {
          final client = HttpClient();
          client.badCertificateCallback = (X509Certificate cert, String host, int port) => true;
          return client;
        },
      );
    }
  }

  void cancelActiveTransfer() {
    _activeCancelToken?.cancel('Transfer cancelled by user');
    _activeCancelToken = null;
  }

  Future<bool> sendFiles({
    required DeviceDto targetDevice,
    required List<FileDto> files,
  }) async {
    final sessionId = const Uuid().v4();
    _activeCancelToken = CancelToken();

    // 1. Prepare upload request payload
    final fileMap = <String, Map<String, dynamic>>{};
    for (var f in files) {
      fileMap[f.id] = f.toJson();
    }

    final isHttpsFirst = targetDevice.https || targetDevice.protocol.toLowerCase() == 'https';
    final schemes = isHttpsFirst ? ['https', 'http'] : ['http', 'https'];

    Response? prepareResponse;
    String activeScheme = schemes.first;

    for (final scheme in schemes) {
      final url = '$scheme://${targetDevice.ip}:${targetDevice.port}/api/localsend/v2/prepare-upload';
      try {
        final res = await _dio.post(
          url,
          data: {
            'info': {
              'alias': 'ShanuSend Pro',
              'version': '2.1',
              'deviceModel': Platform.operatingSystem,
              'deviceType': (Platform.isAndroid || Platform.isIOS) ? 'mobile' : 'desktop',
              'fingerprint': 'shanu_flutter_fp',
              'port': 53317,
              'protocol': 'http',
              'download': true,
            },
            'files': fileMap,
          },
          cancelToken: _activeCancelToken,
        );

        if (res.statusCode == 200 && res.data != null) {
          prepareResponse = res;
          activeScheme = scheme;
          break;
        }
      } catch (e) {
        debugPrint('Prepare upload attempt failed on $scheme: $e');
      }
    }

    if (prepareResponse == null || prepareResponse.data == null) {
      if (!_statusController.isClosed) {
        _statusController.add(TransferStatus(
          sessionId: sessionId,
          fileName: files.isNotEmpty ? files.first.fileName : 'Error',
          receivedBytes: 0,
          totalBytes: 0,
          speedMBps: 0.0,
          etaSeconds: 0,
          isFailed: true,
        ));
      }
      _activeCancelToken = null;
      return false;
    }

    try {
      final Map<String, dynamic> responseData = prepareResponse.data is String 
          ? jsonDecode(prepareResponse.data) 
          : Map<String, dynamic>.from(prepareResponse.data);

      final filesObj = responseData['files'];
      final tokens = <String, String>{};
      if (filesObj is Map) {
        filesObj.forEach((k, v) {
          tokens[k.toString()] = v.toString();
        });
      }

      final baseUrl = '$activeScheme://${targetDevice.ip}:${targetDevice.port}';

      // 2. Stream files safely from disk without loading full bytes into memory
      for (var file in files) {
        final token = tokens[file.id];
        if (token == null || file.path == null) continue;

        final diskFile = File(file.path!);
        if (!await diskFile.exists()) continue;

        final fileSize = await diskFile.length();
        final startTime = DateTime.now();

        await _dio.post(
          '$baseUrl/api/localsend/v2/upload',
          queryParameters: {
            'sessionId': sessionId,
            'fileId': file.id,
            'token': token,
          },
          data: diskFile.openRead(),
          cancelToken: _activeCancelToken,
          options: Options(
            headers: {
              Headers.contentLengthHeader: fileSize,
              'content-type': 'application/octet-stream',
            },
          ),
          onSendProgress: (sent, total) {
            final elapsedSec = DateTime.now().difference(startTime).inMilliseconds / 1000.0;
            final speedBytesPerSec = elapsedSec > 0.1 ? (sent / elapsedSec) : 0.0;
            final speedMBps = speedBytesPerSec / (1024 * 1024);
            final remainingBytes = total - sent;
            final etaSeconds = speedBytesPerSec > 0 ? (remainingBytes / speedBytesPerSec).round() : 0;

            if (!_statusController.isClosed) {
              _statusController.add(TransferStatus(
                sessionId: sessionId,
                fileName: file.fileName,
                receivedBytes: sent,
                totalBytes: total,
                speedMBps: double.parse(speedMBps.toStringAsFixed(2)),
                etaSeconds: etaSeconds,
                isCompleted: sent >= total,
              ));
            }
          },
        );
      }

      _activeCancelToken = null;
      return true;
    } catch (e) {
      debugPrint('Upload stream failed: $e');
      if (!_statusController.isClosed) {
        _statusController.add(TransferStatus(
          sessionId: sessionId,
          fileName: files.isNotEmpty ? files.first.fileName : 'Error',
          receivedBytes: 0,
          totalBytes: 0,
          speedMBps: 0.0,
          etaSeconds: 0,
          isFailed: true,
        ));
      }
      _activeCancelToken = null;
      return false;
    }
  }

  void dispose() {
    _statusController.close();
  }
}
