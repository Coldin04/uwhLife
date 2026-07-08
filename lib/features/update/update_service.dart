import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path_provider/path_provider.dart';

import 'update_manifest.dart';

typedef DownloadProgress = void Function(int received, int? total);

class UpdateService {
  const UpdateService({HttpClient? client}) : _client = client;

  static const manifestUrls = [
    'https://raw.giteeusercontent.com/coldin04/uwhlife_source/raw/master/update.json',
    'https://raw.githubusercontent.com/coldin04/uwhLife/main/update.json',
  ];

  final HttpClient? _client;

  Future<UpdateManifest?> fetchManifest({
    List<String> urls = manifestUrls,
    Duration timeout = const Duration(seconds: 4),
  }) async {
    for (final url in urls) {
      final manifest = await _fetchOne(url, timeout);
      if (manifest != null) return manifest;
    }
    return null;
  }

  Future<File> downloadAndroidApk(
    AndroidUpdateInfo info, {
    DownloadProgress? onProgress,
  }) async {
    Object? lastError;
    for (final url in info.downloadUrls) {
      try {
        final file = await _downloadFile(url, info.versionName, onProgress);
        final valid = await verifySha256(file, info.sha256);
        if (!valid) {
          lastError = const FileSystemException('APK checksum mismatch');
          await file.delete().catchError((_) => file);
          continue;
        }
        return file;
      } catch (error) {
        lastError = error;
      }
    }
    throw StateError('下载更新失败：${lastError ?? '无可用下载地址'}');
  }

  static Future<bool> verifySha256(File file, String expected) async {
    final normalized = expected.trim().toLowerCase();
    if (normalized.isEmpty) return true;
    final digest = await sha256.bind(file.openRead()).first;
    return digest.toString().toLowerCase() == normalized;
  }

  Future<UpdateManifest?> _fetchOne(String url, Duration timeout) async {
    HttpClient? ownedClient;
    final client = _client ?? (ownedClient = HttpClient());
    try {
      final request = await client.getUrl(Uri.parse(url)).timeout(timeout);
      request.headers.set(HttpHeaders.acceptHeader, 'application/json');
      final response = await request.close().timeout(timeout);
      if (response.statusCode < 200 || response.statusCode >= 300) return null;
      final body = await response
          .transform(utf8.decoder)
          .join()
          .timeout(timeout);
      return UpdateManifest.fromJson(jsonDecode(body) as Map<String, dynamic>);
    } catch (_) {
      return null;
    } finally {
      ownedClient?.close(force: true);
    }
  }

  Future<File> _downloadFile(
    String url,
    String versionName,
    DownloadProgress? onProgress,
  ) async {
    HttpClient? ownedClient;
    final client = _client ?? (ownedClient = HttpClient());
    try {
      final request = await client.getUrl(Uri.parse(url));
      final response = await request.close();
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw HttpException('HTTP ${response.statusCode}', uri: Uri.parse(url));
      }

      final dir = await getTemporaryDirectory();
      final safeVersion = versionName.replaceAll(
        RegExp(r'[^0-9A-Za-z._-]'),
        '_',
      );
      final file = File('${dir.path}/UWHLife-$safeVersion-update.apk');
      final sink = file.openWrite();
      var received = 0;
      final total = response.contentLength >= 0 ? response.contentLength : null;
      try {
        await for (final chunk in response) {
          received += chunk.length;
          sink.add(chunk);
          onProgress?.call(received, total);
        }
      } finally {
        await sink.close();
      }
      return file;
    } finally {
      ownedClient?.close(force: true);
    }
  }
}
