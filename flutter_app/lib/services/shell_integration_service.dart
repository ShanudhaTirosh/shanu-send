import 'dart:io' show Platform, Process;

class ShellIntegrationService {
  static const String _regKeyPath = r'HKCU\Software\Classes\*\shell\ShanuSend';
  static const String _commandKeyPath = r'HKCU\Software\Classes\*\shell\ShanuSend\command';

  static bool get isWindows => Platform.isWindows;

  static Future<bool> isContextMenuRegistered() async {
    if (!isWindows) return false;
    try {
      final result = await Process.run('reg', ['query', _regKeyPath]);
      return result.exitCode == 0;
    } catch (_) {
      return false;
    }
  }

  static Future<bool> registerContextMenu() async {
    if (!isWindows) return false;
    try {
      final exePath = Platform.resolvedExecutable;

      // Add main menu key with icon and label
      final res1 = await Process.run('reg', [
        'add',
        _regKeyPath,
        '/ve',
        '/d',
        'Send with ShanuSend',
        '/f',
      ]);

      if (res1.exitCode != 0) return false;

      await Process.run('reg', [
        'add',
        _regKeyPath,
        '/v',
        'Icon',
        '/d',
        '"$exePath"',
        '/f',
      ]);

      // Add command key
      final res2 = await Process.run('reg', [
        'add',
        _commandKeyPath,
        '/ve',
        '/d',
        '"$exePath" "%1"',
        '/f',
      ]);

      return res2.exitCode == 0;
    } catch (_) {
      return false;
    }
  }

  static Future<bool> unregisterContextMenu() async {
    if (!isWindows) return false;
    try {
      final result = await Process.run('reg', [
        'delete',
        _regKeyPath,
        '/f',
      ]);
      return result.exitCode == 0;
    } catch (_) {
      return false;
    }
  }
}
