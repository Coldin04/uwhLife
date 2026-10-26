import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:pointycastle/export.dart';

/// Character set the IDS front end uses for its random padding.
const String idsRandomAlphabet =
    'ABCDEFGHJKMNPQRSTWXYZabcdefhijkmnprstwxyz2345678';

/// Cryptographically random text drawn from [idsRandomAlphabet].
String idsSecureRandomText(int length) {
  final random = Random.secure();
  return String.fromCharCodes(
    List<int>.generate(
      length,
      (_) => idsRandomAlphabet.codeUnitAt(
        random.nextInt(idsRandomAlphabet.length),
      ),
      growable: false,
    ),
  );
}

/// AES-CBC/PKCS7 + Base64, matching CryptoJS `AES.encrypt(...).toString()`.
///
/// The IDS pages always prefix the plaintext with 64 random characters, so the
/// first cipher block is throw-away material and the server can decrypt with a
/// fixed IV: only that block ends up garbled.
String idsAesEncrypt({
  required String plaintext,
  required String key,
  required String iv,
}) {
  final keyBytes = Uint8List.fromList(utf8.encode(key));
  if (keyBytes.length != 16 && keyBytes.length != 24 && keyBytes.length != 32) {
    throw const FormatException('Invalid AES key length');
  }
  final cipher = PaddedBlockCipher('AES/CBC/PKCS7')
    ..init(
      true,
      PaddedBlockCipherParameters<ParametersWithIV<KeyParameter>, Null>(
        ParametersWithIV<KeyParameter>(
          KeyParameter(keyBytes),
          Uint8List.fromList(utf8.encode(iv)),
        ),
        null,
      ),
    );
  return base64.encode(
    cipher.process(Uint8List.fromList(utf8.encode(plaintext))),
  );
}
