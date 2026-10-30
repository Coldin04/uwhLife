import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:uwhlife/core/platform/side_navigation.dart';

void main() {
  tearDown(() {
    isDuoDevice = false;
    systemAdaptivePhone = false;
    systemVerticalEdge = 'none';
    systemReservedBottom = 0;
    systemReservedRightWidth = 0;
    systemSideCenterInset = 0;
  });

  testWidgets('Duo outer display keeps side navigation on a narrow screen', (
    tester,
  ) async {
    bool? sideNavigation;
    Future<void> render(Size size) async {
      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: MediaQueryData(
              size: size,
              padding: isDuoDevice
                  ? const EdgeInsets.only(right: 90)
                  : EdgeInsets.zero,
            ),
            child: Builder(
              builder: (context) {
                sideNavigation = usesSideNavigation(context);
                return const SizedBox();
              },
            ),
          ),
        ),
      );
    }

    await render(const Size(390, 844));
    expect(sideNavigation, isFalse);
    isDuoDevice = true;
    await render(const Size(390, 844));
    expect(sideNavigation, isTrue);
    isDuoDevice = false;
    await render(const Size(800, 900));
    expect(sideNavigation, isTrue);
    systemAdaptivePhone = true;
    systemVerticalEdge = 'none';
    await render(const Size(800, 1100));
    expect(sideNavigation, isFalse);
    systemVerticalEdge = 'left';
    await render(const Size(800, 500));
    expect(sideNavigation, isTrue);
  });

  testWidgets('side controls use the system cluster centre on both edges', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(466, 678);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    for (final edge in ['right', 'left']) {
      systemVerticalEdge = edge;
      isDuoDevice = true;
      final insets = edge == 'right'
          ? const EdgeInsets.only(right: 84)
          : const EdgeInsets.only(left: 84);
      for (final nativeCenter in [47.83, 0.0]) {
        systemSideCenterInset = nativeCenter;
        await tester.pumpWidget(
          MaterialApp(
            home: MediaQuery(
              data: MediaQueryData(
                size: const Size(466, 678),
                padding: insets,
                viewPadding: insets,
              ),
              child: Builder(
                builder: (context) => Stack(
                  children: [
                    Positioned(
                      top: 100,
                      left: edge == 'left'
                          ? sideControlRightInset(context, 48)
                          : null,
                      right: edge == 'right'
                          ? sideControlRightInset(context, 48)
                          : null,
                      child: const SizedBox(
                        key: ValueKey('dock'),
                        width: 48,
                        height: 48,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
        final center = tester.getCenter(find.byKey(const ValueKey('dock'))).dx;
        final offset = nativeCenter > 0 ? nativeCenter : 42.0;
        expect(center, closeTo(edge == 'right' ? 466 - offset : offset, 0.01));
      }
    }
  });
}
