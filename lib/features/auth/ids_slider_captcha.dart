import 'dart:convert';
import 'dart:typed_data';

import 'ids_aes.dart';

/// One puzzle-slider challenge issued by `openSliderCaptcha.htl`.
///
/// The AES key for signing the answer is not sent separately: it is the last
/// 16 bytes of the (base64-decoded) small image.
class IdsSliderChallenge {
  const IdsSliderChallenge({
    required this.key,
    required this.bigImage,
    required this.smallImage,
    required this.tagWidth,
    required this.yHeight,
  });

  factory IdsSliderChallenge.fromJson(Map<String, dynamic> json) {
    final bigImage = _decodeImage(json['bigImage']);
    final smallImage = _decodeImage(json['smallImage']);
    if (smallImage.length < 16) {
      throw const FormatException('Slider captcha image is too short');
    }
    return IdsSliderChallenge(
      key: String.fromCharCodes(smallImage.sublist(smallImage.length - 16)),
      bigImage: bigImage,
      smallImage: smallImage,
      tagWidth: _asInt(json['tagWidth']),
      yHeight: _asInt(json['yHeight']),
    );
  }

  /// AES key used to sign the answer (last 16 bytes of [smallImage]).
  final String key;
  final Uint8List bigImage;
  final Uint8List smallImage;
  final int tagWidth;
  final int yHeight;

  static Uint8List _decodeImage(Object? value) {
    if (value is! String || value.isEmpty) {
      throw const FormatException('Slider captcha image is missing');
    }
    return base64.decode(value);
  }

  static int _asInt(Object? value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return 0;
  }
}

/// One pointer sample in the shape the IDS front end records.
///
/// [a] is the accumulated horizontal offset, [b] the vertical offset and [c]
/// the milliseconds elapsed since the previous sample.
class IdsSliderTrack {
  const IdsSliderTrack({required this.a, required this.b, required this.c});

  final int a;
  final int b;
  final int c;

  Map<String, int> toJson() => <String, int>{'a': a, 'b': b, 'c': c};

  @override
  String toString() => 'IdsSliderTrack(a: $a, b: $b, c: $c)';
}

/// What the user produced by dragging the slider.
class IdsSliderAnswer {
  const IdsSliderAnswer({
    required this.canvasLength,
    required this.moveLength,
    required this.tracks,
  });

  /// Width of the canvas the drag happened on, in logical pixels.
  final int canvasLength;

  /// Horizontal distance the slider travelled, in the same unit.
  final int moveLength;

  final List<IdsSliderTrack> tracks;

  Map<String, Object> toJson() => <String, Object>{
    'canvasLength': canvasLength,
    'moveLength': moveLength,
    'tracks': <Map<String, int>>[for (final track in tracks) track.toJson()],
  };
}

/// Signs a drag answer the way `encrypt.js` does.
class IdsSliderSigner {
  IdsSliderSigner({String Function(int)? randomText})
    : _randomText = randomText ?? idsSecureRandomText;

  final String Function(int) _randomText;

  String sign({
    required IdsSliderChallenge challenge,
    required IdsSliderAnswer answer,
  }) {
    final payload = jsonEncode(answer.toJson());
    return idsAesEncrypt(
      plaintext: '${_randomText(64)}$payload',
      key: challenge.key,
      iv: _randomText(16),
    );
  }
}
