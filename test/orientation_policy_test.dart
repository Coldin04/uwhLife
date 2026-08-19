import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:uwhlife/core/platform/orientation_policy.dart';

void main() {
  group('orientationsForShortestSide', () {
    test('locks phones to upright portrait', () {
      expect(
        orientationsForShortestSide(tabletShortestSideBreakpoint - 1),
        const <DeviceOrientation>[DeviceOrientation.portraitUp],
      );
    });

    test('allows all orientations on tablet-sized displays', () {
      expect(
        orientationsForShortestSide(tabletShortestSideBreakpoint),
        DeviceOrientation.values,
      );
    });
  });
}
