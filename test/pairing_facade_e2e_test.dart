import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mirrorline/core/data/database.dart';
import 'package:mirrorline/core/data/daos/peer_dao.dart';
import 'package:mirrorline/core/data/models/peer.dart';
import 'package:mirrorline/core/network/message_protocol.dart';
import 'package:mirrorline/core/network/socket_manager.dart';
import 'package:mirrorline/core/security/crypto_manager.dart';
import 'package:mirrorline/core/security/security_constants.dart';
import 'package:mirrorline/features/pairing/pairing_facade.dart';
import 'package:mirrorline/features/pairing/peer_facade.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
  });

  test(
    'Main scans Source, persists both sides, then Main reconnects',
    () async {
      await _runPairingAndReconnect(scannerRole: 'main');
    },
  );

  test(
    'Source scans Main, persists both sides, then Main reconnects',
    () async {
      await _runPairingAndReconnect(scannerRole: 'source');
    },
  );

  test('immediate accept completes before request write returns', () async {
    final key = CryptoManager.generateKey();
    final writeGate = Completer<void>();
    final scanner = await _Device.create(
      id: 'scanner-id',
      name: 'Scanner',
      role: 'main',
      ip: '10.42.0.1',
      port: 45678,
      pairingKey: key,
      createHandshakeSocket:
          ({
            required onMessage,
            required onConnected,
            required onDisconnected,
          }) => _ControlledSocketManager(
            onMessage: onMessage,
            onDisconnected: onDisconnected,
            send: (type, payload) async {
              if (type == MessageTypes.pairingRequest) {
                onMessage(
                  await _encryptedMessage(key, MessageTypes.pairingAccept, {
                    'transactionId': payload['transactionId'],
                    'deviceName': 'Scanned',
                    'peerId': 'scanned-id',
                    'publicKey': 'scanned-public-key',
                    'role': 'source',
                    'ip': '10.42.0.2',
                  }),
                );
                await writeGate.future;
              }
              return true;
            },
          ),
    );
    addTearDown(scanner.dispose);

    var completed = false;
    final request = _sendScannerRequest(scanner).whenComplete(() {
      completed = true;
    });
    await _waitFor(() => !scanner.pairing.state.isWaitingForAccept);

    expect(completed, isFalse);
    expect(scanner.pairing.state.errorCode, isNull);
    writeGate.complete();
    await request;
    expect(scanner.pairing.state.isComplete, isTrue);
    expect((await scanner.dao.getPeer())?.id, 'scanned-id');
  });

  test('immediate ack completes before accept write returns', () async {
    final key = CryptoManager.generateKey();
    final writeGate = Completer<void>();
    final scanned = await _Device.create(
      id: 'scanned-id',
      name: 'Scanned',
      role: 'source',
      ip: '10.42.0.2',
      port: 45678,
      pairingKey: key,
    );
    addTearDown(scanned.dispose);
    final scannerInfo = _scannerInfo(transactionId: 'immediate-ack');
    await scanned.pairing.handleIncomingRequest(scannerInfo);
    final socket = _ControlledSocketManager(
      send: (type, payload) async {
        if (type == MessageTypes.pairingAccept) {
          scanned.pairing.handlePairingAck(_ackFor(scannerInfo));
          await writeGate.future;
        }
        return true;
      },
    );

    var completed = false;
    final accept = scanned.pairing
        .acceptRequest(
          socketManager: socket,
          scannerInfo: scannerInfo,
          myIp: scanned.ip,
        )
        .whenComplete(() => completed = true);
    await _waitFor(() => scanned.pairing.state.isFinalizing);

    expect(completed, isFalse);
    writeGate.complete();
    await accept;
    expect(scanned.pairing.state.isComplete, isTrue);
    expect((await scanned.dao.getPeer())?.id, 'scanner-id');
  });

  test(
    'scanner disconnect fails old transaction without closing replacement',
    () async {
      final key = CryptoManager.generateKey();
      final sockets = <_ControlledSocketManager>[];
      final oldDisconnectGate = Completer<void>();
      final scanner = await _Device.create(
        id: 'scanner-id',
        name: 'Scanner',
        role: 'main',
        ip: '10.42.0.1',
        port: 45678,
        pairingKey: key,
        createHandshakeSocket:
            ({
              required onMessage,
              required onConnected,
              required onDisconnected,
            }) {
              final socket = _ControlledSocketManager(
                onMessage: onMessage,
                onDisconnected: onDisconnected,
                disconnectGate: sockets.isEmpty ? oldDisconnectGate : null,
                send: (type, payload) async {
                  if (sockets.length == 2 &&
                      type == MessageTypes.pairingRequest) {
                    onMessage(
                      await _encryptedMessage(key, MessageTypes.pairingAccept, {
                        'transactionId': payload['transactionId'],
                        'deviceName': 'Replacement',
                        'peerId': 'scanned-id',
                        'publicKey': 'scanned-public-key',
                        'role': 'source',
                        'ip': '10.42.0.2',
                      }),
                    );
                  }
                  return true;
                },
              );
              sockets.add(socket);
              return socket;
            },
      );
      addTearDown(scanner.dispose);

      final first = _sendScannerRequest(scanner);
      await _waitFor(() => sockets.isNotEmpty);
      sockets.first.emitDisconnected();
      await _waitFor(
        () => scanner.pairingStates.any(
          (state) => state.errorCode == PairingErrorCode.rejectedOrTimedOut,
        ),
      );

      final replacement = _sendScannerRequest(scanner);
      await _waitFor(() => sockets.length == 2);
      oldDisconnectGate.complete();
      await first;
      await replacement;

      expect(sockets[1].disconnectCount, 1);
      expect(scanner.pairing.state.isComplete, isTrue);
      expect((await scanner.dao.getPeer())?.id, 'scanned-id');
    },
  );

  test(
    'scanned disconnect fails finalization without corrupting replacement',
    () async {
      final key = CryptoManager.generateKey();
      final scanned = await _Device.create(
        id: 'scanned-id',
        name: 'Scanned',
        role: 'source',
        ip: '10.42.0.2',
        port: 45678,
        pairingKey: key,
      );
      addTearDown(scanned.dispose);
      final oldInfo = _scannerInfo(transactionId: 'old-transaction');
      await scanned.pairing.handleIncomingRequest(oldInfo);
      final oldSocket = _ControlledSocketManager();
      final oldAccept = scanned.pairing.acceptRequest(
        socketManager: oldSocket,
        scannerInfo: oldInfo,
        myIp: scanned.ip,
      );
      await _waitFor(() => scanned.pairing.state.isFinalizing);

      scanned.pairing.handleSocketDisconnected(oldSocket);
      expect(scanned.pairing.state.errorCode, PairingErrorCode.ackTimeout);

      final newInfo = _scannerInfo(transactionId: 'new-transaction');
      await scanned.pairing.handleIncomingRequest(newInfo);
      final newSocket = _ControlledSocketManager(
        send: (type, payload) async {
          if (type == MessageTypes.pairingAccept) {
            scanned.pairing.handlePairingAck(_ackFor(newInfo));
          }
          return true;
        },
      );
      final newAccept = scanned.pairing.acceptRequest(
        socketManager: newSocket,
        scannerInfo: newInfo,
        myIp: scanned.ip,
      );
      scanned.pairing.handleSocketDisconnected(oldSocket);

      await oldAccept;
      await newAccept;
      expect(scanned.pairing.state.isComplete, isTrue);
      expect((await scanned.dao.getPeer())?.id, 'scanner-id');
    },
  );

  test(
    'failed request and ack writes never complete scanner pairing',
    () async {
      final key = CryptoManager.generateKey();
      var failRequest = true;
      final scanner = await _Device.create(
        id: 'scanner-id',
        name: 'Scanner',
        role: 'main',
        ip: '10.42.0.1',
        port: 45678,
        pairingKey: key,
        createHandshakeSocket:
            ({
              required onMessage,
              required onConnected,
              required onDisconnected,
            }) => _ControlledSocketManager(
              onMessage: onMessage,
              onDisconnected: onDisconnected,
              send: (type, payload) async {
                if (type == MessageTypes.pairingRequest && failRequest) {
                  return false;
                }
                if (type == MessageTypes.pairingRequest) {
                  onMessage(
                    await _encryptedMessage(key, MessageTypes.pairingAccept, {
                      'transactionId': payload['transactionId'],
                      'deviceName': 'Scanned',
                      'peerId': 'scanned-id',
                      'publicKey': 'scanned-public-key',
                      'role': 'source',
                      'ip': '10.42.0.2',
                    }),
                  );
                }
                return type != MessageTypes.pairingAck;
              },
            ),
      );
      addTearDown(scanner.dispose);

      await _sendScannerRequest(scanner);
      expect(scanner.pairing.state.errorCode, PairingErrorCode.handshakeFailed);
      expect(scanner.pairing.state.isComplete, isFalse);
      expect((await scanner.dao.getPeer())?.id, 'scanner-id');

      failRequest = false;
      await _sendScannerRequest(scanner);
      expect(scanner.pairing.state.errorCode, PairingErrorCode.handshakeFailed);
      expect(scanner.pairing.state.isComplete, isFalse);
      expect((await scanner.dao.getPeer())?.id, 'scanned-id');
    },
  );

  test('failed accept and reject writes remain terminal failures', () async {
    final key = CryptoManager.generateKey();
    final scanned = await _Device.create(
      id: 'scanned-id',
      name: 'Scanned',
      role: 'source',
      ip: '10.42.0.2',
      port: 45678,
      pairingKey: key,
    );
    addTearDown(scanned.dispose);
    final socket = _ControlledSocketManager(send: (_, _) async => false);

    final acceptInfo = _scannerInfo(transactionId: 'failed-accept');
    await scanned.pairing.handleIncomingRequest(acceptInfo);
    await scanned.pairing.acceptRequest(
      socketManager: socket,
      scannerInfo: acceptInfo,
      myIp: scanned.ip,
    );
    expect(scanned.pairing.state.errorCode, PairingErrorCode.handshakeFailed);
    expect(scanned.pairing.state.isComplete, isFalse);
    expect((await scanned.dao.getPeer())?.id, 'scanned-id');

    await scanned.pairing.handleIncomingRequest(
      _scannerInfo(transactionId: 'failed-reject'),
    );
    await scanned.pairing.rejectRequest(socketManager: socket);
    expect(scanned.pairing.state.errorCode, PairingErrorCode.handshakeFailed);
    expect(scanned.pairing.pendingScannerInfo, isNull);
  });
}

