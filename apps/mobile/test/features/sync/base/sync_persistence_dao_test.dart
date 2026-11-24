import 'dart:io';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mirrorline/core/data/database.dart';
import 'package:mirrorline/core/security/local_storage_crypto.dart';
import 'package:mirrorline/features/sync/base/sync_persistence_dao.dart';
import 'package:mirrorline/features/sync/domain/sync_persistence_models.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  late Database db;
  late DateTime now;
  late SyncPersistenceDao dao;
  const user = '11111111-1111-4111-8111-111111111111';
  const device = '22222222-2222-4222-8222-222222222222';
  setUp(() async {
    sqfliteFfiInit();
    db = await databaseFactoryFfi.openDatabase(
      inMemoryDatabasePath,
      options: OpenDatabaseOptions(
        version: AppDatabase.schemaVersion,
        onConfigure: AppDatabase.instance.configureDatabase,
        onCreate: AppDatabase.instance.createTables,
      ),
    );
    now = DateTime.utc(2026, 1, 10);
    dao = SyncPersistenceDao.forDatabase(db, clock: () => now);
    await dao.saveServerIdentity(user, device);
  });
  tearDown(() => db.close());
  Uint8List bytes(int length, [int value = 1]) =>
      Uint8List.fromList(List.filled(length, value));
  RelayEnvelopeRecord envelope({
    required String messageId,
    int digest = 1,
    int protocolVersion = 1,
    String? recipientUserId,
    DateTime? createdAt,
    DateTime? acceptedAt,
    DateTime? expiresAt,
  }) => RelayEnvelopeRecord(
    direction: 'outbox',
    messageId: messageId,
    protocolVersion: protocolVersion,
    messageType: 'event',
    senderUserId: user,
    senderDeviceId: device,
    recipientUserId: recipientUserId ?? user,
    recipientDeviceId: device,
    senderKeyVersion: 1,
    recipientKeyVersion: 1,
    nonce: bytes(12),
    ciphertext: bytes(16),
    signature: bytes(64),
    digest: bytes(32, digest),
    createdAt: createdAt ?? now,
    acceptedAt: acceptedAt,
    expiresAt: expiresAt,
  );

  test(
    'fresh schema has default history policy and server identity isolation',
    () async {
      expect(await dao.historyPolicy(), LocalHistoryRetention.days30);
      await expectLater(
        dao.updateMailboxCursor(user, 'bad', 'a', 1),
        throwsArgumentError,
      );
    },
  );
  test(
    'upgrade from version seven adds persistence tables idempotently',
    () async {
      await db.insert('peer', {
        'id': 'legacy-peer',
        'role': 'source',
        'ip': '0.0.0.0',
        'port': 1,
        'key': 'legacy',
        'created_at': 1,
      });
      await db.execute('DROP TABLE local_history_policy');
      await AppDatabase.instance.upgradeTables(db, 7, 8);
      await AppDatabase.instance.upgradeTables(db, 7, 8);
      expect(await dao.historyPolicy(), LocalHistoryRetention.days30);
      expect(
        (await db.query(
          'peer',
          where: 'id = ?',
          whereArgs: ['legacy-peer'],
        )).single['key'],
        'legacy',
      );
    },
  );
  test('key versions are monotonic and replace active key', () async {
    await dao.addPublicKeyVersion(
      userId: user,
      deviceId: device,
      version: 1,
      signingPublicKey: bytes(32),
      encryptionPublicKey: bytes(32, 2),
      fingerprint: bytes(32, 3),
      status: DeviceKeyStatus.active,
    );
    await dao.addPublicKeyVersion(
      userId: user,
      deviceId: device,
      version: 2,
      signingPublicKey: bytes(32, 4),
      encryptionPublicKey: bytes(32, 5),
      fingerprint: bytes(32, 6),
      status: DeviceKeyStatus.active,
    );
    expect(
      (await db.query(
        'device_key_version',
        where: "status = 'active'",
      )).single['version'],
      2,
    );
    await expectLater(
      dao.addPublicKeyVersion(
        userId: user,
        deviceId: device,
        version: 2,
        signingPublicKey: bytes(32),
        encryptionPublicKey: bytes(32),
        fingerprint: bytes(32),
        status: DeviceKeyStatus.pending,
      ),
      throwsStateError,
    );
  });
  test(
    'cursor and replay enforce monotonic and idempotent boundaries',
    () async {
      await dao.updateMailboxCursor(user, device, 'opaque-b', 1);
      await dao.updateMailboxCursor(user, device, 'opaque-b', 1);
      await expectLater(
        dao.updateMailboxCursor(user, device, 'opaque-other', 1),
        throwsStateError,
      );
      await expectLater(
        dao.updateMailboxCursor(user, device, 'opaque-a', 0),
        throwsStateError,
      );
      await expectLater(
        dao.updateMailboxCursor(
          'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
          device,
          'opaque-c',
          2,
        ),
        throwsA(isA<DatabaseException>()),
      );
      await dao.updateMailboxCursor(user, device, 'opaque-c', 2);
      expect(
        await dao.recordReplay(
          user,
          device,
          '55555555-5555-4555-8555-555555555555',
          bytes(32),
        ),
        ReplayDisposition.accepted,
      );
      expect(
        await dao.recordReplay(
          user,
          device,
          '55555555-5555-4555-8555-555555555555',
          bytes(32),
        ),
        ReplayDisposition.idempotent,
      );
      expect(
        await dao.recordReplay(
          user,
          device,
          '55555555-5555-4555-8555-555555555555',
          bytes(32, 2),
        ),
        ReplayDisposition.conflict,
      );
      now = now.add(const Duration(days: 8));
      expect(await dao.cleanupReplay(), 1);
      now = now.add(const Duration(milliseconds: 1));
      expect(await dao.cleanupReplay(), 0);
    },
  );
  test('stores ciphertext only and rejects malformed envelope', () async {
    await dao.addPublicKeyVersion(
      userId: user,
      deviceId: device,
      version: 1,
      signingPublicKey: bytes(32),
      encryptionPublicKey: bytes(32, 2),
      fingerprint: bytes(32, 3),
      status: DeviceKeyStatus.active,
    );
    final record = RelayEnvelopeRecord(
      direction: 'outbox',
      messageId: '33333333-3333-4333-8333-333333333333',
      protocolVersion: 1,
      messageType: 'event',
      senderUserId: user,
      senderDeviceId: device,
      recipientUserId: user,
      recipientDeviceId: device,
      senderKeyVersion: 1,
      recipientKeyVersion: 1,
      nonce: bytes(12),
      ciphertext: bytes(16),
      signature: bytes(64),
      digest: bytes(32),
      createdAt: now,
    );
    expect(await dao.storeEnvelope(record), ReplayDisposition.accepted);
    expect(await dao.storeEnvelope(record), ReplayDisposition.idempotent);
    expect((await db.query('relay_envelope')).single['ciphertext'], bytes(16));
    await expectLater(
      dao.storeEnvelope(
        RelayEnvelopeRecord(
          direction: 'inbox',
          messageId: '44444444-4444-4444-8444-444444444444',
          protocolVersion: 1,
          messageType: 'event',
          senderUserId: user,
          senderDeviceId: device,
          recipientUserId: user,
          recipientDeviceId: device,
          senderKeyVersion: 1,
          recipientKeyVersion: 1,
          nonce: bytes(1),
          ciphertext: bytes(16),
          signature: bytes(64),
          digest: bytes(32),
          createdAt: now,
        ),
      ),
      throwsArgumentError,
    );
    await expectLater(
      dao.storeEnvelope(
        RelayEnvelopeRecord(
          direction: 'outbox',
          messageId: '45454545-4545-4454-8454-454545454545',
          protocolVersion: 1,
          messageType: 'event',
          senderUserId: user,
          senderDeviceId: device,
          recipientUserId: user,
          recipientDeviceId: device,
          senderKeyVersion: 1,
          recipientKeyVersion: 2,
          nonce: bytes(12),
          ciphertext: bytes(16),
          signature: bytes(64),
          digest: bytes(32),
          createdAt: now,
        ),
      ),
      throwsA(isA<DatabaseException>()),
    );
  });
  test(
    'envelope protocol invariants are enforced by DAO and database',
    () async {
      await dao.addPublicKeyVersion(
        userId: user,
        deviceId: device,
        version: 1,
        signingPublicKey: bytes(32),
        encryptionPublicKey: bytes(32, 2),
        fingerprint: bytes(32, 3),
        status: DeviceKeyStatus.active,
      );
      await expectLater(
        dao.storeEnvelope(
          envelope(
            messageId: '46464646-4646-4464-8464-464646464646',
            protocolVersion: 2,
          ),
        ),
        throwsArgumentError,
      );
      await expectLater(
        dao.storeEnvelope(
          envelope(
            messageId: '47474747-4747-4474-8474-474747474747',
            acceptedAt: now,
          ),
        ),
        throwsArgumentError,
      );
      await expectLater(
        dao.storeEnvelope(
          envelope(
            messageId: '48484848-4848-4484-8484-484848484848',
            expiresAt: now.add(const Duration(days: 7)),
          ),
        ),
        throwsArgumentError,
      );
      await expectLater(
        dao.storeEnvelope(
          envelope(
            messageId: '49494949-4949-4494-8494-494949494949',
            acceptedAt: now,
            expiresAt: now.add(const Duration(days: 6)),
          ),
        ),
        throwsArgumentError,
      );
      await expectLater(
        dao.storeEnvelope(
          envelope(
            messageId: '50505050-5050-4050-8050-505050505050',
            recipientUserId: 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
          ),
        ),
        throwsArgumentError,
      );

      Map<String, Object?> row(String messageId) => {
        'direction': 'outbox',
        'message_id': messageId,
        'protocol_version': 1,
        'message_type': 'event',
        'sender_user_id': user,
        'sender_device_id': device,
        'recipient_user_id': user,
        'recipient_device_id': device,
        'sender_key_version': 1,
        'recipient_key_version': 1,
        'nonce': bytes(12),
        'ciphertext': bytes(16),
        'signature': bytes(64),
        'digest': bytes(32),
        'accepted_at': null,
        'expires_at': null,
        'replay_recorded_at': now.millisecondsSinceEpoch,
        'created_at': now.millisecondsSinceEpoch,
      };
      final badProtocol = row('51515151-5151-4151-8151-515151515151');
      badProtocol['protocol_version'] = 2;
      await expectLater(
        db.insert('relay_envelope', badProtocol),
        throwsA(isA<DatabaseException>()),
      );
      final unpairedTimes = row('52525252-5252-4252-8252-525252525252');
      unpairedTimes['accepted_at'] = now.millisecondsSinceEpoch;
      await expectLater(
        db.insert('relay_envelope', unpairedTimes),
        throwsA(isA<DatabaseException>()),
      );
    },
  );
  test('pending envelopes omit ciphertext after expiry', () async {
    await dao.addPublicKeyVersion(
      userId: user,
      deviceId: device,
      version: 1,
      signingPublicKey: bytes(32),
      encryptionPublicKey: bytes(32, 2),
      fingerprint: bytes(32, 3),
      status: DeviceKeyStatus.active,
    );
    await dao.storeEnvelope(
      envelope(
        messageId: '53535353-5353-4353-8353-535353535353',
        acceptedAt: now,
        expiresAt: now.add(const Duration(days: 7)),
      ),
    );
    expect((await dao.pendingEnvelopes('outbox')).single.messageType, 'event');
    now = now.add(const Duration(days: 7));
    expect(await dao.pendingEnvelopes('outbox'), isEmpty);
  });
  test(
    'envelope instants round-trip as UTC and expire at the same instant',
    () async {
      await dao.addPublicKeyVersion(
        userId: user,
        deviceId: device,
        version: 1,
        signingPublicKey: bytes(32),
        encryptionPublicKey: bytes(32, 2),
        fingerprint: bytes(32, 3),
        status: DeviceKeyStatus.active,
      );
      final created = DateTime.parse('2026-01-10T05:30:00+05:30');
      final accepted = DateTime.parse('2026-01-11T05:30:00+05:30');
      final expires = DateTime.parse('2026-01-18T05:30:00+05:30');
      now = accepted;
      await dao.storeEnvelope(
        envelope(
          messageId: '54545454-5454-4454-8454-545454545454',
          createdAt: created,
          acceptedAt: accepted,
          expiresAt: expires,
        ),
      );
      final stored = (await dao.pendingEnvelopes('outbox')).single;
      expect(stored.createdAt, created.toUtc());
      expect(stored.acceptedAt, accepted.toUtc());
      expect(stored.expiresAt, expires.toUtc());
      expect(stored.createdAt.isUtc, isTrue);
      expect(stored.acceptedAt!.isUtc, isTrue);
      expect(stored.expiresAt!.isUtc, isTrue);
      now = expires;
      expect(await dao.pendingEnvelopes('outbox'), isEmpty);
      expect(await dao.expireEnvelopes(), 1);
    },
  );
  test(
    'requires canonical lowercase UUIDv4 identities and message ids',
    () async {
      await expectLater(
        dao.saveServerIdentity('11111111-1111-1111-8111-111111111111', device),
        throwsArgumentError,
      );
      await expectLater(
        dao.saveServerIdentity('AAAAAAAA-AAAA-4AAA-8AAA-AAAAAAAAAAAA', device),
        throwsArgumentError,
      );
      await expectLater(
        dao.recordReplay(
          user,
          device,
          '55555555-5555-4555-8555-55555555555A',
          bytes(32),
        ),
        throwsArgumentError,
      );
    },
  );
  test(
    'acknowledgement and expiry purge ciphertext but retain replay tombstones',
    () async {
      await dao.addPublicKeyVersion(
        userId: user,
        deviceId: device,
        version: 1,
        signingPublicKey: bytes(32),
        encryptionPublicKey: bytes(32, 2),
        fingerprint: bytes(32, 3),
        status: DeviceKeyStatus.active,
      );
      const acknowledgedId = '78787878-7878-4787-8787-787878787878';
      final acknowledged = envelope(messageId: acknowledgedId);
      expect(await dao.storeEnvelope(acknowledged), ReplayDisposition.accepted);
      final acknowledgedAt = now;
      now = now.add(const Duration(days: 6));
      expect(
        await dao.acknowledgeEnvelope(user, device, acknowledgedId),
        isTrue,
      );
      expect(
        await dao.acknowledgeEnvelope(
          user,
          device,
          'abababab-abab-4aba-8aba-abababababab',
        ),
        isFalse,
      );
      expect(
        await dao.acknowledgeEnvelope(user, device, acknowledgedId),
        isTrue,
      );
      expect(await db.query('relay_envelope'), isEmpty);
      expect(
        await dao.storeEnvelope(acknowledged),
        ReplayDisposition.idempotent,
      );
      expect(
        await dao.storeEnvelope(envelope(messageId: acknowledgedId, digest: 2)),
        ReplayDisposition.conflict,
      );
      now = acknowledgedAt.add(const Duration(days: 8));
      expect(await dao.cleanupReplay(), 1);
      now = now.add(const Duration(milliseconds: 1));
      expect(await dao.cleanupReplay(), 0);

      const expiringId = '89898989-8989-4989-8989-898989898989';
      final expiringRecordedAt = now;
      final expiring = envelope(
        messageId: expiringId,
        acceptedAt: now,
        expiresAt: now.add(const Duration(days: 7)),
      );
      expect(await dao.storeEnvelope(expiring), ReplayDisposition.accepted);
      now = now.add(const Duration(days: 7));
      expect(await dao.expireEnvelopes(), 1);
      now = now.add(const Duration(milliseconds: 1));
      expect(await dao.expireEnvelopes(), 0);
      expect(await db.query('relay_envelope'), isEmpty);
      expect(await dao.acknowledgeEnvelope(user, device, expiringId), isTrue);
      expect(await dao.storeEnvelope(expiring), ReplayDisposition.idempotent);
      expect(
        await dao.storeEnvelope(
          envelope(
            messageId: expiringId,
            digest: 2,
            acceptedAt: expiring.acceptedAt,
            expiresAt: expiring.expiresAt,
          ),
        ),
        ReplayDisposition.conflict,
      );
      now = expiringRecordedAt.add(const Duration(days: 8));
      expect(await dao.cleanupReplay(), 1);
      now = now.add(const Duration(milliseconds: 1));
      expect(await dao.cleanupReplay(), 0);

      const conflictingId = '90909090-9090-4090-8090-909090909090';
      final conflicting = envelope(
        messageId: conflictingId,
        acceptedAt: now,
        expiresAt: now.add(const Duration(days: 7)),
      );
      expect(await dao.storeEnvelope(conflicting), ReplayDisposition.accepted);
      await db.insert('replay_tombstone', {
        'sender_user_id': user,
        'sender_device_id': device,
        'message_id': conflictingId,
        'digest': bytes(32, 2),
        'accepted_at': now.millisecondsSinceEpoch,
      });
      now = now.add(const Duration(days: 7));
      await expectLater(dao.expireEnvelopes(), throwsStateError);
      final retained = await db.query(
        'relay_envelope',
        where: 'message_id = ?',
        whereArgs: [conflictingId],
      );
      expect(retained.single['ciphertext'], bytes(16));
    },
  );
  test('history policies and cleanup keep replay records separate', () async {
    for (final policy in LocalHistoryRetention.values) {
      await dao.setHistoryPolicy(policy);
      expect(await dao.historyPolicy(), policy);
    }
    await dao.setHistoryPolicy(LocalHistoryRetention.days7);
    await dao.addEncryptedLocalHistory(
      'v1:opaque',
      occurredAt: now.subtract(const Duration(days: 7)),
    );
    await expectLater(
      dao.addEncryptedLocalHistory('plaintext'),
      throwsArgumentError,
    );
    await dao.recordReplay(
      user,
      device,
      '66666666-6666-4666-8666-666666666666',
      bytes(32),
    );
    expect(await dao.cleanupHistory(), 1);
    now = now.add(const Duration(milliseconds: 1));
    expect(await dao.cleanupHistory(), 0);
    expect((await db.query('replay_tombstone')).length, 1);
  });
  test(
    'concurrent replay admission is idempotent and rollback leaves no row',
    () async {
      final results = await Future.wait([
        dao.recordReplay(
          user,
          device,
          '77777777-7777-4777-8777-777777777777',
          bytes(32),
        ),
        dao.recordReplay(
          user,
          device,
          '77777777-7777-4777-8777-777777777777',
          bytes(32),
        ),
      ]);
      expect(
        results,
        containsAll(<ReplayDisposition>[
          ReplayDisposition.accepted,
          ReplayDisposition.idempotent,
        ]),
      );
      await expectLater(
        dao.addPublicKeyVersion(
          userId: user,
          deviceId: device,
          version: 1,
          signingPublicKey: bytes(1),
          encryptionPublicKey: bytes(32),
          fingerprint: bytes(32),
          status: DeviceKeyStatus.active,
        ),
        throwsArgumentError,
      );
      expect((await db.query('device_key_version')).isEmpty, isTrue);
    },
  );
  test('live envelopes are replay admission history', () async {
    await dao.addPublicKeyVersion(
      userId: user,
      deviceId: device,
      version: 1,
      signingPublicKey: bytes(32),
      encryptionPublicKey: bytes(32, 2),
      fingerprint: bytes(32, 3),
      status: DeviceKeyStatus.active,
    );
    const messageId = 'eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee';
    expect(
      await dao.storeEnvelope(envelope(messageId: messageId)),
      ReplayDisposition.accepted,
    );
    expect(
      await dao.recordReplay(user, device, messageId, bytes(32)),
      ReplayDisposition.idempotent,
    );
    expect(
      await dao.recordReplay(user, device, messageId, bytes(32, 2)),
      ReplayDisposition.conflict,
    );
    expect(await db.query('replay_tombstone'), isEmpty);
  });
  test(
    'file-backed independent handles reconcile replay and envelope races',
    () async {
      final testDatabaseRoot = Directory('build/test-databases');
      await testDatabaseRoot.create(recursive: true);
      final directory = await testDatabaseRoot.createTemp('sync-race-');
      final path = '${directory.path}/sync.db';
      final first = await databaseFactoryFfi.openDatabase(
        path,
        options: OpenDatabaseOptions(
          version: AppDatabase.schemaVersion,
          singleInstance: false,
          onConfigure: AppDatabase.instance.configureDatabase,
          onCreate: AppDatabase.instance.createTables,
        ),
      );
      final second = await databaseFactoryFfi.openDatabase(
        path,
        options: OpenDatabaseOptions(
          version: AppDatabase.schemaVersion,
          singleInstance: false,
          onConfigure: AppDatabase.instance.configureDatabase,
        ),
      );
      addTearDown(() async {
        await first.close();
        await second.close();
        await directory.delete(recursive: true);
      });
      final firstDao = SyncPersistenceDao.forDatabase(first, clock: () => now);
      final secondDao = SyncPersistenceDao.forDatabase(
        second,
        clock: () => now,
      );
      await firstDao.saveServerIdentity(user, device);
      await firstDao.addPublicKeyVersion(
        userId: user,
        deviceId: device,
        version: 1,
        signingPublicKey: bytes(32),
        encryptionPublicKey: bytes(32, 2),
        fingerprint: bytes(32, 3),
        status: DeviceKeyStatus.active,
      );

      const replaySameId = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';
      final replaySame = await Future.wait([
        firstDao.recordReplay(user, device, replaySameId, bytes(32)),
        secondDao.recordReplay(user, device, replaySameId, bytes(32)),
      ]);
      expect(
        replaySame,
        containsAll([ReplayDisposition.accepted, ReplayDisposition.idempotent]),
      );
      const replayDifferentId = 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb';
      final replayDifferent = await Future.wait([
        firstDao.recordReplay(user, device, replayDifferentId, bytes(32)),
        secondDao.recordReplay(user, device, replayDifferentId, bytes(32, 2)),
      ]);
      expect(
        replayDifferent,
        containsAll([ReplayDisposition.accepted, ReplayDisposition.conflict]),
      );

      RelayEnvelopeRecord raceEnvelope(String messageId, int digest) =>
          RelayEnvelopeRecord(
            direction: 'outbox',
            messageId: messageId,
            protocolVersion: 1,
            messageType: 'event',
            senderUserId: user,
            senderDeviceId: device,
            recipientUserId: user,
            recipientDeviceId: device,
            senderKeyVersion: 1,
            recipientKeyVersion: 1,
            nonce: bytes(12),
            ciphertext: bytes(16),
            signature: bytes(64),
            digest: bytes(32, digest),
            createdAt: now,
          );
      const envelopeSameId = 'cccccccc-cccc-4ccc-8ccc-cccccccccccc';
      final envelopeSame = await Future.wait([
        firstDao.storeEnvelope(raceEnvelope(envelopeSameId, 1)),
        secondDao.storeEnvelope(raceEnvelope(envelopeSameId, 1)),
      ]);
      expect(
        envelopeSame,
        containsAll([ReplayDisposition.accepted, ReplayDisposition.idempotent]),
      );
      const envelopeDifferentId = 'dddddddd-dddd-4ddd-8ddd-dddddddddddd';
      final envelopeDifferent = await Future.wait([
        firstDao.storeEnvelope(raceEnvelope(envelopeDifferentId, 1)),
        secondDao.storeEnvelope(raceEnvelope(envelopeDifferentId, 2)),
      ]);
      expect(
        envelopeDifferent,
        containsAll([ReplayDisposition.accepted, ReplayDisposition.conflict]),
      );

      const envelopeReplaySameId = 'eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee';
      final envelopeReplaySame = await Future.wait([
        firstDao.storeEnvelope(raceEnvelope(envelopeReplaySameId, 1)),
        secondDao.recordReplay(user, device, envelopeReplaySameId, bytes(32)),
      ]);
      expect(
        envelopeReplaySame,
        containsAll([ReplayDisposition.accepted, ReplayDisposition.idempotent]),
      );
      final sameEnvelopeRows = await first.query(
        'relay_envelope',
        where: 'message_id = ?',
        whereArgs: [envelopeReplaySameId],
      );
      final sameTombstoneRows = await first.query(
        'replay_tombstone',
        where: 'message_id = ?',
        whereArgs: [envelopeReplaySameId],
      );
      expect(sameEnvelopeRows.length + sameTombstoneRows.length, 1);

      const envelopeReplayDifferentId = 'ffffffff-ffff-4fff-8fff-ffffffffffff';
      final envelopeReplayDifferent = await Future.wait([
        firstDao.storeEnvelope(raceEnvelope(envelopeReplayDifferentId, 1)),
        secondDao.recordReplay(
          user,
          device,
          envelopeReplayDifferentId,
          bytes(32, 2),
        ),
      ]);
      expect(
        envelopeReplayDifferent,
        containsAll([ReplayDisposition.accepted, ReplayDisposition.conflict]),
      );
      final differentEnvelopeRows = await first.query(
        'relay_envelope',
        where: 'message_id = ?',
        whereArgs: [envelopeReplayDifferentId],
      );
      final differentTombstoneRows = await first.query(
        'replay_tombstone',
        where: 'message_id = ?',
        whereArgs: [envelopeReplayDifferentId],
      );
      expect(differentEnvelopeRows.length + differentTombstoneRows.length, 1);
    },
  );
  test('history is ciphertext-only and malformed values fail closed', () async {
    final key = SecretKey(List<int>.filled(32, 9));
    final secured = SyncPersistenceDao.forDatabase(
      db,
      keyLoader: () async => key,
      encrypt: LocalStorageCrypto.encrypt,
      decrypt: LocalStorageCrypto.decrypt,
    );
    await secured.addLocalHistory('private event');
    final stored =
        (await db.query('local_history_entry')).single['encrypted_payload']
            as String;
    expect(stored, startsWith(LocalStorageCrypto.currentPrefix));
    expect(stored, isNot(contains('private event')));
    expect(await secured.readLocalHistory(), ['private event']);
    await secured.addEncryptedLocalHistory(
      '${LocalStorageCrypto.currentPrefix}bad',
    );
    await expectLater(secured.readLocalHistory(), throwsStateError);
  });

  test('full reset restores the default history retention policy', () async {
    await dao.setHistoryPolicy(LocalHistoryRetention.days7);
    await dao.addEncryptedLocalHistory('v1:opaque');
    await AppDatabase.instance.resetDatabase(db);
    expect(await dao.historyPolicy(), LocalHistoryRetention.days30);
    expect(await dao.encryptedLocalHistory(), isEmpty);
  });

  test('full reset rolls back all data when one delete fails', () async {
    await dao.setHistoryPolicy(LocalHistoryRetention.days7);
    await db.insert('peer', {
      'id': 'reset-peer',
      'device_name': '',
      'role': 'source',
      'ip': '127.0.0.1',
      'port': 1,
      'key': 'key',
      'public_key': '',
      'created_at': now.millisecondsSinceEpoch,
    });
    await db.insert('call_event', {
      'id': 'reset-call',
      'direction': 'incoming',
      'number': '1',
      'contact_name': '',
      'timestamp': now.millisecondsSinceEpoch,
      'encrypted': '',
      'status': 'received',
      'created_at': now.millisecondsSinceEpoch,
    });
    await db.execute('''
      CREATE TRIGGER abort_call_event_reset
      BEFORE DELETE ON call_event
      BEGIN
        SELECT RAISE(ABORT, 'reset failure');
      END
    ''');

    await expectLater(
      AppDatabase.instance.resetDatabase(db),
      throwsA(isA<DatabaseException>()),
    );
    expect(await dao.historyPolicy(), LocalHistoryRetention.days7);
    expect(await db.query('peer'), hasLength(1));
    expect(await db.query('call_event'), hasLength(1));
  });
}
