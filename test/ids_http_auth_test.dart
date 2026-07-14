import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:pointycastle/export.dart';
import 'package:uwhlife/features/auth/ids_http_auth.dart';

void main() {
  test('encodes the password with the IDS AES-CBC shape', () {
    final encoder = IdsPasswordEncoder(
      randomText: (length) => length == 64 ? 'A' * 64 : 'B' * length,
    );
    final encoded = encoder.encode(
      password: 'secret',
      salt: '1234567890abcdef',
    );

    final cipher = PaddedBlockCipher('AES/CBC/PKCS7')
      ..init(
        false,
        PaddedBlockCipherParameters<ParametersWithIV<KeyParameter>, Null>(
          ParametersWithIV<KeyParameter>(
            KeyParameter(Uint8List.fromList(utf8.encode('1234567890abcdef'))),
            Uint8List.fromList(utf8.encode('B' * 16)),
          ),
          null,
        ),
      );
    final plaintext = utf8.decode(cipher.process(base64.decode(encoded)));

    expect(plaintext, '${'A' * 64}secret');
  });

  test('keeps cookies constrained to their domain and path', () {
    final jar = HttpCookieJar();
    final rootCookie = Cookie('ids', 'one')..path = '/';
    final pathCookie = Cookie('portal', 'two')..path = '/message/';
    jar.save(Uri.parse('https://ids.uwh.edu.cn/authserver/login'), <Cookie>[
      rootCookie,
      pathCookie,
    ]);

    expect(
      jar.cookieHeaderFor(Uri.parse('https://ids.uwh.edu.cn/message/list')),
      contains('ids=one'),
    );
    expect(
      jar.cookieHeaderFor(Uri.parse('https://ids.uwh.edu.cn/message/list')),
      contains('portal=two'),
    );
    expect(
      jar.cookieHeaderFor(Uri.parse('https://ids.uwh.edu.cn/other')),
      isNot(contains('portal=two')),
    );
    expect(
      jar.cookieHeaderFor(Uri.parse('https://ehall.uwh.edu.cn/message/list')),
      isEmpty,
    );
  });
}