Future<void> _sendScannerRequest(_Device scanner) {
  return scanner.pairing.sendRequest(
    scannedId: 'scanned-id',
    scannedIp: '10.42.0.2',
    scannedPort: 45678,
    scannedKeyBase64: scanner.selfPeer.key,
    scannedDeviceName: 'Scanned',
    scannedPublicKey: 'scanned-public-key',
    myIp: scanner.ip,
  );
}

Map<String, dynamic> _scannerInfo({required String transactionId}) => {
  'transactionId': transactionId,
  'deviceName': 'Scanner',
  'peerId': 'scanner-id',
  'role': 'main',
  'publicKey': 'scanner-public-key',
  'ip': '10.42.0.1',
};

Map<String, dynamic> _ackFor(Map<String, dynamic> scannerInfo) => {
  'transactionId': scannerInfo['transactionId'],
  'peerId': scannerInfo['peerId'],
  'publicKey': scannerInfo['publicKey'],
};

Future<MirrorMessage> _encryptedMessage(
  SecretKey key,
  String type,
  Map<String, dynamic> payload,
) async {
  final id = 'message-${DateTime.now().microsecondsSinceEpoch}';
  final timestamp = DateTime.now().millisecondsSinceEpoch;
  final metadata = CryptoManager.canonicalMessageMetadata(
    version: SecurityConstants.protocolVersion,
    type: type,
    id: id,
    timestamp: timestamp,
  );
  return MirrorMessage(
    type: type,
    id: id,
    timestamp: timestamp,
    payload: await CryptoManager.encryptWithAad(
      key,
      jsonEncode(payload),
      aad: utf8.encode(metadata),
    ),
  );
}

