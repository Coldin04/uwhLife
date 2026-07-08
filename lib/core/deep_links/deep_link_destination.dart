enum DeepLinkDestination {
  openDoor,
  payCode,
  bath;

  static DeepLinkDestination? parse(String link) {
    final uri = Uri.tryParse(link);
    if (uri == null) return null;
    if (uri.scheme.toLowerCase() != 'uwhlife') return null;

    return switch (uri.host.toLowerCase()) {
      'opendoor' => DeepLinkDestination.openDoor,
      'paycode' => DeepLinkDestination.payCode,
      'bath' => DeepLinkDestination.bath,
      _ => null,
    };
  }
}
