// Resolves and, where possible, auto-installs the external binaries the
// Scrcpy panel depends on (`adb`, `scrcpy`) instead of assuming they're
// already on the user's PATH.
//
// Platform-tools (adb) is a static, self-contained per-OS zip published by
// Google at a stable URL — safe to automate on Windows/macOS/Linux.
//
// scrcpy itself only gets a fully automated download on Windows, where
// Genymobile publishes a self-contained zip (scrcpy.exe + adb.exe + the DLLs
// it needs). On macOS/Linux, scrcpy links against system libraries
// (ffmpeg/SDL2/AVFoundation/V4L2) that vary by OS version and distro, so a
// generic downloaded binary is not reliably going to run — this service
// detects that case and returns install instructions for the platform's
// package manager instead of pretending a silent download will work.
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

enum ToolAvailability { bundled, systemPath, missing }

class ToolPaths {
  final String? adbPath;
  final String? scrcpyPath;
  final ToolAvailability adbAvailability;
  final ToolAvailability scrcpyAvailability;

  const ToolPaths({
    required this.adbPath,
    required this.scrcpyPath,
    required this.adbAvailability,
    required this.scrcpyAvailability,
  });

  bool get isReady => adbPath != null && scrcpyPath != null;
}

class ToolBootstrapException implements Exception {
  final String message;
  const ToolBootstrapException(this.message);
  @override
  String toString() => message;
}

/// Thrown when a tool can't be auto-installed on this OS and needs a manual
/// package-manager step. [instructions] is meant to be shown verbatim to the
/// user, not parsed.
class ToolBootstrapNeedsManualInstall implements Exception {
  final String instructions;
  const ToolBootstrapNeedsManualInstall(this.instructions);
  @override
  String toString() => instructions;
}

class ToolBootstrapService {
  static const _scrcpyLatestReleaseApi =
      'https://api.github.com/repos/Genymobile/scrcpy/releases/latest';
  static const _platformToolsBase =
      'https://dl.google.com/android/repository';

  final Dio _dio = Dio();

  String get _adbExeName => Platform.isWindows ? 'adb.exe' : 'adb';
  String get _scrcpyExeName => Platform.isWindows ? 'scrcpy.exe' : 'scrcpy';