Future<void> _runPairingAndReconnect({required String scannerRole}) async {
  final bootstrapKey = CryptoManager.generateKey();
  final bootstrapMessages = <String>[];
  late _Device scanned;
  late final SocketManager bootstrapServer;
  bootstrapServer = SocketManager(
    onMessage: (message) {
      bootstrapMessages.add(message.type);
      unawaited(
        _routeBootstrapMessage(
          device: scanned,
          socket: bootstrapServer,
          key: bootstrapKey,
          message: message,
        ),
      );
    },
  );
  addTearDown(bootstrapServer.disconnect);
  await bootstrapServer.startServer(0, bootstrapKey);
  final port = bootstrapServer.boundPort!;

  final main = await _Device.create(
    id: 'main-id',
    name: 'Main Device',
    role: 'main',
    ip: '10.42.0.1',
    port: port,
    pairingKey: scannerRole == 'source'
        ? bootstrapKey
        : CryptoManager.generateKey(),
  );
  final source = await _Device.create(
    id: 'source-id',
    name: 'Source Device',
    role: 'source',
    ip: '10.42.0.2',
    port: port,
    pairingKey: scannerRole == 'main'
        ? bootstrapKey
        : CryptoManager.generateKey(),
  );
  addTearDown(main.dispose);
  addTearDown(source.dispose);

  final scanner = scannerRole == 'main' ? main : source;
  scanned = scannerRole == 'main' ? source : main;

  final request = scanner.pairing.sendRequest(
    scannedId: scanned.id,
    scannedIp: scanned.ip,
    scannedPort: port,
    scannedKeyBase64: scanned.selfPeer.key,
    scannedDeviceName: scanned.name,
    scannedPublicKey: scanned.identity.publicKey,
    myIp: scanner.ip,
  );

  await _waitFor(() => scanned.pairing.state.isShowingRequest);
  expect(scanner.pairing.state.isWaitingForAccept, isTrue);
  expect(scanned.pairing.pendingScannerInfo?['peerId'], scanner.id);
  expect(bootstrapMessages, contains(MessageTypes.pairingRequest));

  final accept = scanned.pairing.acceptRequest(
    socketManager: bootstrapServer,
    scannerInfo: scanned.pairing.pendingScannerInfo!,
    myIp: scanned.ip,
  );

  await request.timeout(const Duration(seconds: 5));
  await accept.timeout(const Duration(seconds: 5));
  expect(scanned.pairingStates.any((state) => state.isFinalizing), isTrue);
  expect(scanner.pairing.state.isComplete, isTrue);
  expect(scanned.pairing.state.isComplete, isTrue);
  expect(bootstrapMessages, [
    MessageTypes.pairingRequest,
    MessageTypes.pairingAck,
  ]);

  final mainPeer = await main.dao.getPeer();
  final sourcePeer = await source.dao.getPeer();
  expect(mainPeer, isNotNull);
  expect(sourcePeer, isNotNull);
  _expectPersistedPeer(
    actual: mainPeer!,
    remote: source,
    localRole: 'main',
    sharedKey: scanned.selfPeer.key,
    port: port,
  );
  await _expectStoredConnectionIdentity(
    main,
    remote: source,
    key: bootstrapKey,
  );
  await _expectStoredConnectionIdentity(
    source,
    remote: main,
    key: bootstrapKey,
  );
  _expectPersistedPeer(
    actual: sourcePeer!,
    remote: main,
    localRole: 'source',
    sharedKey: scanned.selfPeer.key,
    port: port,
  );

  await bootstrapServer.disconnect();

  final delivered = Completer<MirrorMessage>();
  final sourceConnected = Completer<void>();
  final sourceServer = SocketManager(
    onMessage: (message) {
      if (!delivered.isCompleted) delivered.complete(message);
    },
    onConnected: sourceConnected.complete,
  )..requireAuthIdentity();
  addTearDown(sourceServer.disconnect);
  sourceServer.setAuthIdentity(
    peerPublicKeyBase64: sourcePeer.publicKey,
    localKeyPair: source.identity.keyPair,
    localDeviceId: source.id,
    peerDeviceId: sourcePeer.id,
  );
  await sourceServer.startServer(port, source.identity.peerKey!);

  final mainClient = SocketManager(onMessage: (_) {})..requireAuthIdentity();
  addTearDown(mainClient.disconnect);
  mainClient.setAuthIdentity(
    peerPublicKeyBase64: mainPeer.publicKey,
    localKeyPair: main.identity.keyPair,
    localDeviceId: main.id,
    peerDeviceId: mainPeer.id,
  );

  expect(mainPeer.role, 'main', reason: 'persisted Main role must dial');
  expect(
    sourcePeer.role,
    'source',
    reason: 'persisted Source role must listen',
  );
  expect(mainPeer.ip, source.ip);
  expect(
    await mainClient.connect(
      _transportAddress(mainPeer.ip),
      mainPeer.port,
      main.identity.peerKey!,
    ),
    isTrue,
  );
  await sourceConnected.future.timeout(const Duration(seconds: 5));
  expect(mainClient.isAuthed, isTrue);
  expect(sourceServer.isAuthed, isTrue);
  expect(mainClient.isPairingMode, isFalse);
  expect(sourceServer.isPairingMode, isFalse);

  const postAuthPayload = {'body': 'authenticated reconnect payload'};
  expect(
    await mainClient.sendMessage(MessageTypes.smsIncoming, postAuthPayload),
    isTrue,
  );
  final message = await delivered.future.timeout(const Duration(seconds: 5));
  expect(message.type, MessageTypes.smsIncoming);
  expect(message.sessionId, isNotEmpty);
  expect(message.sequence, 1);
  expect(
    await _decryptPayload(main.identity.peerKey!, message),
    postAuthPayload,
  );
}

