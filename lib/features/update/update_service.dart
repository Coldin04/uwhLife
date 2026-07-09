import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path_provider/path_provider.dart';
import 'package:flutter/services.dart';

import 'update_manifest.dart';

typedef DownloadProgress = void Function(int received, int? total);

class UpdateService {
  const UpdateService({HttpClient? client, Directory? cacheDirectory})
    : _client = client,
      _cacheDirectory = cacheDirectory;

  static const manifestUrls = [
    'https://raw.giteeusercontent.com/coldin04/uwhlife_source/raw/master/update.json',
    'https://raw.githubusercontent.com/coldin04/uwhLife/main/update.json',
  ];

  final HttpClient? _client;
  final Directory? _cacheDirectory;

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
    final supportedAbis = await currentAndroidAbis();
    await cleanupStaleAndroidApks(keep: info, supportedAbis: supportedAbis);
    final cached = await cachedAndroidApk(info, supportedAbis: supportedAbis);
    if (cached != null) {
      final length = await cached.length();
      onProgress?.call(length, length);
      return cached;
    }

    Object? lastError;
    for (final url in info.downloadUrlsFor(supportedAbis)) {
      try {
        final file = await _downloadFile(
          url,
          info.versionName,
          info.selectedAbi(supportedAbis),
          onProgress,
        );
        final valid = await verifySha256(file, info.sha256For(supportedAbis));
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

  Future<File?> cachedAndroidApk(
    AndroidUpdateInfo info, {
    List<String> supportedAbis = const [],
  }) async {
    final file = await androidApkCacheFile(info, supportedAbis: supportedAbis);
    if (!await file.exists()) return null;
    final valid = await verifySha256(file, info.sha256For(supportedAbis));
    if (valid) return file;
    await file.delete().catchError((_) => file);
    return null;
  }

  Future<void> cleanupStaleAndroidApks({
    AndroidUpdateInfo? keep,
    List<String> supportedAbis = const [],
  }) async {
    final dir = await _androidApkCacheDirectory();
    if (!await dir.exists()) return;

    final keepPath = keep == null
        ? null
        : (await androidApkCacheFile(keep, supportedAbis: supportedAbis)).path;
    await for (final entity in dir.list()) {
      if (entity is! File) continue;
      final name = entity.uri.pathSegments.last;
      final isUpdateApk =
          name.startsWith('UWHLife-') &&
          (name.endsWith('-update.apk') || name.endsWith('-update.apk.part'));
      if (!isUpdateApk || entity.path == keepPath) continue;
      await entity.delete().catchError((_) => entity);
    }
  }

  Future<File> androidApkCacheFile(
    AndroidUpdateInfo info, {
    List<String> supportedAbis = const [],
  }) async {
    final dir = await _androidApkCacheDirectory();
    final safeVersion = _safeVersionName(info.versionName);
    final abi = info.selectedAbi(supportedAbis);
    final abiSuffix = abi == null ? '' : '-$abi';
    return File('${dir.path}/UWHLife-$safeVersion$abiSuffix-update.apk');
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
    String? abi,
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

      final dir = await _androidApkCacheDirectory();
      final safeVersion = _safeVersionName(versionName);
      final abiSuffix = abi == null ? '' : '-$abi';
      final file = File(
        '${dir.path}/UWHLife-$safeVersion$abiSuffix-update.apk',
      );
      final partialFile = File('${file.path}.part');
      final sink = partialFile.openWrite();
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
      if (await file.exists()) await file.delete();
      await partialFile.rename(file.path);
      return file;
    } finally {
      ownedClient?.close(force: true);
    }
  }

  Future<Directory> _androidApkCacheDirectory() async {
    final dir = _cacheDirectory ?? await getTemporaryDirectory();
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  static String _safeVersionName(String versionName) {
    return versionName.replaceAll(RegExp(r'[^0-9A-Za-z._-]'), '_');
  }

  static const MethodChannel _apkInstallerChannel = MethodChannel(
    'uwhlife/apk_installer',
  );

  static Future<List<String>> currentAndroidAbis() async {
    try {
      final result = await _apkInstallerChannel.invokeListMethod<String>(
        'supportedAbis',
      );
      return result ?? const [];
    } catch (_) {
      return const [];
    }
  }
}
