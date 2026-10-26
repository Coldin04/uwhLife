import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:uwhlife/features/auth/ids_slider_captcha.dart';
import 'package:uwhlife/features/auth/widgets/ids_slider_captcha_dialog.dart';

/// 59 x 36 solid PNG: realistic enough for the piece scaling arithmetic.
const String _pngBase64 =
    'iVBORw0KGgoAAAANSUhEUgAAADsAAAAkCAIAAAC4x9WqAAAAOUlEQVR42u3OAQ0AMAgAIH0l'
    's1jSlI/h3CABWT1xyotrjI2NjY2NjY2NjY2NjY2NjY2NjY2NjY13fIjMAXp+Yu0rAAAAAElF'
    'TkSuQmCC';

IdsSliderChallenge _challenge() {
  final png = base64.decode(_pngBase64);
  return IdsSliderChallenge(
    key: '0123456789abcdef',
    bigImage: png,
    smallImage: png,
    tagWidth: 9,
    yHeight: 0,
  );
}

Widget _host({
  required ValueChanged<IdsSliderAnswer?> onClosed,
  IdsSliderChallenge? challenge,
  String? message,
}) {
  return MaterialApp(
    home: Scaffold(
      body: Builder(
        builder: (context) => TextButton(
          onPressed: () async {
            final answer = await IdsSliderCaptchaDialog.show(
              context,
              challenge ?? _challenge(),
              message: message,
            );
            onClosed(answer);
          },
          child: const Text('open'),
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('returns the drag answer when the user releases the slider', (
    tester,
  ) async {
    IdsSliderAnswer? answer;
    await tester.pumpWidget(_host(onClosed: (value) => answer = value));

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.byKey(IdsSliderCaptchaDialog.sliderBarKey), findsOneWidget);

    await tester.drag(
      find.byKey(IdsSliderCaptchaDialog.sliderBarKey),
      const Offset(80, 0),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(IdsSliderCaptchaDialog.sliderBarKey), findsNothing);
    expect(answer, isNotNull);
    expect(answer!.canvasLength, 280);
    expect(answer!.moveLength, greaterThanOrEqualTo(70));
    expect(answer!.tracks.first.a, 0);
    expect(answer!.tracks.last.a, answer!.moveLength);
  });

  testWidgets('a tiny drag keeps the dialog open with a hint', (tester) async {
    await tester.pumpWidget(_host(onClosed: (_) {}));

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    await tester.drag(
      find.byKey(IdsSliderCaptchaDialog.sliderBarKey),
      const Offset(2, 0),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(IdsSliderCaptchaDialog.sliderBarKey), findsOneWidget);
    expect(find.text('请按住滑块向右拖动'), findsOneWidget);
  });

  testWidgets('shows the retry message and cancel closes without an answer', (
    tester,
  ) async {
    IdsSliderAnswer? answer;
    var closed = false;
    await tester.pumpWidget(
      _host(
        challenge: _challenge(),
        message: '验证未通过，请再试一次',
        onClosed: (value) {
          answer = value;
          closed = true;
        },
      ),
    );

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.text('验证未通过，请再试一次'), findsOneWidget);

    await tester.tap(find.byTooltip('取消'));
    await tester.pumpAndSettle();

    expect(closed, isTrue);
    expect(answer, isNull);
  });
}
