bool isIdsLoginForm({required String url, required String body}) {
  final uri = Uri.tryParse(url);
  if (uri?.host.toLowerCase() != 'ids.uwh.edu.cn' ||
      uri?.path.toLowerCase().contains('/authserver/login') != true) {
    return false;
  }

  final html = body.toLowerCase();
  final hasUsername = RegExp(
    r'''<input[^>]+(?:name|id)=["']username["']''',
  ).hasMatch(html);
  final hasPassword = RegExp(
    r'''<input[^>]+(?:name|id)=["']password["']|<input[^>]+type=["']password["']''',
  ).hasMatch(html);
  return hasUsername && hasPassword;
}