Future<void> _routeBootstrapMessage({
  required _Device device,
  required SocketManager socket,
  required SecretKey key,
  required MirrorMessage message,
}) async {
  final payload = await _decryptPayload(key, message);
  switch (message.type) {
    case MessageTypes.pairingRequest:
      await device.pairing.handleIncomingRequest(
        payload,
        liveRemoteAddress: socket.remoteAddress,
      );
    case MessageTypes.pairingAck:
      device.pairing.handlePairingAck(payload);
  }
}

Future<Map<String, dynamic>> _decryptPayload(
  SecretKey key,
  MirrorMessage message,
) async {
  final metadata = CryptoManager.canonicalMessageMetadata(
    version: message.protocolVersion,
    type: message.type,
    id: message.id,
    timestamp: message.timestamp,
  );
  final decrypted = await CryptoManager.decryptWithAad(
    key,
    message.payload,
    aad: utf8.encode(metadata),
  );
  return jsonDecode(decrypted!) as Map<String, dynamic>;
}

void _expectPersistedPeer({
  required Peer actual,
  required _Device remote,
  required String localRole,
  required String sharedKey,
  required int port,
}) {
  expect(actual.id, remote.id);
  expect(actual.deviceName, remote.name);
  expect(actual.publicKey, remote.identity.publicKey);
  expect(actual.ip, remote.ip);
  expect(actual.port, port);
  expect(actual.role, localRole);
  expect(actual.key, sharedKey);
}

