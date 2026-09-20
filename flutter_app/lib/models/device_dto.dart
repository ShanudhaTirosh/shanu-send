class DeviceDto {
  final String alias;
  final String version;
  final String deviceModel;
  final String deviceType;
  final String fingerprint;
  final int port;
  final String protocol;
  final bool download;
  final bool https;
  final String ip;

  DeviceDto({
    required this.alias,
    required this.version,
    required this.deviceModel,
    required this.deviceType,
    required this.fingerprint,
    required this.port,
    required this.protocol,
    required this.download,
    required this.https,
    required this.ip,
  });

  factory DeviceDto.fromJson(Map<String, dynamic> json, String ip) {
    return DeviceDto(
      alias: json['alias'] ?? 'Unknown Device',
      version: json['version'] ?? '2.1',
      deviceModel: json['deviceModel'] ?? json['model'] ?? 'Generic',
      deviceType: json['deviceType'] ?? 'desktop',
      fingerprint: json['fingerprint'] ?? '',
      port: json['port'] ?? 53317,
      protocol: json['protocol'] ?? 'https',
      download: json['download'] ?? true,
      https: json['https'] ?? true,
      ip: ip,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'alias': alias,
      'version': version,
      'deviceModel': deviceModel,
      'deviceType': deviceType,
      'fingerprint': fingerprint,
      'port': port,
      'protocol': protocol,
      'download': download,
      'https': https,
    };
  }
}
