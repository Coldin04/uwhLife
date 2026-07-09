class AndroidVersionCode {
  AndroidVersionCode._();

  static int logicalBuildNumber(String buildNumber) {
    final code = int.tryParse(buildNumber) ?? 0;
    if (code > 1000 && code < 4000) {
      final baseCode = code % 1000;
      if (baseCode > 0) return baseCode;
    }
    return code;
  }
}
