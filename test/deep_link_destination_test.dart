import 'package:flutter_test/flutter_test.dart';
import 'package:uwhlife/core/deep_links/deep_link_destination.dart';

void main() {
  group('DeepLinkDestination.parse', () {
    test('routes supported uwhlife scheme hosts', () {
      expect(
        DeepLinkDestination.parse('uwhlife://opendoor'),
        DeepLinkDestination.openDoor,
      );
      expect(
        DeepLinkDestination.parse('uwhlife://paycode'),
        DeepLinkDestination.payCode,
      );
      expect(
        DeepLinkDestination.parse('uwhlife://bath'),
        DeepLinkDestination.bath,
      );
    });

    test('ignores unknown or malformed links', () {
      expect(DeepLinkDestination.parse('https://paycode'), isNull);
      expect(DeepLinkDestination.parse('uwhlife://unknown'), isNull);
      expect(DeepLinkDestination.parse('not a uri'), isNull);
      expect(DeepLinkDestination.parse(''), isNull);
    });
  });
}
