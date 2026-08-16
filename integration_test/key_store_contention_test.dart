import 'dart:async';
import 'dart:isolate';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:mirrorline/core/security/key_store.dart';

void _ensureIdentityInBackground(List<Object> arguments) async {
  final token = arguments[0] as RootIsolateToken;
  final results = arguments[1] as SendPort;
  final commands = ReceivePort();

  BackgroundIsolateBinaryMessenger.ensureInitialized(token);
  results.send(['ready', commands.sendPort]);
  await commands.first;

  try {
    results.send(['result', await KeyStore.ensureDeviceKeyPair()]);
  } catch (error) {
    results.send(['error', error.toString()]);
  } finally {
    commands.close();
  }
}

Future<_BackgroundIdentityCall> _startBackgroundIdentityCall(
  RootIsolateToken token,
) async {
  final results = ReceivePort();
  await Isolate.spawn(_ensureIdentityInBackground, [token, results.sendPort]);
  final iterator = StreamIterator(results);
  await iterator.moveNext();
  final ready = iterator.current as List<Object?>;
  return _BackgroundIdentityCall(iterator, ready[1]! as SendPort);
}

class _BackgroundIdentityCall {
  const _BackgroundIdentityCall(this._results, this._commands);

  final StreamIterator<dynamic> _results;
  final SendPort _commands;

  void start() => _commands.send(null);

  Future<String> result() async {
    await _results.moveNext();
    final response = _results.current as List<Object?>;
    await _results.cancel();
    if (response[0] == 'error') throw StateError(response[1].toString());
    return response[1]! as String;
  }
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('cross-isolate contention leaves a recoverable identity', (
    tester,
  ) async {
    await KeyStore.clearDeviceKeyPair();
    addTearDown(KeyStore.clearDeviceKeyPair);

    final rootToken = RootIsolateToken.instance;
    expect(rootToken, isNotNull);
    final token = rootToken!;
    final calls = await Future.wait([
      _startBackgroundIdentityCall(token),
      _startBackgroundIdentityCall(token),
    ]);
    final backgroundResults = calls.map((call) => call.result()).toList();

    for (final call in calls) {
      call.start();
    }
    final created = await Future.wait([
      KeyStore.ensureDeviceKeyPair(),
      ...backgroundResults,
    ]);

    final persisted = await KeyStore.getDevicePublicKey();
    expect(persisted, isNotNull);
    expect(await KeyStore.getDeviceKeyPair(), isNotNull);
    expect(created, everyElement(hasLength(44)));
    expect(await KeyStore.ensureDeviceKeyPair(), persisted);
  });
}