String _transportAddress(String logicalIp) {
  expect(logicalIp, anyOf('10.42.0.1', '10.42.0.2'));
  return InternetAddress.loopbackIPv4.address;
}

Future<void> _expectStoredConnectionIdentity(
  _Device device, {
  required _Device remote,
  required SecretKey key,
}) async {
  expect(device.identity.peerId, remote.id);
  expect(device.identity.peerKey, isNotNull);
  expect(
    await device.identity.peerKey!.extractBytes(),
    await key.extractBytes(),
  );
}

Future<void> _waitFor(bool Function() condition) async {
  final deadline = DateTime.now().add(const Duration(seconds: 5));
  while (!condition()) {
    if (DateTime.now().isAfter(deadline)) {
      throw TimeoutException('Condition was not met.');
    }
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
}

class _Device {
  final String id;
  final String name;
  final String role;
  final String ip;
  final Peer selfPeer;
  final Database database;
  final PeerDao dao;
  final _MemoryPeerIdentityStore identity;
  final ProviderContainer container;
  final PeerFacade peers;
  final List<PairingState> pairingStates;

  _Device({
    required this.id,
    required this.name,
    required this.role,
    required this.ip,
    required this.selfPeer,
    required this.database,
    required this.dao,
    required this.identity,
    required this.container,
    required this.peers,
    required this.pairingStates,
  });

  PairingFacade get pairing => container.read(pairingFacadeProvider.notifier);

  static Future<_Device> create({
    required String id,
    required String name,
    required String role,
    required String ip,
    required int port,
    required SecretKey pairingKey,
    PairingHandshakeSocketFactory? createHandshakeSocket,
  }) async {
    final database = await databaseFactory.openDatabase(
      inMemoryDatabasePath,
      options: OpenDatabaseOptions(
        version: AppDatabase.schemaVersion,
        onCreate: AppDatabase.instance.createTables,
        singleInstance: false,
      ),
    );
    final dao = PeerDao.forDatabase(database);
    final identity = await _MemoryPeerIdentityStore.create(
      id: id,
      deviceName: name,
      role: role,
    );
    final selfPeer = Peer(
      id: id,
      deviceName: name,
      role: role,
      ip: ip,
      port: port,
      key: base64Encode(await pairingKey.extractBytes()),
      publicKey: '',
      createdAt: DateTime.now(),
    );
    await dao.insert(selfPeer);
    await identity.setPeerId(id);
    await identity.setPeerKey(pairingKey);

    final peers = PeerFacade(dao: dao, identityStore: identity);
    late final ProviderContainer container;
    container = ProviderContainer(
      overrides: [
        peerFacadeProvider.overrideWith((ref) => peers),
        pairingFacadeProvider.overrideWith(
          (ref) => PairingFacade(
            ref,
            getLocalAddresses: () async => [ip],
            getLocalIdentity: () async =>
                (id: identity.id, publicKey: identity.publicKey),
            invalidateNormalConnectionWork: () async {},
            connectHandshakeSocket: (socket, logicalIp, port, key) {
              return socket.connect(_transportAddress(logicalIp), port, key);
            },
            createHandshakeSocket: createHandshakeSocket,
          ),
        ),
      ],
    );
    final pairingStates = <PairingState>[];
    container.listen<PairingState>(pairingFacadeProvider, (_, next) {
      pairingStates.add(next);
    }, fireImmediately: true);
    await peers.initialized;
    return _Device(
      id: id,
      name: name,
      role: role,
      ip: ip,
      selfPeer: selfPeer,
      database: database,
      dao: dao,
      identity: identity,
      container: container,
      peers: peers,
      pairingStates: pairingStates,
    );
  }

  Future<void> dispose() async {
    container.dispose();
    await database.close();
  }
}

class _ControlledSocketManager extends SocketManager {
  final Future<bool> Function(String, Map<String, dynamic>) _send;
  final void Function()? _emitDisconnected;
  final Completer<void>? disconnectGate;
  int disconnectCount = 0;

  _ControlledSocketManager({
    Future<bool> Function(String, Map<String, dynamic>)? send,
    void Function(MirrorMessage)? onMessage,
    void Function()? onDisconnected,
    this.disconnectGate,
  }) : _send = send ?? ((_, _) async => true),
       _emitDisconnected = onDisconnected,
       super(onMessage: onMessage ?? (_) {});

  void emitDisconnected() => _emitDisconnected?.call();

  @override
  Future<bool> connect(
    String ip,
    int port,
    SecretKey key, {
    Duration? connectTimeout,
  }) async => true;

  @override
  Future<bool> sendMessage(String type, Map<String, dynamic> payload) =>
      _send(type, payload);

  @override
  Future<void> disconnect() async {
    disconnectCount++;
    await disconnectGate?.future;
  }
}

class _MemoryPeerIdentityStore implements PeerIdentityStore {
  final String id;
  final String deviceName;
  String role;
  final SimpleKeyPair keyPair;
  final String publicKey;
  String? peerId;
  SecretKey? peerKey;

  _MemoryPeerIdentityStore({
    required this.id,
    required this.deviceName,
    required this.role,
    required this.keyPair,
    required this.publicKey,
  });

  static Future<_MemoryPeerIdentityStore> create({
    required String id,
    required String deviceName,
    required String role,
  }) async {
    final keyPair = await Ed25519().newKeyPair();
    final publicKey = base64Encode((await keyPair.extractPublicKey()).bytes);
    return _MemoryPeerIdentityStore(
      id: id,
      deviceName: deviceName,
      role: role,
      keyPair: keyPair,
      publicKey: publicKey,
    );
  }

  @override
  Future<void> clearPeerId() async => peerId = null;

  @override
  Future<void> clearPeerKey() async => peerKey = null;

  @override
  Future<String> ensureDeviceKeyPair() async => publicKey;

  @override
  Future<String?> getSelfDeviceName() async => deviceName;

  @override
  Future<String?> getSelfId() async => id;

  @override
  Future<String?> getSelfRole() async => role;

  @override
  Future<void> setPeerId(String id) async => peerId = id;

  @override
  Future<void> setPeerKey(SecretKey key) async => peerKey = key;

  @override
  Future<void> setSelfIdentity({
    required String id,
    required String deviceName,
    required String role,
  }) async {}

  @override
  Future<void> setSelfRole(String role) async => this.role = role;
}
