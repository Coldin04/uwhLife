class UpdateManifest {
  const UpdateManifest({
    required this.schemaVersion,
    required this.app,
    required this.android,
    required this.ios,
  });

  factory UpdateManifest.fromJson(Map<String, dynamic> json) {
    return UpdateManifest(
      schemaVersion: _readInt(json['schemaVersion']),
      app: json['app']?.toString() ?? '',
      android: AndroidUpdateInfo.fromJson(_readMap(json['android'])),
      ios: IosUpdateInfo.fromJson(_readMap(json['ios'])),
    );
  }

  final int schemaVersion;
  final String app;
  final AndroidUpdateInfo android;
  final IosUpdateInfo ios;
}

class AndroidUpdateInfo {
  const AndroidUpdateInfo({
    required this.versionName,
    required this.versionCode,
    required this.minSupportedVersionCode,
    required this.mandatory,
    required this.title,
    required this.notes,
    required this.apkUrl,
    required this.fallbackApkUrl,
    required this.sha256,
  });

  factory AndroidUpdateInfo.fromJson(Map<String, dynamic> json) {
    return AndroidUpdateInfo(
      versionName: json['versionName']?.toString() ?? '',
      versionCode: _readInt(json['versionCode']),
      minSupportedVersionCode: _readInt(json['minSupportedVersionCode']),
      mandatory: json['mandatory'] == true,
      title: json['title']?.toString() ?? '发现新版本',
      notes: _readStringList(json['notes']),
      apkUrl: json['apkUrl']?.toString() ?? '',
      fallbackApkUrl: json['fallbackApkUrl']?.toString() ?? '',
      sha256: json['sha256']?.toString() ?? '',
    );
  }

  final String versionName;
  final int versionCode;
  final int minSupportedVersionCode;
  final bool mandatory;
  final String title;
  final List<String> notes;
  final String apkUrl;
  final String fallbackApkUrl;
  final String sha256;

  List<String> get downloadUrls {
    return [apkUrl, fallbackApkUrl]
        .map((url) => url.trim())
        .where((url) => url.isNotEmpty)
        .toList(growable: false);
  }

  bool isNewerThan({required String buildNumber}) {
    return versionCode > (int.tryParse(buildNumber) ?? 0);
  }

  bool requiresUpdate({required String buildNumber}) {
    return minSupportedVersionCode > (int.tryParse(buildNumber) ?? 0);
  }
}

class IosUpdateInfo {
  const IosUpdateInfo({
    required this.versionName,
    required this.buildVersion,
    required this.title,
    required this.notes,
    required this.altSourceUrl,
  });

  factory IosUpdateInfo.fromJson(Map<String, dynamic> json) {
    return IosUpdateInfo(
      versionName: json['versionName']?.toString() ?? '',
      buildVersion: json['buildVersion']?.toString() ?? '',
      title: json['title']?.toString() ?? '发现新版本',
      notes: _readStringList(json['notes']),
      altSourceUrl: json['altSourceUrl']?.toString() ?? '',
    );
  }

  final String versionName;
  final String buildVersion;
  final String title;
  final List<String> notes;
  final String altSourceUrl;

  bool isNewerThan({required String buildNumber}) {
    return (int.tryParse(buildVersion) ?? 0) > (int.tryParse(buildNumber) ?? 0);
  }
}

Map<String, dynamic> _readMap(Object? value) {
  if (value is Map<String, dynamic>) return value;
  if (value is Map) return value.cast<String, dynamic>();
  return const {};
}

int _readInt(Object? value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  return int.tryParse(value?.toString() ?? '') ?? 0;
}

List<String> _readStringList(Object? value) {
  if (value is! List) return const [];
  return value.map((item) => item.toString()).toList(growable: false);
}
