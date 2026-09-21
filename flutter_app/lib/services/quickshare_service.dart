import 'dart:async';
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

class QuickShareService {
  final Dio _dio = Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 5),
    receiveTimeout: const Duration(minutes: 30),
  ));

  Future<bool> sendFileQuickShare({
    required String targetIp,
    required int targetPort,
    required String deviceName,
    required String fileName,
    required File file,
  }) async {
    try {
      final prepareUrl = 'http://$targetIp:$targetPort/api/quickshare/v1/prepare-upload';
      final fileSize = await file.length();

      final prepareResponse = await _dio.post(
        prepareUrl,
        data: {
          'sender_name': deviceName,
          'file_name': fileName,
          'file_size': fileSize,
        },
      );

      if (prepareResponse.statusCode == 200) {
        final uploadUrl = 'http://$targetIp:$targetPort/api/quickshare/v1/upload';
        final uploadResponse = await _dio.post(
          uploadUrl,
          data: file.openRead(),
          options: Options(
            headers: {
              Headers.contentLengthHeader: fileSize,
              'content-type': 'application/octet-stream',
            },
          ),
        );
        return uploadResponse.statusCode == 200;
      }
      return false;
    } catch (e) {
      debugPrint('QuickShare send error: $e');
      return false;
    }
  }
}
