class FileDto {
  final String id;
  final String fileName;
  final int size;
  final String fileType;
  final String? sha256;
  final String? preview;
  final String? path; // Local path if sending

  FileDto({
    required this.id,
    required this.fileName,
    required this.size,
    required this.fileType,
    this.sha256,
    this.preview,
    this.path,
  });

  factory FileDto.fromJson(Map<String, dynamic> json) {
    return FileDto(
      id: json['id'] ?? '',
      fileName: json['fileName'] ?? json['name'] ?? 'file.bin',
      size: json['size'] ?? 0,
      fileType: json['fileType'] ?? 'other',
      sha256: json['sha256'],
      preview: json['preview'],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'fileName': fileName,
      'size': size,
      'fileType': fileType,
      if (sha256 != null) 'sha256': sha256,
      if (preview != null) 'preview': preview,
    };
  }
}

class TransferStatus {
  final String sessionId;
  final String fileName;
  final int receivedBytes;
  final int totalBytes;
  final double speedMBps;
  final int etaSeconds;
  final bool isCompleted;
  final bool isFailed;

  TransferStatus({
    required this.sessionId,
    required this.fileName,
    required this.receivedBytes,
    required this.totalBytes,
    required this.speedMBps,
    required this.etaSeconds,
    this.isCompleted = false,
    this.isFailed = false,
  });

  double get progress => totalBytes > 0 ? (receivedBytes / totalBytes).clamp(0.0, 1.0) : 0.0;
}
