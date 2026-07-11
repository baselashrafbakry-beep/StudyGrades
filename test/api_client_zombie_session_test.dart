import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:voice_grader/models/user_model.dart';
import 'package:voice_grader/services/api_client.dart';

class _FakeSecureStorageChannel {
  static const _channel = MethodChannel(
    'plugins.it_nomads.com/flutter_secure_storage',
  );

  final Map<String, String> store = {};

  void install() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_channel, (MethodCall call) async {
          final args = call.arguments is Map
              ? Map<String, dynamic>.from(call.arguments as Map)
              : <String, dynamic>{};
          final key = args['key']?.toString();
          switch (call.method) {
            case 'write':
              store[key!] = args['value']?.toString() ?? '';
              return null;
            case 'read':
              return key == null ? null : store[key];
            case 'delete':
              if (key != null) store.remove(key);
              return null;
            case 'deleteAll':
              store.clear();
              return null;
            case 'readAll':
              return store;
            case 'containsKey':
              return key != null && store.containsKey(key);
            default:
              return null;
          }
        });
  }
}

class _RefreshAdapter implements HttpClientAdapter {
  _RefreshAdapter({
    required this.refreshStatusCode,
    this.throwConnectionErrorOnRefresh = false,
  });

  final int refreshStatusCode;
  final bool throwConnectionErrorOnRefresh;

  @override
  void close({bool force = false}) {}

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    final isRefresh = options.path.contains('/token/refresh/');
    if (!isRefresh) {
      return ResponseBody.fromString(
        '{}',
        401,
        headers: {
          Headers.contentTypeHeader: [Headers.jsonContentType],
        },
      );
    }

    if (throwConnectionErrorOnRefresh) {
      throw DioException.connectionError(
        requestOptions: options,
        reason: 'simulated offline refresh failure',
      );
    }

    return ResponseBody.fromString(
      refreshStatusCode >= 200 && refreshStatusCode < 300
          ? '{"access":"new_access_token"}'
          : '{}',
      refreshStatusCode,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _FakeSecureStorageChannel secureStorage;

  setUp(() {
    secureStorage = _FakeSecureStorageChannel()..install();
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_FakeSecureStorageChannel._channel, null);
  });

  User cachedUser() => User(
    id: 1,
    username: 'teacher',
    email: 'teacher@example.com',
    role: UserRole.teacher,
    subscription: null,
  );

  group('ApiClient refresh failure handling', () {
    test('definitive refresh rejection clears stale tokens', () async {
      final client = ApiClient();
      await client.debugSeedAuthSession(
        access: 'old_access',
        refresh: 'old_refresh',
        user: cachedUser(),
      );

      client.debugSetHttpClientAdapter(_RefreshAdapter(refreshStatusCode: 401));

      await expectLater(client.getHierarchy(), throwsA(anything));

      expect(await client.isAuthenticated(), isFalse);
      expect(secureStorage.store.containsKey('access_token'), isFalse);
      expect(secureStorage.store.containsKey('refresh_token'), isFalse);
    });

    test(
      'temporary network failure during refresh preserves the session',
      () async {
        final client = ApiClient();
        await client.debugSeedAuthSession(
          access: 'old_access',
          refresh: 'old_refresh',
          user: cachedUser(),
        );

        client.debugSetHttpClientAdapter(
          _RefreshAdapter(
            refreshStatusCode: 0,
            throwConnectionErrorOnRefresh: true,
          ),
        );

        await expectLater(client.getHierarchy(), throwsA(anything));

        expect(await client.isAuthenticated(), isTrue);
        expect(secureStorage.store['access_token'], 'old_access');
        expect(secureStorage.store['refresh_token'], 'old_refresh');
      },
    );

    test(
      'missing refresh token clears an unrecoverable auth session',
      () async {
        final client = ApiClient();
        await client.debugSeedAuthSession(
          access: 'old_access',
          refresh: 'old_refresh',
          user: cachedUser(),
        );
        secureStorage.store.remove('refresh_token');

        client.debugSetHttpClientAdapter(
          _RefreshAdapter(refreshStatusCode: 200),
        );

        await expectLater(client.getHierarchy(), throwsA(anything));

        expect(await client.isAuthenticated(), isFalse);
        expect(secureStorage.store.containsKey('access_token'), isFalse);
        expect(secureStorage.store.containsKey('refresh_token'), isFalse);
      },
    );
  });
}
