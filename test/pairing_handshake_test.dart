import 'dart:async';
import 'dart:convert';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mirrorline/core/network/message_protocol.dart';
import 'package:mirrorline/core/network/socket_manager.dart';
import 'package:mirrorline/core/security/crypto_manager.dart';
import 'package:mirrorline/features/pairing/pairing_facade.dart';
import 'package:mirrorline/features/pairing/pairing_transport.dart';

class _FakeTransport implements PairingTransport {
  _FakeTransport({this.remoteAddress = '10.0.0.2'});

  @override
  final String? remoteAddress;
  final Object token = Object();
  bool current = true;
  FutureOr<void> Function(String, Map<String, dynamic>)? onSend;
  final List<(String, Map<String, dynamic>)> sent = [];

  @override
  Object get connectionToken => token;

  @override
  bool get isCurrent => current;

  @override
  Future<bool> send(String type, Map<String, dynamic> payload) async {
    if (!current) return false;
    sent.add((type, payload));
    await onSend?.call(type, payload);
    return current;
  }
}

class _FakeClientTransport extends _FakeTransport
    implements PairingClientTransport {
  _FakeClientTransport({
    required this.onMessage,
    required this.onDisconnected,
    super.remoteAddress,
  });

  final PairingMessageHandler onMessage;
  final void Function() onDisconnected;
  bool connectResult = true;
  int disconnectCount = 0;

  @override
  Future<bool> connect(String ip, int port, SecretKey key) async {
    current = connectResult;
    return connectResult;
  }

  @override
  Future<void> disconnect() async {
    disconnectCount++;
    current = false;
  }
}

typedef _FacadeBuilder = PairingFacade Function(Ref ref);

({ProviderContainer container, PairingFacade facade}) _createFacade(
  _FacadeBuilder builder,
) {
  late final StateNotifierProvider<PairingFacade, PairingState> provider;
  provider = StateNotifierProvider((ref) => builder(ref));
  final container = ProviderContainer();
  final facade = container.read(provider.notifier);
  return (container: container, facade: facade);
}

String get _keyBase64 => base64Encode(List<int>.filled(32, 7));

