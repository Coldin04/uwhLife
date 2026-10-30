import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:uwhlife/features/auth/portal_auto_login.dart';
import 'package:uwhlife/features/door/door_api.dart';

void main() {
  test(
    'starts a cold-launch door request without waiting for a probe',
    () async {
      final probe = Completer<void>();
      var opens = 0;
      final coordinator = DoorSessionCoordinator(
        waitForRecovery: () async {},
        generation: () => 1,
        open: (generation) async {
          opens++;
          expect(generation, 1);
          return const DoorOpenResult.opened('已开门');
        },
        loginRequired: (_) async => fail('应当直接使用现有会话'),
      );

      final result = await coordinator.run();

      expect(probe.isCompleted, isFalse);
      expect(opens, 1);
      expect(result.status, DoorOpenStatus.opened);
    },
  );

  test(
    'waits for an ongoing recovery before reading the generation and opening',
    () async {
      final recovery = Completer<void>();
      var generation = 1;
      var opens = 0;
      final coordinator = DoorSessionCoordinator(
        waitForRecovery: () => recovery.future,
        generation: () => generation,
        open: (observed) async {
          opens++;
          expect(observed, 2);
          return const DoorOpenResult.opened('已开门');
        },
        loginRequired: (_) async => fail('不应再次恢复'),
      );

      final result = coordinator.run();
      await Future<void>.delayed(Duration.zero);
      expect(opens, 0);
      generation = 2;
      recovery.complete();

      expect((await result).status, DoorOpenStatus.opened);
      expect(opens, 1);
    },
  );

  test('does not repeat the door request when recovery fails', () async {
    var opens = 0;
    var recoveries = 0;
    final coordinator = DoorSessionCoordinator(
      waitForRecovery: () async {},
      generation: () => 7,
      open: (_) async {
        opens++;
        return const DoorOpenResult.needsLogin();
      },
      loginRequired: (observed) async {
        expect(observed, 7);
        recoveries++;
        return PortalAutoLoginOutcome.failed;
      },
    );

    final result = await coordinator.run();

    expect(result.status, DoorOpenStatus.needsLogin);
    expect(opens, 1);
    expect(recoveries, 1);
  });

  test('retries once with the new generation after recovery', () async {
    var generation = 7;
    final openedGenerations = <int>[];
    var recoveries = 0;
    final retryExpiries = <int>[];
    final coordinator = DoorSessionCoordinator(
      waitForRecovery: () async {},
      generation: () => generation,
      open: (observed) async {
        openedGenerations.add(observed);
        return const DoorOpenResult.needsLogin();
      },
      loginRequired: (observed) async {
        expect(observed, 7);
        recoveries++;
        generation = 8;
        return PortalAutoLoginOutcome.restored;
      },
      onRetryLoginRequired: (observed) async => retryExpiries.add(observed),
    );

    final result = await coordinator.run();

    expect(result.status, DoorOpenStatus.needsLogin);
    expect(openedGenerations, [7, 8]);
    expect(recoveries, 1);
    expect(retryExpiries, [8]);
  });

  test(
    'reports expiry after a submitted action without repeating it',
    () async {
      var opens = 0;
      var recoveries = 0;
      final coordinator = DoorSessionCoordinator(
        waitForRecovery: () async {},
        generation: () => 4,
        open: (_) async {
          opens++;
          return const DoorOpenResult.needsLogin(retrySafe: false);
        },
        loginRequired: (_) async {
          recoveries++;
          return PortalAutoLoginOutcome.restored;
        },
      );

      final result = await coordinator.run();

      expect(result.status, DoorOpenStatus.needsLogin);
      expect(opens, 1);
      expect(recoveries, 1);
    },
  );
}
