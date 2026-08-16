// Verifies Peer model + PeerDao correctly persist and read back the
// paired peer's IP, role, deviceName, publicKey -- the fields the pairing
// handshake populates. Uses sqflite_ffi so it exercises the real DAO
// against the real (in-memory) SQLite schema.
import 'package:flutter_test/flutter_test.dart';
import 'package:mirrorline/core/data/database.dart';
import 'package:mirrorline/core/data/daos/peer_dao.dart';
import 'package:mirrorline/core/data/models/peer.dart';
import 'package:mirrorline/features/pairing/peer_facade.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  test(
    'applyPairedPeer persists the scanner IP claimed in the handshake',
    () async {
      final db = await databaseFactory.openDatabase(
        inMemoryDatabasePath,
        options: OpenDatabaseOptions(
          version: AppDatabase.schemaVersion,
          onCreate: AppDatabase.instance.createTables,
        ),
      );

      // Simulate a pre-pairing self row on the scanned device: ip is this
      // device's own local IP, role is this device's own role, publicKey is
      // empty (no peer paired yet).
      final self = Peer(
        id: 'self-id-1',
        deviceName: 'My Device',
        role: 'source',
        ip: '192.168.1.10',
        port: 45678,
        key: 'shared-key-base64',
        publicKey: '',
        createdAt: DateTime.now(),
      );
      final dao = PeerDao.forDatabase(db);
      await dao.insert(self);

      // Mimic applyPairedPeer: the scanner claimed its IP in the
      // pairingRequest payload. applyPairedPeer must store that IP, not the
      // TCP remote address (which can be wrong on NAT/VLAN) and not the
      // pre-pairing self IP (the "peer IP = this device's own IP" bug).
      final scannerClaimedIp = '192.168.1.42';
      final updated = self.copyWith(
        id: 'scanner-id-2',
        deviceName: 'Scanner Device',
        publicKey: 'scanner-pub-key',
        ip: scannerClaimedIp,
      );
      await dao.replaceId(self.id, updated);

      final stored = await dao.getPeer();
      expect(stored, isNotNull);
      expect(
        stored!.id,
        'scanner-id-2',
        reason: 'id must switch to the scanner (other device) after pairing',
      );
      expect(stored.deviceName, 'Scanner Device');
      expect(stored.publicKey, 'scanner-pub-key');
      expect(
        stored.role,
        'source',
        reason: 'role is this device\'s own role, preserved across pairing',
      );
      expect(
        stored.ip,
        scannerClaimedIp,
        reason:
            'ip must be the scanner\'s claimed IP, not this device\'s '
            'own pre-pairing IP -- this is the bug that made Settings show '
            'the paired device\'s IP as this device\'s own IP',
      );
      expect(
        stored.key,
        'shared-key-base64',
        reason: 'shared AES key is preserved across pairing',
      );

      await db.close();
    },
  );

  test(
    'createPeerFromQr persists the scanned device\'s accept-claimed IP',
    () async {
      final db = await databaseFactory.openDatabase(
        inMemoryDatabasePath,
        options: OpenDatabaseOptions(
          version: AppDatabase.schemaVersion,
          onCreate: AppDatabase.instance.createTables,
        ),
      );

      final dao = PeerDao.forDatabase(db);

      // The scanner reads the QR (with the stale IP) but the scanned device
      // claims its real IP in pairingAccept -- the scanner must persist the
      // claimed IP, not the QR's IP.
      final staleQrIp = '10.0.0.5';
      final acceptClaimedIp = '192.168.1.99';

      final peer = Peer(
        id: 'scanned-id-3',
        deviceName: 'Scanned Device',
        role: 'main', // this device's own role
        ip: acceptClaimedIp, // accept IP overrides QR IP
        port: 45678,
        key: 'shared-key-base64',
        publicKey: 'scanned-pub',
        createdAt: DateTime.now(),
      );
      await dao.insert(peer);

      final stored = await dao.getPeer();
      expect(stored, isNotNull);
      expect(
        stored!.ip,
        acceptClaimedIp,
        reason:
            'scanner must store the IP the scanned device claimed in '
            'pairingAccept, not the stale IP from the QR ($staleQrIp)',
      );
      expect(stored.id, 'scanned-id-3');
      expect(stored.deviceName, 'Scanned Device');
      expect(stored.publicKey, 'scanned-pub');
      expect(stored.role, 'main');

      await db.close();
    },
  );

  test('beacon-discovered IP refines the peer IP after pairing', () async {
    // After pairing, beacon discovery may find the peer at a new address
    // (e.g. it roamed to a different subnet). The new IP must overwrite the
    // handshake-claimed IP -- this is what ConnectionFacade.
    // _recordDiscoveredAddress does.
    final db = await databaseFactory.openDatabase(
      inMemoryDatabasePath,
      options: OpenDatabaseOptions(
        version: AppDatabase.schemaVersion,
        onCreate: AppDatabase.instance.createTables,
      ),
    );

    final dao = PeerDao.forDatabase(db);

    final paired = Peer(
      id: 'peer-4',
      deviceName: 'Paired Device',
      role: 'main',
      ip: '192.168.1.42', // handshake-claimed IP
      port: 45678,
      key: 'shared-key-base64',
      publicKey: 'peer-pub',
      createdAt: DateTime.now(),
    );
    await dao.insert(paired);

    // Beacon finds the peer at a new IP.
    final roamed = paired.copyWith(ip: '192.168.2.77');
    await dao.update(roamed);

    final stored = await dao.getPeer();
    expect(stored, isNotNull);
    expect(
      stored!.ip,
      '192.168.2.77',
      reason:
          'beacon-discovered IP must overwrite the handshake-claimed '
          'IP after the peer roams',
    );

    await db.close();
  });

  test('full reset deletes every peer row', () async {
    final db = await databaseFactory.openDatabase(
      inMemoryDatabasePath,
      options: OpenDatabaseOptions(
        version: AppDatabase.schemaVersion,
        onCreate: AppDatabase.instance.createTables,
      ),
    );
    final dao = PeerDao.forDatabase(db);
    final now = DateTime.now();
    await dao.insert(
      Peer(
        id: 'active',
        deviceName: 'Active',
        role: 'main',
        ip: '192.168.1.2',
        port: 45678,
        key: 'key',
        publicKey: 'public-key',
        createdAt: now,
      ),
    );
    await dao.insert(
      Peer(
        id: 'stale',
        deviceName: 'Stale',
        role: 'main',
        ip: '192.168.1.3',
        port: 45678,
        key: 'key',
        publicKey: 'public-key',
        createdAt: now.subtract(const Duration(minutes: 1)),
      ),
    );
    var credentialsCleared = false;
    final facade = PeerFacade(
      dao: dao,
      clearPeerCredentials: () async => credentialsCleared = true,
    );
    await facade.initialized;

    await facade.reset();

    expect(await dao.getAllPeers(), isEmpty);
    expect(facade.state, isNull);
    expect(credentialsCleared, isTrue);
    facade.dispose();
    await db.close();
  });

  test('deleting active peer unpairs instead of promoting stale row', () async {
    final db = await databaseFactory.openDatabase(
      inMemoryDatabasePath,
      options: OpenDatabaseOptions(
        version: AppDatabase.schemaVersion,
        onCreate: AppDatabase.instance.createTables,
      ),
    );
    final dao = PeerDao.forDatabase(db);
    final active = Peer(
      id: 'active',
      deviceName: 'Active',
      role: 'source',
      ip: '192.168.1.2',
      port: 45678,
      key: 'key',
      publicKey: 'public-key',
      createdAt: DateTime.now(),
    );
    await dao.insert(active);
    await dao.insert(
      active.copyWith(
        id: 'stale',
        deviceName: 'Stale',
        createdAt: active.createdAt.subtract(const Duration(minutes: 1)),
      ),
    );
    var credentialsCleared = false;
    final facade = PeerFacade(
      dao: dao,
      clearPeerCredentials: () async => credentialsCleared = true,
    );
    await facade.initialized;

    await facade.deletePeer(active);

    expect(await dao.getAllPeers(), isEmpty);
    expect(facade.state, isNull);
    expect(credentialsCleared, isTrue);
    facade.dispose();
    await db.close();
  });

  test('deleting a peer quarantines pending and sent Outbox rows', () async {
    final db = await databaseFactory.openDatabase(
      inMemoryDatabasePath,
      options: OpenDatabaseOptions(
        version: AppDatabase.schemaVersion,
        onCreate: AppDatabase.instance.createTables,
      ),
    );
    final dao = PeerDao.forDatabase(db);
    final peer = Peer(
      id: 'peer-to-delete',
      deviceName: 'Paired Device',
      role: 'main',
      ip: '192.168.1.2',
      port: 45678,
      key: 'key',
      publicKey: 'public-key',
      createdAt: DateTime.now(),
    );
    await dao.insert(peer);
    for (final status in ['pending', 'sent', 'completed']) {
      await db.insert('outbox', {
        'message_id': 'message-$status',
        'destination_peer_id': peer.id,
        'type': 'sms',
        'payload': '{}',
        'status': status,
        'attempt_count': 0,
        'created_at': 1,
      });
    }

    await dao.delete(peer.id);

    final rows = await db.query('outbox', orderBy: 'message_id');
    expect(rows[0]['status'], 'completed');
    expect(rows[1]['status'], 'dead_letter');
    expect(rows[2]['status'], 'dead_letter');
    await db.close();
  });

  test(
    'replacing a peer quarantines only the replaced peer outbox rows',
    () async {
      final db = await databaseFactory.openDatabase(
        inMemoryDatabasePath,
        options: OpenDatabaseOptions(
          version: AppDatabase.schemaVersion,
          onCreate: AppDatabase.instance.createTables,
        ),
      );
      final dao = PeerDao.forDatabase(db);
      final oldPeer = Peer(
        id: 'peer-a',
        deviceName: 'Peer A',
        role: 'main',
        ip: '192.168.1.2',
        port: 45678,
        key: 'key-a',
        publicKey: 'public-key-a',
        createdAt: DateTime.now(),
      );
      final replacement = oldPeer.copyWith(
        id: 'peer-b',
        deviceName: 'Peer B',
        publicKey: 'public-key-b',
      );
      await dao.insert(oldPeer);
      for (final status in ['pending', 'sent', 'completed']) {
        await db.insert('outbox', {
          'message_id': 'a-$status',
          'destination_peer_id': oldPeer.id,
          'type': 'sms',
          'payload': '{}',
          'status': status,
          'attempt_count': 0,
          'created_at': 1,
        });
      }

      await dao.replaceId(oldPeer.id, replacement);

      final rows = await db.query('outbox', orderBy: 'message_id');
      expect(
        rows.map((row) => row['destination_peer_id']),
        everyElement('peer-a'),
      );
      expect(rows[0]['status'], 'completed');
      expect(rows[1]['status'], 'dead_letter');
      expect(rows[2]['status'], 'dead_letter');
      expect((await dao.getPeer())!.id, 'peer-b');
      await db.close();
    },
  );
}