Future<void> _sendScannerRequest(PairingFacade facade) => facade.sendRequest(
  scannedId: 'scanned-id',
  scannedIp: '192.0.2.10',
  scannedPort: 45678,
  scannedKeyBase64: _keyBase64,
  scannedDeviceName: 'Scanned device',
  scannedPublicKey: 'scanned-public-key',
  myDeviceName: 'Scanner device',
  myPeerId: 'scanner-id',
  myRole: 'main',
  myPublicKey: 'scanner-public-key',
  myIp: '198.51.100.20',
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'scanner installs waiter before immediate accept and ACKs session',
    () async {
      late _FakeClientTransport transport;
      Map<String, dynamic>? persisted;
      final setup = _createFacade(
        (ref) => PairingFacade(
          ref,
          createSessionId: () => 'session-1',
          clientFactory: ({required onMessage, required onDisconnected}) {
            transport = _FakeClientTransport(
              onMessage: onMessage,
              onDisconnected: onDisconnected,
              remoteAddress: '203.0.113.8',
            );
            transport.onSend = (type, payload) async {
              if (type == MessageTypes.pairingRequest) {
                await onMessage(MessageTypes.pairingAccept, {
                  'sessionId': payload['sessionId'],
                  'peerId': 'scanned-id',
                  'publicKey': 'scanned-public-key',
                  'deviceName': 'Current scanned name',
                  'ip': 'untrusted.example',
                });
              } else if (type == MessageTypes.pairingAck) {
                await onMessage(MessageTypes.pairingComplete, {
                  'sessionId': payload['sessionId'],
                });
              }
            };
            return transport;
          },
          persistScanner: (data) async => persisted = data,
        ),
      );
      addTearDown(setup.container.dispose);

      await _sendScannerRequest(setup.facade);

      expect(persisted?['ip'], '203.0.113.8');
      expect(persisted?['deviceName'], 'Current scanned name');
      expect(transport.sent.last.$1, MessageTypes.pairingAck);
      expect(transport.sent.last.$2['sessionId'], 'session-1');
      expect(setup.facade.state.errorCode, isNull);
    },
  );

  test('scanner ignores wrong session then accepts expected session', () async {
    var persistCount = 0;
    final setup = _createFacade(
      (ref) => PairingFacade(
        ref,
        createSessionId: () => 'expected',
        clientFactory: ({required onMessage, required onDisconnected}) {
          final transport = _FakeClientTransport(
            onMessage: onMessage,
            onDisconnected: onDisconnected,
          );
          transport.onSend = (type, payload) async {
            if (type == MessageTypes.pairingRequest) {
              await onMessage(MessageTypes.pairingAccept, {
                'sessionId': 'stale',
                'peerId': 'scanned-id',
                'publicKey': 'scanned-public-key',
              });
              await onMessage(MessageTypes.pairingAccept, {
                'sessionId': 'expected',
                'peerId': 'scanned-id',
                'publicKey': 'scanned-public-key',
              });
            } else if (type == MessageTypes.pairingAck) {
              await onMessage(MessageTypes.pairingComplete, {
                'sessionId': payload['sessionId'],
              });
            }
          };
          return transport;
        },
        persistScanner: (_) async => persistCount++,
      ),
    );
    addTearDown(setup.container.dispose);

    await _sendScannerRequest(setup.facade);

    expect(persistCount, 1);
    expect(setup.facade.state.errorCode, isNull);
  });

  test('scanner rejects accept identity that differs from QR', () async {
    var persistCount = 0;
    final setup = _createFacade(
      (ref) => PairingFacade(
        ref,
        createSessionId: () => 'identity-session',
        clientFactory: ({required onMessage, required onDisconnected}) {
          final transport = _FakeClientTransport(
            onMessage: onMessage,
            onDisconnected: onDisconnected,
          );
          transport.onSend = (type, payload) async {
            if (type == MessageTypes.pairingRequest) {
              await onMessage(MessageTypes.pairingAccept, {
                'sessionId': 'identity-session',
                'peerId': 'attacker-id',
                'publicKey': 'attacker-key',
              });
            }
          };
          return transport;
        },
        persistScanner: (_) async => persistCount++,
      ),
    );
    addTearDown(setup.container.dispose);

    await _sendScannerRequest(setup.facade);

    expect(persistCount, 0);
    expect(setup.facade.state.errorCode, PairingErrorCode.handshakeFailed);
  });

  test('scanner rolls back persistence when ACK cannot be sent', () async {
    var persisted = false;
    var rolledBack = false;
    final setup = _createFacade(
      (ref) => PairingFacade(
        ref,
        createSessionId: () => 'rollback-session',
        clientFactory: ({required onMessage, required onDisconnected}) {
          final transport = _FakeClientTransport(
            onMessage: onMessage,
            onDisconnected: onDisconnected,
          );
          transport.onSend = (type, payload) async {
            if (type == MessageTypes.pairingRequest) {
              await onMessage(MessageTypes.pairingAccept, {
                'sessionId': 'rollback-session',
                'peerId': 'scanned-id',
                'publicKey': 'scanned-public-key',
              });
            } else if (type == MessageTypes.pairingAck) {
              transport.current = false;
            }
          };
          return transport;
        },
        persistScanner: (_) async => persisted = true,
        rollbackScanner: (_) async => rolledBack = true,
      ),
    );
    addTearDown(setup.container.dispose);

    await _sendScannerRequest(setup.facade);

    expect(persisted, isTrue);
    expect(rolledBack, isTrue);
    expect(setup.facade.state.errorCode, PairingErrorCode.handshakeFailed);
  });

  test('scanned side installs ACK waiter and uses transport address', () async {
    late PairingFacade facade;
    final transport = _FakeTransport(remoteAddress: '203.0.113.42');
    Map<String, dynamic>? persisted;
    final setup = _createFacade(
      (ref) => facade = PairingFacade(
        ref,
        localIdentity: () async => {
          'deviceName': 'Scanned device',
          'peerId': 'scanned-id',
          'publicKey': 'scanned-key',
          'role': 'source',
        },
        verificationCode: () => '',
        persistScanned: (data) async => persisted = data,
      ),
    );
    addTearDown(setup.container.dispose);
    transport.onSend = (type, payload) {
      if (type == MessageTypes.pairingAccept) {
        facade.handlePairingAck(transport, {'sessionId': payload['sessionId']});
      }
    };
    await facade.handleIncomingRequest(transport, {
      'sessionId': 'incoming-session',
      'deviceName': 'Scanner device',
      'peerId': 'scanner-id',
      'publicKey': 'scanner-key',
      'role': 'main',
      'ip': 'untrusted.example',
    });

    final accepted = await facade.acceptRequest(
      transport: transport,
      myIp: '192.0.2.2',
    );

    expect(accepted, isTrue);
    expect(persisted?['ip'], '203.0.113.42');
    expect(persisted?['peerId'], 'scanner-id');
  });

  test('wrong-session and stale-transport ACKs do not persist', () async {
    late PairingFacade facade;
    final transport = _FakeTransport();
    var persistCount = 0;
    final setup = _createFacade(
      (ref) => facade = PairingFacade(
        ref,
        ackTimeout: const Duration(milliseconds: 10),
        localIdentity: () async => {
          'deviceName': 'Scanned device',
          'peerId': 'scanned-id',
          'publicKey': 'scanned-key',
          'role': 'source',
        },
        verificationCode: () => '',
        persistScanned: (_) async => persistCount++,
      ),
    );
    addTearDown(setup.container.dispose);
    transport.onSend = (type, payload) {
      if (type != MessageTypes.pairingAccept) return;
      facade.handlePairingAck(transport, {'sessionId': 'wrong'});
      transport.current = false;
      facade.handlePairingAck(transport, {'sessionId': 'incoming-session'});
    };
    await facade.handleIncomingRequest(transport, {
      'sessionId': 'incoming-session',
      'peerId': 'scanner-id',
      'publicKey': 'scanner-key',
      'role': 'main',
    });

    await facade.acceptRequest(transport: transport, myIp: '192.0.2.2');

    expect(persistCount, 0);
    expect(facade.state.errorCode, PairingErrorCode.ackTimeout);
  });

  test('scanned persistence failure aborts the scanner session', () async {
    late PairingFacade facade;
    final transport = _FakeTransport();
    final setup = _createFacade(
      (ref) => facade = PairingFacade(
        ref,
        localIdentity: () async => {
          'deviceName': 'Scanned device',
          'peerId': 'scanned-id',
          'publicKey': 'scanned-key',
          'role': 'source',
        },
        verificationCode: () => '',
        persistScanned: (_) async => throw StateError('database failed'),
      ),
    );
    addTearDown(setup.container.dispose);
    transport.onSend = (type, payload) {
      if (type == MessageTypes.pairingAccept) {
        facade.handlePairingAck(transport, {'sessionId': payload['sessionId']});
      }
    };
    await facade.handleIncomingRequest(transport, {
      'sessionId': 'failing-session',
      'peerId': 'scanner-id',
      'publicKey': 'scanner-key',
      'role': 'main',
    });

    final accepted = await facade.acceptRequest(
      transport: transport,
      myIp: '192.0.2.2',
    );

    expect(accepted, isFalse);
    expect(transport.sent.last.$1, MessageTypes.pairingAbort);
    expect(transport.sent.last.$2['sessionId'], 'failing-session');
    expect(facade.state.errorCode, PairingErrorCode.handshakeFailed);
  });

  test(
    'cleanup from replaced scanner session cannot clear newer session',
    () async {
      final transports = <_FakeClientTransport>[];
      var nextSession = 0;
      var persistCount = 0;
      final firstRequestSent = Completer<void>();
      final setup = _createFacade(
        (ref) => PairingFacade(
          ref,
          createSessionId: () => 'session-${++nextSession}',
          clientFactory: ({required onMessage, required onDisconnected}) {
            final index = transports.length;
            final transport = _FakeClientTransport(
              onMessage: onMessage,
              onDisconnected: onDisconnected,
            );
            transport.onSend = (type, payload) async {
              if (type == MessageTypes.pairingRequest && index == 0) {
                firstRequestSent.complete();
              } else if (type == MessageTypes.pairingRequest) {
                await onMessage(MessageTypes.pairingAccept, {
                  'sessionId': payload['sessionId'],
                  'peerId': 'scanned-id',
                  'publicKey': 'scanned-public-key',
                });
              } else if (type == MessageTypes.pairingAck) {
                await onMessage(MessageTypes.pairingComplete, {
                  'sessionId': payload['sessionId'],
                });
              }
            };
            transports.add(transport);
            return transport;
          },
          persistScanner: (_) async => persistCount++,
        ),
      );
      addTearDown(setup.container.dispose);

      final first = _sendScannerRequest(setup.facade);
      await firstRequestSent.future;
      final second = _sendScannerRequest(setup.facade);
      await Future.wait([first, second]);

      expect(persistCount, 1);
      expect(transports, hasLength(2));
      expect(transports[0].disconnectCount, 1);
      expect(transports[1].sent.last.$1, MessageTypes.pairingAck);
      expect(setup.facade.state.errorCode, isNull);
    },
  );

  test('legacy request without session ID is rejected clearly', () async {
    final transport = _FakeTransport();
    final setup = _createFacade((ref) => PairingFacade(ref));
    addTearDown(setup.container.dispose);

    await setup.facade.handleIncomingRequest(transport, {
      'peerId': 'scanner-id',
      'publicKey': 'scanner-key',
      'role': 'main',
    });

    expect(setup.facade.state.isShowingRequest, isFalse);
    expect(setup.facade.state.errorCode, PairingErrorCode.handshakeFailed);
    expect(setup.facade.pendingScannerInfo, isNull);
  });

  test('pairing messages retain encrypted MirrorMessage framing', () async {
    final key = CryptoManager.generateKey();
    final received = Completer<Map<String, dynamic>>();
    final server = SocketManager(
      onMessage: (message) async {
        if (message.type != MessageTypes.pairingRequest) return;
        final cleartext = await CryptoManager.decrypt(key, message.payload);
        received.complete(jsonDecode(cleartext!) as Map<String, dynamic>);
      },
      onConnected: () {},
      onDisconnected: () {},
    );
    await server.startServer(45911, key);
    final client = SocketManager(
      onMessage: (_) {},
      onConnected: () {},
      onDisconnected: () {},
    );
    addTearDown(client.disconnect);
    addTearDown(server.disconnect);
    expect(await client.connect('127.0.0.1', 45911, key), isTrue);

    await client.sendMessage(MessageTypes.pairingRequest, {
      'sessionId': 'encrypted-session',
      'peerId': 'scanner-id',
    });

    expect(
      (await received.future.timeout(const Duration(seconds: 3)))['sessionId'],
      'encrypted-session',
    );
  });
}
