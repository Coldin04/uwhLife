import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uwhlife/core/storage/login_state_store.dart';
import 'package:uwhlife/features/auth/portal_auto_login.dart';
import 'package:uwhlife/features/message/message_api.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'message bootstrap failure preserves the existing portal login',
    () async {
      SharedPreferences.setMockInitialValues({
        LoginStateStore.loggedInKey: true,
      });
      MessageApi.reset();
      PortalAutoLogin.instance.reset();
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(
        const MethodChannel('uwhlife/browser_data'),
        (_) async => '',
      );
      messenger.setMockMethodCallHandler(
        const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
        (_) async => null,
      );
      addTearDown(() {
        MessageApi.reset();
        PortalAutoLogin.instance.reset();
        messenger.setMockMethodCallHandler(
          const MethodChannel('uwhlife/browser_data'),
          null,
        );
        messenger.setMockMethodCallHandler(
          const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
          null,
        );
      });

      await HttpOverrides.runZoned(() async {
        await expectLater(MessageApi.fetchCategories(), throwsException);
      }, createHttpClient: (_) => _HtmlClient());

      expect(await LoginStateStore.readLoggedIn(), isTrue);
    },
  );
}

class _HtmlClient implements HttpClient {
  @override
  Future<HttpClientRequest> getUrl(Uri url) async => _HtmlRequest();
  @override
  void close({bool force = false}) {}
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _HtmlRequest implements HttpClientRequest {
  @override
  final HttpHeaders headers = _Headers();
  @override
  Future<HttpClientResponse> close() async => _HtmlResponse();
  @override
  set followRedirects(bool value) {}
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Headers implements HttpHeaders {
  @override
  void set(String name, Object value, {bool preserveHeaderCase = false}) {}
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _HtmlResponse extends Stream<List<int>> implements HttpClientResponse {
  @override
  int get statusCode => 200;
  @override
  StreamSubscription<List<int>> listen(
    void Function(List<int>)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) =>
      Stream.value(utf8.encode('<html>Temporarily unavailable</html>')).listen(
        onData,
        onError: onError,
        onDone: onDone,
        cancelOnError: cancelOnError,
      );
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
