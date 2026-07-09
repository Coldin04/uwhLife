import 'dart:convert';
import 'dart:io';

void main() {
  final pubspec = File('pubspec.yaml').readAsLinesSync();
  final versionLine = pubspec.firstWhere((line) => line.startsWith('version:'));
  final versionRaw = versionLine.split(':').sublist(1).join(':').trim();
  final parts = versionRaw.split('+');
  final versionName = parts.first;
  final buildNumber = parts.length > 1 ? parts[1] : '1';
  final tag = Platform.environment['TAG_NAME'] ?? 'v$versionName';
  final date =
      Platform.environment['RELEASE_DATE'] ??
      DateTime.now().toUtc().toIso8601String().split('T').first;
  final ipaSize = int.tryParse(Platform.environment['IPA_SIZE'] ?? '');
  final androidSha256 = Platform.environment['ANDROID_ARM64_SHA256'] ?? '';
  final androidArmeabiV7aSha256 =
      Platform.environment['ANDROID_ARMEABI_V7A_SHA256'] ?? '';
  final androidX8664Sha256 =
      Platform.environment['ANDROID_X86_64_SHA256'] ?? '';
  final githubRepository =
      Platform.environment['GITHUB_REPOSITORY'] ?? 'coldin04/uwhLife';
  final release = _readReleaseConfig();
  final title = release['title']?.toString() ?? 'v$versionName 更新';
  final mandatory = release['mandatory'] == true;
  final minSupportedVersionCode =
      _positiveInt(release['minSupportedVersionCode']) ??
      int.tryParse(buildNumber) ??
      0;
  final notes = _readNotes(release['notes']);

  const giteeLatest =
      'https://gitee.com/coldin04/uwhlife_source/releases/download/latest';
  final githubRelease =
      'https://github.com/$githubRepository/releases/download/$tag';
  final apkUrls = {
    'armeabi-v7a': '$giteeLatest/UWHLife_android_armeabi-v7a.apk',
    'arm64-v8a': '$giteeLatest/UWHLife_android_arm64-v8a.apk',
    'x86_64': '$giteeLatest/UWHLife_android_x86_64.apk',
  };
  final fallbackApkUrls = {
    'armeabi-v7a': '$githubRelease/UWHLife_android_armeabi-v7a.apk',
    'arm64-v8a': '$githubRelease/UWHLife_android_arm64-v8a.apk',
    'x86_64': '$githubRelease/UWHLife_android_x86_64.apk',
  };
  final numberedNotes = _numberedNotes(notes);

  final sourceFile = File('source.json');
  final source =
      jsonDecode(sourceFile.readAsStringSync()) as Map<String, dynamic>;
  final apps = source['apps'] as List;
  final app = apps.first as Map<String, dynamic>;
  final versions = app['versions'] as List;
  final existingVersion = versions.whereType<Map>().cast<Map>().firstWhere(
    (item) => item['version']?.toString() == versionName,
    orElse: () => const {},
  );
  final previousVersion = versions.whereType<Map>().cast<Map>().firstWhere(
    (item) => item['version']?.toString() != versionName,
    orElse: () => const {},
  );
  versions.removeWhere((item) {
    return item is Map && item['version']?.toString() == versionName;
  });
  final existingSize = _positiveInt(existingVersion['size']);
  final previousSize = _positiveInt(previousVersion['size']);
  versions.insert(0, {
    'version': versionName,
    'buildVersion': buildNumber,
    'date': date,
    'localizedDescription': numberedNotes,
    'downloadURL': '$giteeLatest/UWHLife_unsigned.ipa',
    'size': ipaSize ?? existingSize ?? previousSize ?? 0,
    'minOSVersion': '15.0',
  });

  final news = source['news'] as List;
  news.removeWhere((item) {
    return item is Map && item['identifier']?.toString() == versionName;
  });
  news.insert(0, {
    'title': title,
    'identifier': versionName,
    'caption': notes.first,
    'date': date,
    'tintColor': '#2196F3',
    'notify': true,
    'appID': 'com.cold04.uwhlife',
  });
  sourceFile.writeAsStringSync(_prettyJson(source));

  final updateFile = File('update.json');
  final update =
      jsonDecode(updateFile.readAsStringSync()) as Map<String, dynamic>;
  update['android'] = {
    'versionName': versionName,
    'versionCode': int.tryParse(buildNumber) ?? 0,
    'minSupportedVersionCode': minSupportedVersionCode,
    'mandatory': mandatory,
    'title': title,
    'notes': notes,
    'apkUrl': '$giteeLatest/UWHLife_android_arm64-v8a.apk',
    'fallbackApkUrl': '$githubRelease/UWHLife_android_arm64-v8a.apk',
    'apkUrls': apkUrls,
    'fallbackApkUrls': fallbackApkUrls,
    'sha256ByAbi': {
      'armeabi-v7a': androidArmeabiV7aSha256,
      'arm64-v8a': androidSha256,
      'x86_64': androidX8664Sha256,
    },
    'sha256': androidSha256,
  };
  update['ios'] = {
    'versionName': versionName,
    'buildVersion': buildNumber,
    'title': title,
    'notes': notes,
    'altSourceUrl':
        'https://raw.giteeusercontent.com/coldin04/uwhlife_source/raw/master/source.json',
  };
  updateFile.writeAsStringSync(_prettyJson(update));

  File('release_notes.md').writeAsStringSync(
    [
      '## $title',
      '',
      numberedNotes,
      '',
      '### 下载',
      '',
      '- Android: `UWHLife_android_arm64-v8a.apk`',
      '- iOS: `UWHLife_unsigned.ipa`',
      '',
    ].join('\n'),
  );
}

String _prettyJson(Object value) {
  return '${const JsonEncoder.withIndent('  ').convert(value)}\n';
}

int? _positiveInt(Object? value) {
  final parsed = value is int ? value : int.tryParse(value?.toString() ?? '');
  if (parsed == null || parsed <= 0) return null;
  return parsed;
}

Map<String, dynamic> _readReleaseConfig() {
  final file = File('release.json');
  if (!file.existsSync()) return const {};
  return (jsonDecode(file.readAsStringSync()) as Map).cast<String, dynamic>();
}

List<String> _readNotes(Object? value) {
  if (value is! List) return const ['更新体验与稳定性优化。'];
  final notes = value
      .map((item) => item.toString().trim())
      .where((item) => item.isNotEmpty)
      .toList(growable: false);
  if (notes.isEmpty) return const ['更新体验与稳定性优化。'];
  return notes;
}

String _numberedNotes(List<String> notes) {
  return [
    for (var i = 0; i < notes.length; i += 1) '${i + 1}. ${notes[i]}',
  ].join('\n');
}
