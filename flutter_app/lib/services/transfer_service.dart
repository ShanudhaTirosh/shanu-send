import 'dart:async';
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:uuid/uuid.dart';
import '../models/device_dto.dart';
import '../models/file_dto.dart';

class TransferService {
  final Dio _dio = Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 10),
    receiveTimeout: const Duration(minutes: 60),
  ));

  final _statusController = StreamController<TransferStatus>.broadcast();
  Stream<TransferStatus> get statusStream => _statusController.stream;

  Future<bool> sendFiles({
    required DeviceDto targetDevice,
    required List<FileDto> files,
  }) async {
    final sessionId = const Uuid().v4();
    final baseUrl = 'http://${targetDevice.ip}:${targetDevice.port}';

    // 1. Prepare upload request
    final fileMap = <String, Map<String, dynamic>>{};
    for (var f in files) {
      fileMap[f.id] = f.toJson();
    }

    try {
      final prepareResponse = await _dio.post(
        '$baseUrl/api/localsend/v2/prepare-upload',
        data: {
          'info': {
            'alias': 'ShanuSend Flutter',
            'version': '2.1',
            'deviceModel': Platform.operatingSystem,
            'deviceType': 'desktop',
            'fingerprint': 'shanu_flutter_fp',
            'port': 53317,
            'protocol': 'http',
            'download': true,
          },
          'files': fileMap,
        },
      );

      if (prepareResponse.statusCode != 200 || prepareResponse.data == null) {
        return false;
      }

      final responseData = Map<String, dynamic>.from(prepareResponse.data);
      final tokens = Map<String, String>.from(responseData['files'] ?? {});

      // 2. Stream files chunked with live speed meter
      for (var file in files) {
        final token = tokens[file.id];
        if (token == null || file.path == null) continue;

        final diskFile = File(file.path!);
        final fileSize = await diskFile.length();
        final startTime = DateTime.now();

        await _dio.post(
          '$baseUrl/api/localsend/v2/upload',
          queryParameters: {
            'sessionId': sessionId,
            'fileId': file.id,
            'token': token,
          },
          data: diskFile.openRead(), // Zero-copy chunked byte stream
          options: Options(
            headers: {
              Headers.contentLengthHeader: fileSize,
              'content-type': 'application/octet-stream',
            },
          ),
          onSendProgress: (sent, total) {
            final elapsed = DateTime.now().difference(startTime).inMilliseconds / 1000.0;
            final speedBytesPerSec = elapsed > 0 ? (sent / elapsed) : 0.0;
            final speedMBps = speedBytesPerSec / (1024 * 1024);
            final remainingBytes = total - sent;
            final etaSeconds = speedBytesPerSec > 0 ? (remainingBytes / speedBytesPerSec).round() : 0;

            _statusController.add(TransferStatus(
              sessionId: sessionId,
              fileName: file.fileName,
              receivedBytes: sent,
              totalBytes: total,
              speedMBps: speedMBps,
              etaSeconds: etaSeconds,
              isCompleted: sent >= total,
            ));
          },
        );
      }

      return true;
    } catch (e) {
      _statusController.add(TransferStatus(
        sessionId: sessionId,
        fileName: files.isNotEmpty ? files.first.fileName : 'Error',
        receivedBytes: 0,
        totalBytes: 0,
        speedMBps: 0.0,
        etaSeconds: 0,
        isFailed: true,
      ));
      return false;
    }
  }

  void dispose() {
    _statusController.close();
  }
}
