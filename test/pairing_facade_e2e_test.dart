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
