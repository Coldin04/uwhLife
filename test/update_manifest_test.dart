import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:uwhlife/features/update/update_manifest.dart';
import 'package:uwhlife/features/update/update_service.dart';

void main() {
  const updatePayload = 'uwhLife update payload';
  const updatePayloadSha256 =
      '2257977f0c01cad5f870f41ec563403ed5634dcc99491ddf930c0bbf28cbd26f';
  const rawManifest = '''
{
  "schemaVersion": 1,
  "app": "uwhLife",
  "android": {
    "versionName": "1.2.1",
    "versionCode": 11,
    "minSupportedVersionCode": 10,
    "mandatory": false,
    "title": "发现新版本",
    "notes": ["优化首页加载体验", "修复若干问题"],
    "apkUrl": "https://gitee.com/coldin04/uwhlife_source/releases/download/latest/UWHLife_android_arm64-v8a.apk",
    "fallbackApkUrl": "https://github.com/coldin04/uwhLife/releases/download/v1.2.1/UWHLife_android_arm64-v8a.apk",
    "apkUrls": {
      "armeabi-v7a": "https://gitee.com/coldin04/uwhlife_source/releases/download/latest/UWHLife_android_armeabi-v7a.apk",
      "arm64-v8a": "https://gitee.com/coldin04/uwhlife_source/releases/download/latest/UWHLife_android_arm64-v8a.apk",
      "x86_64": "https://gitee.com/coldin04/uwhlife_source/releases/download/latest/UWHLife_android_x86_64.apk"
    },
    "fallbackApkUrls": {
      "armeabi-v7a": "https://github.com/coldin04/uwhLife/releases/download/v1.2.1/UWHLife_android_armeabi-v7a.apk",
      "arm64-v8a": "https://github.com/coldin04/uwhLife/releases/download/v1.2.1/UWHLife_android_arm64-v8a.apk",
      "x86_64": "https://github.com/coldin04/uwhLife/releases/download/v1.2.1/UWHLife_android_x86_64.apk"
    },
    "sha256ByAbi": {
      "arm64-v8a": "abc123"
    },
    "sha256": "abc123"
  },
  "ios": {
    "versionName": "1.2.1",
    "buildVersion": "11",
    "title": "发现新版本",
    "notes": ["优化首页加载体验"],
    "altSourceUrl": "https://raw.giteeusercontent.com/coldin04/uwhlife_source/raw/master/source.json"
  }
}
''';

  test('parses platform-specific update metadata from one manifest', () {
    final manifest = UpdateManifest.fromJson(
      jsonDecode(rawManifest) as Map<String, dynamic>,
    );

    expect(manifest.schemaVersion, 1);
    expect(manifest.android.versionName, '1.2.1');
    expect(manifest.android.versionCode, 11);
    expect(manifest.android.downloadUrls, [
      'https://gitee.com/coldin04/uwhlife_source/releases/download/latest/UWHLife_android_arm64-v8a.apk',
      'https://github.com/coldin04/uwhLife/releases/download/v1.2.1/UWHLife_android_arm64-v8a.apk',
    ]);
    expect(manifest.ios.buildVersion, '11');
    expect(
      manifest.ios.altSourceUrl,
      'https://raw.giteeusercontent.com/coldin04/uwhlife_source/raw/master/source.json',
    );
  });

  test('selects android download URLs by supported ABI', () {
    final manifest = UpdateManifest.fromJson(
      jsonDecode(rawManifest) as Map<String, dynamic>,
    );

    expect(manifest.android.selectedAbi(['armeabi-v7a']), 'armeabi-v7a');
    expect(manifest.android.selectedAbi(['x86_64']), 'x86_64');
    expect(manifest.android.downloadUrlsFor(['armeabi-v7a']), [
      'https://gitee.com/coldin04/uwhlife_source/releases/download/latest/UWHLife_android_armeabi-v7a.apk',
      'https://github.com/coldin04/uwhLife/releases/download/v1.2.1/UWHLife_android_armeabi-v7a.apk',
    ]);
    expect(manifest.android.downloadUrlsFor(['mips']), [
      'https://gitee.com/coldin04/uwhlife_source/releases/download/latest/UWHLife_android_arm64-v8a.apk',
      'https://github.com/coldin04/uwhLife/releases/download/v1.2.1/UWHLife_android_arm64-v8a.apk',
    ]);
  });

  test('compares android versionCode and ios buildVersion', () {
    final manifest = UpdateManifest.fromJson(
      jsonDecode(rawManifest) as Map<String, dynamic>,
    );

    expect(manifest.android.isNewerThan(buildNumber: '10'), isTrue);
    expect(manifest.android.isNewerThan(buildNumber: '11'), isFalse);
    expect(manifest.android.isNewerThan(buildNumber: '2011'), isFalse);
    expect(manifest.android.isNewerThan(buildNumber: '2010'), isTrue);
    expect(manifest.ios.isNewerThan(buildNumber: '10'), isTrue);
    expect(manifest.ios.isNewerThan(buildNumber: '11'), isFalse);
  });

  test('validates sha256 when a checksum is provided', () async {
    final file = File('${Directory.systemTemp.path}/uwhlife-update-test.apk');
    await file.writeAsString(updatePayload);
    addTearDown(() {
      if (file.existsSync()) file.deleteSync();
    });

    expect(await UpdateService.verifySha256(file, updatePayloadSha256), isTrue);
    expect(await UpdateService.verifySha256(file, 'deadbeef'), isFalse);
    expect(await UpdateService.verifySha256(file, ''), isTrue);
  });

  test('reuses a cached apk when checksum still matches', () async {
    final dir = await Directory.systemTemp.createTemp('uwhlife-cache-test-');
    addTearDown(() {
      if (dir.existsSync()) dir.deleteSync(recursive: true);
    });
    final service = UpdateService(cacheDirectory: dir);
    final manifest = UpdateManifest.fromJson(
      jsonDecode(rawManifest.replaceFirst('abc123', updatePayloadSha256))
          as Map<String, dynamic>,
    );
    final file = await service.androidApkCacheFile(manifest.android);
    await file.writeAsString(updatePayload);

    final cached = await service.cachedAndroidApk(manifest.android);

    expect(cached?.path, file.path);
  });

  test('removes stale apk caches but keeps the current version', () async {
    final dir = await Directory.systemTemp.createTemp('uwhlife-cache-test-');
    addTearDown(() {
      if (dir.existsSync()) dir.deleteSync(recursive: true);
    });
    final service = UpdateService(cacheDirectory: dir);
    final manifest = UpdateManifest.fromJson(
      jsonDecode(rawManifest) as Map<String, dynamic>,
    );
    final current = await service.androidApkCacheFile(manifest.android);
    final stale = File('${dir.path}/UWHLife-1.2.0-update.apk');
    final partial = File('${dir.path}/UWHLife-1.2.0-update.apk.part');
    await current.writeAsString(updatePayload);
    await stale.writeAsString('old apk');
    await partial.writeAsString('partial old apk');

    await service.cleanupStaleAndroidApks(keep: manifest.android);

    expect(await current.exists(), isTrue);
    expect(await stale.exists(), isFalse);
    expect(await partial.exists(), isFalse);
  });
}
