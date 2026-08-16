import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mirrorline/core/security/key_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('plugins.it_nomads.com/flutter_secure_storage');
  final values = <String, String>{};

  setUp(() {
    values.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          final arguments = Map<String, dynamic>.from(call.arguments as Map);
          final key = arguments['key'] as String;
          switch (call.method) {
            case 'read':
              return values[key];
            case 'write':
              values[key] = arguments['value'] as String;
              return null;
            case 'delete':
              values.remove(key);
              return null;
            default:
              throw UnimplementedError(call.method);
          }
        });
  });

  tearDown(() async {
    await KeyStore.clearDeviceKeyPair();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test('stores a validated device identity as one atomic record', () async {
    final publicKey = await KeyStore.ensureDeviceKeyPair();

    expect(values.keys, contains('device_ed25519'));
    expect(values.keys, isNot(contains('device_ed25519_private')));
    expect(values.keys, isNot(contains('device_ed25519_public')));
    expect(await KeyStore.getDevicePublicKey(), publicKey);
    expect(await KeyStore.getDeviceKeyPair(), isNotNull);
  });

  test('fails closed for corrupted atomic identity records', () async {
    values['device_ed25519'] = jsonEncode({
      'version': 1,
      'privateKey': base64Encode(List<int>.filled(32, 1)),
      'publicKey': base64Encode(List<int>.filled(32, 2)),
    });

    expect(await KeyStore.getDevicePublicKey(), isNull);
    expect(await KeyStore.getDeviceKeyPair(), isNull);
    expect(KeyStore.ensureDeviceKeyPair, throwsStateError);
  });

  test('migrates only a complete valid legacy identity', () async {
    final publicKey = await KeyStore.ensureDeviceKeyPair();
    final record =
        jsonDecode(values.remove('device_ed25519')!) as Map<String, dynamic>;
    values['device_ed25519_private'] = record['privateKey'] as String;
    values['device_ed25519_public'] = record['publicKey'] as String;

    expect(await KeyStore.getDevicePublicKey(), publicKey);
    expect(await KeyStore.ensureDeviceKeyPair(), publicKey);
    expect(values['device_ed25519'], isNotNull);
    expect(values, isNot(contains('device_ed25519_private')));
    expect(values, isNot(contains('device_ed25519_public')));
  });

  test('fails closed for partial legacy identities', () async {
    values['device_ed25519_private'] = base64Encode(List<int>.filled(32, 1));

    expect(await KeyStore.getDevicePublicKey(), isNull);
    expect(KeyStore.ensureDeviceKeyPair, throwsStateError);
  });
}