  Future<Directory> _toolsDir() async {
    final support = await getApplicationSupportDirectory();
    final dir = Directory(p.join(support.path, 'tools'));
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  /// Checks bundled + system PATH only — no network calls. Call this first
  /// so the UI can show "ready" immediately without a spinner.
  Future<ToolPaths> resolve() async {
    final dir = await _toolsDir();

    final bundledAdb = File(p.join(dir.path, 'platform-tools', _adbExeName));
    String? adbPath;
    var adbAvail = ToolAvailability.missing;
    if (await bundledAdb.exists()) {
      adbPath = bundledAdb.path;
      adbAvail = ToolAvailability.bundled;
    } else {
      final systemAdb = await _which('adb');
      if (systemAdb != null) {
        adbPath = systemAdb;
        adbAvail = ToolAvailability.systemPath;
      }
    }

    final bundledScrcpy = File(p.join(dir.path, 'scrcpy', _scrcpyExeName));
    String? scrcpyPath;
    var scrcpyAvail = ToolAvailability.missing;
    if (await bundledScrcpy.exists()) {
      scrcpyPath = bundledScrcpy.path;
      scrcpyAvail = ToolAvailability.bundled;
    } else {
      final systemScrcpy = await _which('scrcpy');
      if (systemScrcpy != null) {
        scrcpyPath = systemScrcpy;
        scrcpyAvail = ToolAvailability.systemPath;
      }
    }

    return ToolPaths(
      adbPath: adbPath,
      scrcpyPath: scrcpyPath,
      adbAvailability: adbAvail,
      scrcpyAvailability: scrcpyAvail,
    );
  }

  Future<String?> _which(String bin) async {
    try {
      final result =
          await Process.run(Platform.isWindows ? 'where' : 'which', [bin]);
      if (result.exitCode == 0) {
        final out = (result.stdout as String).trim().split('\n').first.trim();
        if (out.isNotEmpty) return out;
      }
    } catch (_) {
      // `where`/`which` not available — treat as "not found", not fatal.
    }
    return null;
  }

  /// Downloads Android platform-tools (adb) for the current OS if it isn't
  /// already bundled or on PATH. [onLicenseConsent] must resolve `true`
  /// before any download starts — redistributing platform-tools is bound to
  /// Google's Android SDK Terms and Conditions, so silently downloading it
  /// without the user agreeing isn't acceptable.
  Future<String> ensureAdb({
    required Future<bool> Function() onLicenseConsent,
    void Function(double progress)? onProgress,
  }) async {
    final dir = await _toolsDir();
    final target = File(p.join(dir.path, 'platform-tools', _adbExeName));
    if (await target.exists()) return target.path;

    final systemAdb = await _which('adb');
    if (systemAdb != null) return systemAdb;

    if (!await onLicenseConsent()) {
      throw const ToolBootstrapException(
          'Android SDK Platform-Tools license was not accepted.');
    }

    final osSegment =
        Platform.isWindows ? 'windows' : (Platform.isMacOS ? 'darwin' : 'linux');
    final url = '$_platformToolsBase/platform-tools-latest-$osSegment.zip';
    final zipPath = p.join(dir.path, 'platform-tools-$osSegment.zip');

    await _download(url, zipPath, onProgress: onProgress);
    await _extractZip(zipPath, dir.path);
    await File(zipPath).delete();

    if (!Platform.isWindows) {
      await Process.run('chmod', ['+x', target.path]);
    }
    if (!await target.exists()) {
      throw ToolBootstrapException(
          'adb did not extract to the expected location: ${target.path}');
    }
    return target.path;
  }

  /// Downloads scrcpy for the current OS if it isn't already bundled or on
  /// PATH. Only fully automated on Windows — see the file-level comment.
  Future<String> ensureScrcpy({
    required Future<bool> Function() onLicenseConsent,
    void Function(double progress)? onProgress,
  }) async {
    final dir = await _toolsDir();
    final target = File(p.join(dir.path, 'scrcpy', _scrcpyExeName));
    if (await target.exists()) return target.path;

    final systemScrcpy = await _which('scrcpy');
    if (systemScrcpy != null) return systemScrcpy;

    if (Platform.isMacOS) {
      throw const ToolBootstrapNeedsManualInstall(
        "scrcpy isn't installed. Install it once with Homebrew, then reopen "
        'this panel:\n\nbrew install scrcpy',
      );
    }
    if (Platform.isLinux) {
      throw const ToolBootstrapNeedsManualInstall(
        "scrcpy isn't installed. Install it with your package manager, then "
        'reopen this panel:\n\n'
        '  Debian/Ubuntu:  sudo apt install scrcpy\n'
        '  Fedora:         sudo dnf install scrcpy\n'
        '  Arch:           sudo pacman -S scrcpy\n'
        '  Flatpak:        flatpak install flathub com.genymobile.Scrcpy',
      );
    }
    // Windows from here on.
    if (!await onLicenseConsent()) {
      throw const ToolBootstrapException(
          'scrcpy download was not confirmed.');
    }

    final asset = await _findWindowsScrcpyAsset();
    final zipPath = p.join(dir.path, 'scrcpy-download.zip');
    await _download(asset.downloadUrl, zipPath, onProgress: onProgress);

    final scrcpyDir = Directory(p.join(dir.path, 'scrcpy'));
    if (await scrcpyDir.exists()) await scrcpyDir.delete(recursive: true);
    await _extractZip(zipPath, dir.path,
        flattenSingleRootDir: true, renameRootTo: 'scrcpy');
    await File(zipPath).delete();

    if (!await target.exists()) {
      throw ToolBootstrapException(
          'scrcpy did not extract to the expected location: ${target.path}');
    }
    return target.path;
  }

  Future<_GithubAsset> _findWindowsScrcpyAsset() async {
    final response = await _dio.get<Map<String, dynamic>>(
      _scrcpyLatestReleaseApi,
      options: Options(headers: {'Accept': 'application/vnd.github+json'}),
    );
    final assets =
        (response.data?['assets'] as List<dynamic>? ?? []).cast<Map<String, dynamic>>();

    Map<String, dynamic> pick(RegExp pattern) => assets.firstWhere(
          (a) => pattern.hasMatch(a['name'] as String? ?? ''),
          orElse: () => throw const ToolBootstrapException(
              'No matching Windows scrcpy release asset was found — the '
              'release naming may have changed upstream.'),
        );

    // Prefer 64-bit; fall back to 32-bit if that's all this release has.
    Map<String, dynamic> match;
    try {
      match = pick(RegExp(r'^scrcpy-win64-v[\d.]+\.zip$'));
    } on ToolBootstrapException {
      match = pick(RegExp(r'^scrcpy-win32-v[\d.]+\.zip$'));
    }

    return _GithubAsset(downloadUrl: match['browser_download_url'] as String);
  }

  Future<void> _download(
    String url,
    String destPath, {
    void Function(double progress)? onProgress,
    String? expectedSha256,
  }) async {
    await _dio.download(
      url,
      destPath,
      onReceiveProgress: (received, total) {
        if (total > 0 && onProgress != null) onProgress(received / total);
      },
    );
    // Verify integrity whenever a checksum is available. Neither Google's
    // platform-tools endpoint nor GitHub's release API reliably exposes a
    // per-asset checksum today, so this is best-effort — both downloads are
    // still over HTTPS to a fixed, known host, which is the floor, not the
    // ceiling, of the integrity guarantee here.
    if (expectedSha256 != null) {
      final bytes = await File(destPath).readAsBytes();
      final digest = sha256.convert(bytes).toString();
      if (digest.toLowerCase() != expectedSha256.toLowerCase()) {
        await File(destPath).delete();
        throw ToolBootstrapException(
            'Checksum mismatch for $url — refusing to install an unverified download.');
      }
    }
  }

  Future<void> _extractZip(
    String zipPath,
    String destDir, {
    bool flattenSingleRootDir = false,
    String? renameRootTo,
  }) async {
    final bytes = await File(zipPath).readAsBytes();
    final archive = ZipDecoder().decodeBytes(bytes);

    String stripRoot(String path) {
      if (!flattenSingleRootDir) return path;
      final parts = p.split(path);
      return parts.length > 1 ? p.joinAll(parts.sublist(1)) : path;
    }

    final baseOut = renameRootTo != null ? p.join(destDir, renameRootTo) : destDir;
    for (final entry in archive) {
      final relative = stripRoot(entry.name);
      if (relative.isEmpty) continue;
      final outPath = p.join(baseOut, relative);
      if (entry.isFile) {
        final outFile = File(outPath);
        await outFile.create(recursive: true);
        await outFile.writeAsBytes(entry.content as List<int>);
      } else {
        await Directory(outPath).create(recursive: true);
      }
    }
  }
}

class _GithubAsset {
  final String downloadUrl;
  const _GithubAsset({required this.downloadUrl});
}
