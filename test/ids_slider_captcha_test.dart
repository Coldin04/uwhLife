import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:pointycastle/export.dart';
import 'package:uwhlife/features/auth/ids_slider_captcha.dart';
import 'package:uwhlife/features/auth/ids_slider_recorder.dart';

void main() {
  group('IdsSliderChallenge', () {
    test('uses the last 16 bytes of the small image as the AES key', () {
      final small = <int>[
        ...utf8.encode('png-bytes'),
        ...utf8.encode('0123456789abcdef'),
      ];
      final challenge = IdsSliderChallenge.fromJson(<String, dynamic>{
        'bigImage': base64.encode(utf8.encode('big')),
        'smallImage': base64.encode(small),
        'tagWidth': 93,
        'yHeight': 4,
      });

      expect(challenge.key, '0123456789abcdef');
      expect(challenge.tagWidth, 93);
      expect(challenge.yHeight, 4);
      expect(utf8.decode(challenge.bigImage), 'big');
    });

    test('rejects payloads without usable images', () {
      expect(
        () => IdsSliderChallenge.fromJson(<String, dynamic>{
          'bigImage': '',
          'smallImage': base64.encode(utf8.encode('short')),
        }),
        throwsFormatException,
      );
    });
  });

  test('signer reproduces the front end encryption layout', () {
    final challenge = IdsSliderChallenge(
      key: 'abcdef0123456789',
      bigImage: Uint8List.fromList(<int>[1, 2, 3]),
      smallImage: Uint8List.fromList(<int>[4, 5, 6]),
      tagWidth: 93,
      yHeight: 0,
    );
    const answer = IdsSliderAnswer(
      canvasLength: 280,
      moveLength: 96,
      tracks: <IdsSliderTrack>[
        IdsSliderTrack(a: 0, b: 0, c: 0),
        IdsSliderTrack(a: 48, b: 1, c: 24),
        IdsSliderTrack(a: 96, b: 0, c: 31),
      ],
    );
    final signer = IdsSliderSigner(
      randomText: (length) => length == 64 ? 'A' * 64 : 'B' * length,
    );

    final sign = signer.sign(challenge: challenge, answer: answer);
    final plaintext = _decrypt(sign, 'abcdef0123456789', 'B' * 16);

    // 64 random characters of throw-away prefix, then compact JSON.
    expect(plaintext, startsWith('A' * 64));
    expect(plaintext.substring(64), jsonEncode(answer.toJson()));
    expect(
      plaintext.substring(64),
      '{"canvasLength":280,"moveLength":96,"tracks":'
      '[{"a":0,"b":0,"c":0},{"a":48,"b":1,"c":24},{"a":96,"b":0,"c":31}]}',
    );
  });

  group('IdsSliderDragRecorder', () {
    test('samples on the front end rules and clamps to the track', () {
      final recorder = IdsSliderDragRecorder(maxDistance: 100)
        ..start(Offset(10, 10), Duration.zero);

      // Too early: dropped.
      recorder.update(const Offset(12, 10), const Duration(milliseconds: 5));
      expect(recorder.tracks, hasLength(1));

      // 25ms and 20px later: kept.
      recorder.update(const Offset(30, 11), const Duration(milliseconds: 25));
      expect(recorder.tracks.last.a, 20);
      expect(recorder.tracks.last.c, 25);

      final answer = recorder.finish(
        const Offset(200, 12),
        const Duration(milliseconds: 70),
        canvasLength: 280,
      );

      expect(answer, isNotNull);
      expect(answer!.canvasLength, 280);
      expect(answer.moveLength, 100);
      expect(answer.tracks.first.a, 0);
      expect(answer.tracks.last.a, 100);
      expect(answer.tracks.last.c, greaterThanOrEqualTo(20));
    });

    test('returns null for a drag that is too short', () {
      final recorder = IdsSliderDragRecorder(maxDistance: 100)
        ..start(Offset.zero, Duration.zero);

      final answer = recorder.finish(
        const Offset(2, 0),
        const Duration(milliseconds: 40),
        canvasLength: 280,
      );

      expect(answer, isNull);
    });
  });
}

String _decrypt(String sign, String key, String iv) {
  final cipher = PaddedBlockCipher('AES/CBC/PKCS7')
    ..init(
      false,
      PaddedBlockCipherParameters<ParametersWithIV<KeyParameter>, Null>(
        ParametersWithIV<KeyParameter>(
          KeyParameter(Uint8List.fromList(utf8.encode(key))),
          Uint8List.fromList(utf8.encode(iv)),
        ),
        null,
      ),
    );
  return utf8.decode(cipher.process(base64.decode(sign)));
}
