import 'dart:async';

import 'package:cryptography/cryptography.dart';
import 'package:flutter/foundation.dart';
import 'package:mirrorline/core/data/database.dart';
import 'package:mirrorline/core/security/key_store.dart';
import 'package:mirrorline/core/security/local_storage_crypto.dart';
import 'package:mirrorline/features/sync/domain/sync_persistence_models.dart';
import 'package:sqflite/sqflite.dart';

class SyncPersistenceDao {
  SyncPersistenceDao({
    DateTime Function()? clock,
    Future<SecretKey> Function()? keyLoader,
    Future<String> Function(SecretKey, String)? encrypt,
    Future<String?> Function(SecretKey, String)? decrypt,
  }) : _testDb = null,
       _clock = clock ?? DateTime.now,
       _keyLoader = keyLoader ?? KeyStore.ensureLocalDatabaseKey,
       _encrypt = encrypt ?? LocalStorageCrypto.encrypt,
       _decrypt = decrypt ?? LocalStorageCrypto.decrypt;
  @visibleForTesting
  SyncPersistenceDao.forDatabase(
    this._testDb, {
    DateTime Function()? clock,
    Future<SecretKey> Function()? keyLoader,
    Future<String> Function(SecretKey, String)? encrypt,
    Future<String?> Function(SecretKey, String)? decrypt,
  }) : _clock = clock ?? DateTime.now,
       _keyLoader = keyLoader ?? KeyStore.ensureLocalDatabaseKey,
       _encrypt = encrypt ?? LocalStorageCrypto.encrypt,
       _decrypt = decrypt ?? LocalStorageCrypto.decrypt;
  final Database? _testDb;
  final DateTime Function() _clock;
  final Future<SecretKey> Function() _keyLoader;
  final Future<String> Function(SecretKey, String) _encrypt;
  final Future<String?> Function(SecretKey, String) _decrypt;
  Future<Database> get _db async =>
      _testDb ?? await AppDatabase.instance.database;

  static final _uuid = RegExp(
    r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
  );
  static Future<void> _admissionTail = Future.value();
  void _identity(String userId, String deviceId) {
    if (!_uuid.hasMatch(userId) || !_uuid.hasMatch(deviceId)) {
      throw ArgumentError('Server identity must be UUIDs.');
    }
  }

  void _bytes(Uint8List value, int length, String field) {
    if (value.length != length) {
      throw ArgumentError('$field has invalid length.');
    }
  }

  bool _isBusy(DatabaseException error) {
    final message = error.toString().toLowerCase();
    return message.contains('database is locked') ||
        message.contains('database is busy') ||
        message.contains('sqlite_busy');
  }

  Future<T> _admit<T>(Future<T> Function() operation) async {
    final predecessor = _admissionTail;
    final release = Completer<void>();
    _admissionTail = release.future;
    await predecessor;
    try {
      for (var attempt = 0; attempt < 5; attempt++) {
        try {
          return await operation();
        } on DatabaseException catch (error) {
          if (!_isBusy(error) || attempt == 4) rethrow;
          await Future<void>.delayed(
            Duration(milliseconds: 10 * (attempt + 1)),
          );
        }
      }
      throw StateError('Unreachable admission retry state.');
    } finally {
      release.complete();
    }
  }

  Future<void> saveServerIdentity(String userId, String deviceId) async {
    _identity(userId, deviceId);
    final db = await _db;
    await db.insert('server_identity', {
      'user_id': userId,
      'device_id': deviceId,
      'created_at': _clock().millisecondsSinceEpoch,
    }, conflictAlgorithm: ConflictAlgorithm.ignore);
  }

  Future<void> addPublicKeyVersion({
    required String userId,
    required String deviceId,
    required int version,
    required Uint8List signingPublicKey,
    required Uint8List encryptionPublicKey,
    required Uint8List fingerprint,
    required DeviceKeyStatus status,
  }) async {
    _identity(userId, deviceId);
    _bytes(signingPublicKey, 32, 'signing public key');
    _bytes(encryptionPublicKey, 32, 'encryption public key');
    _bytes(fingerprint, 32, 'fingerprint');
    if (version <= 0) {
      throw ArgumentError.value(version, 'version');
    }
    final db = await _db;
    await db.transaction((txn) async {
      final latest = await txn.rawQuery(
        'SELECT MAX(version) AS version FROM device_key_version WHERE user_id = ? AND device_id = ?',
        [userId, deviceId],
      );
      final max = latest.single['version'] as int?;
      if (max != null && version <= max) {
        throw StateError('Key versions must increase.');
      }
      if (status == DeviceKeyStatus.active) {
        await txn.update(
          'device_key_version',
          {
            'status': 'retiring',
            'retiring_at': _clock().millisecondsSinceEpoch,
          },
          where: 'user_id = ? AND device_id = ? AND status = ?',
          whereArgs: [userId, deviceId, 'active'],
        );
      }
      await txn.insert('device_key_version', {
        'user_id': userId,
        'device_id': deviceId,
        'version': version,
        'signing_public_key': signingPublicKey,
        'encryption_public_key': encryptionPublicKey,
        'fingerprint': fingerprint,
        'status': status.name,
        'created_at': _clock().millisecondsSinceEpoch,
        'activated_at': status == DeviceKeyStatus.active
            ? _clock().millisecondsSinceEpoch
            : null,
      });
    });
  }

  Future<void> updateMailboxCursor(
    String userId,
    String deviceId,
    String cursor,
    int sequence,
  ) async {
    _identity(userId, deviceId);
    if (cursor.isEmpty || cursor.length > 512 || sequence < 0) {
      throw ArgumentError('Invalid mailbox cursor.');
    }
    final db = await _db;
    final now = _clock().millisecondsSinceEpoch;
    await db.transaction((txn) async {
      final existing = await txn.query(
        'mailbox_cursor',
        where: 'user_id = ? AND device_id = ?',
        whereArgs: [userId, deviceId],
      );
      if (existing.isNotEmpty) {
        final oldSequence = existing.single['sequence'] as int;
        final oldCursor = existing.single['cursor'] as String;
        if (sequence < oldSequence ||
            (sequence == oldSequence && cursor != oldCursor)) {
          throw StateError('Mailbox cursor conflict.');
        }
        if (sequence == oldSequence) return;
      }
      if (existing.isNotEmpty) {
        await txn.update(
          'mailbox_cursor',
          {'cursor': cursor, 'sequence': sequence, 'updated_at': now},
          where: 'user_id = ? AND device_id = ?',
          whereArgs: [userId, deviceId],
        );
      } else {
        await txn.insert('mailbox_cursor', {
          'user_id': userId,
          'device_id': deviceId,
          'cursor': cursor,
          'sequence': sequence,
          'updated_at': now,
        });
      }
    });
  }

  Future<ReplayDisposition> storeEnvelope(RelayEnvelopeRecord value) async {
    _identity(value.senderUserId, value.senderDeviceId);
    _identity(value.recipientUserId, value.recipientDeviceId);
    if (value.direction != 'inbox' && value.direction != 'outbox') {
      throw ArgumentError('Invalid envelope direction.');
    }
    if (value.messageId.isEmpty ||
        value.messageId.length > 128 ||
        value.messageType.isEmpty ||
        value.messageType.length > 64 ||
        value.ciphertext.length > 1024 * 1024) {
      throw ArgumentError('Invalid envelope metadata.');
    }
    _bytes(value.nonce, 12, 'nonce');
    _bytes(value.signature, 64, 'signature');
    _bytes(value.digest, 32, 'digest');
    if (!_uuid.hasMatch(value.messageId)) {
      throw ArgumentError('Envelope message id must be a UUID.');
    }
    if (value.protocolVersion != 1 ||
        value.senderKeyVersion <= 0 ||
        value.recipientKeyVersion <= 0) {
      throw ArgumentError('Invalid envelope version.');
    }
    if ((value.acceptedAt == null) != (value.expiresAt == null) ||
        (value.acceptedAt != null &&
            value.expiresAt!.difference(value.acceptedAt!) !=
                const Duration(days: 7))) {
      throw ArgumentError('Invalid server envelope expiry.');
    }
    if (value.senderUserId != value.recipientUserId) {
      throw ArgumentError('Envelope identities must belong to one user.');
    }
    if (value.ciphertext.length < 16) {
      throw ArgumentError('Invalid ciphertext.');
    }
    final db = await _db;
    return _admit(
      () => db.transaction((txn) async {
        final tombstone = await txn.query(
          'replay_tombstone',
          columns: ['digest'],
          where:
              'sender_user_id = ? AND sender_device_id = ? AND message_id = ?',
          whereArgs: [
            value.senderUserId,
            value.senderDeviceId,
            value.messageId,
          ],
        );
        if (tombstone.isNotEmpty) {
          return listEquals(
                tombstone.single['digest'] as Uint8List,
                value.digest,
              )
              ? ReplayDisposition.idempotent
              : ReplayDisposition.conflict;
        }
        final inserted = await txn.insert('relay_envelope', {
          'direction': value.direction,
          'message_id': value.messageId,
          'protocol_version': value.protocolVersion,
          'message_type': value.messageType,
          'sender_user_id': value.senderUserId,
          'sender_device_id': value.senderDeviceId,
          'recipient_user_id': value.recipientUserId,
          'recipient_device_id': value.recipientDeviceId,
          'sender_key_version': value.senderKeyVersion,
          'recipient_key_version': value.recipientKeyVersion,
          'nonce': value.nonce,
          'ciphertext': value.ciphertext,
          'signature': value.signature,
          'digest': value.digest,
          'accepted_at': value.acceptedAt?.millisecondsSinceEpoch,
          'expires_at': value.expiresAt?.millisecondsSinceEpoch,
          'replay_recorded_at': _clock().millisecondsSinceEpoch,
          'created_at': value.createdAt.millisecondsSinceEpoch,
        }, conflictAlgorithm: ConflictAlgorithm.ignore);
        if (inserted != 0) {
          final replay = await txn.query(
            'replay_tombstone',
            columns: ['digest'],
            where:
                'sender_user_id = ? AND sender_device_id = ? AND message_id = ?',
            whereArgs: [
              value.senderUserId,
              value.senderDeviceId,
              value.messageId,
            ],
          );
          if (replay.isEmpty) return ReplayDisposition.accepted;
          await txn.delete(
            'relay_envelope',
            where:
                'sender_user_id = ? AND sender_device_id = ? AND message_id = ?',
            whereArgs: [
              value.senderUserId,
              value.senderDeviceId,
              value.messageId,
            ],
          );
          return listEquals(replay.single['digest'] as Uint8List, value.digest)
              ? ReplayDisposition.idempotent
              : ReplayDisposition.conflict;
        }
        final racedTombstone = await txn.query(
          'replay_tombstone',
          columns: ['digest'],
          where:
              'sender_user_id = ? AND sender_device_id = ? AND message_id = ?',
          whereArgs: [
            value.senderUserId,
            value.senderDeviceId,
            value.messageId,
          ],
        );
        final raced = racedTombstone.isNotEmpty
            ? racedTombstone
            : await txn.query(
                'relay_envelope',
                columns: ['digest'],
                where:
                    'sender_user_id = ? AND sender_device_id = ? AND message_id = ?',
                whereArgs: [
                  value.senderUserId,
                  value.senderDeviceId,
                  value.messageId,
                ],
              );
        if (raced.isEmpty) {
          throw StateError('Envelope admission did not persist a result.');
        }
        if (racedTombstone.isNotEmpty) {
          await txn.delete(
            'relay_envelope',
            where:
                'sender_user_id = ? AND sender_device_id = ? AND message_id = ?',
            whereArgs: [
              value.senderUserId,
              value.senderDeviceId,
              value.messageId,
            ],
          );
        }
        return listEquals(raced.single['digest'] as Uint8List, value.digest)
            ? ReplayDisposition.idempotent
            : ReplayDisposition.conflict;
      }),
    );
  }

  Future<ReplayDisposition> recordReplay(
    String userId,
    String deviceId,
    String messageId,
    Uint8List digest,
  ) async {
    _identity(userId, deviceId);
    _bytes(digest, 32, 'digest');
    if (!_uuid.hasMatch(messageId)) {
      throw ArgumentError('Invalid message id.');
    }
    final db = await _db;
    return _admit(
      () => db.transaction((txn) async {
        final existing = await txn.query(
          'replay_tombstone',
          where:
              'sender_user_id = ? AND sender_device_id = ? AND message_id = ?',
          whereArgs: [userId, deviceId, messageId],
        );
        if (existing.isNotEmpty) {
          return listEquals(existing.single['digest'] as Uint8List, digest)
              ? ReplayDisposition.idempotent
              : ReplayDisposition.conflict;
        }
        final envelope = await txn.query(
          'relay_envelope',
          columns: ['digest'],
          where:
              'sender_user_id = ? AND sender_device_id = ? AND message_id = ?',
          whereArgs: [userId, deviceId, messageId],
        );
        if (envelope.isNotEmpty) {
          return listEquals(envelope.single['digest'] as Uint8List, digest)
              ? ReplayDisposition.idempotent
              : ReplayDisposition.conflict;
        }
        final inserted = await txn.insert('replay_tombstone', {
          'sender_user_id': userId,
          'sender_device_id': deviceId,
          'message_id': messageId,
          'digest': digest,
          'accepted_at': _clock().millisecondsSinceEpoch,
        }, conflictAlgorithm: ConflictAlgorithm.ignore);
        if (inserted != 0) return ReplayDisposition.accepted;
        final raced = await txn.query(
          'replay_tombstone',
          columns: ['digest'],
          where:
              'sender_user_id = ? AND sender_device_id = ? AND message_id = ?',
          whereArgs: [userId, deviceId, messageId],
        );
        if (raced.isEmpty) {
          throw StateError('Replay admission did not persist a result.');
        }
        return listEquals(raced.single['digest'] as Uint8List, digest)
            ? ReplayDisposition.idempotent
            : ReplayDisposition.conflict;
      }),
    );
  }

  Future<List<RelayEnvelopeRecord>> pendingEnvelopes(String direction) async {
    if (direction != 'inbox' && direction != 'outbox') {
      throw ArgumentError.value(direction);
    }
    final rows = await (await _db).query(
      'relay_envelope',
      where:
          'direction = ? AND acked_at IS NULL AND '
          '(expires_at IS NULL OR expires_at > ?)',
      whereArgs: [direction, _clock().millisecondsSinceEpoch],
    );
    return rows.map(_envelope).toList();
  }

  Future<int> expireEnvelopes() async {
    final db = await _db;
    return _admit(
      () => db.transaction((txn) async {
        final rows = await txn.query(
          'relay_envelope',
          columns: [
            'sender_user_id',
            'sender_device_id',
            'message_id',
            'digest',
            'replay_recorded_at',
          ],
          where: 'expires_at IS NOT NULL AND expires_at <= ?',
          whereArgs: [_clock().millisecondsSinceEpoch],
        );
        for (final row in rows) {
          final existing = await txn.query(
            'replay_tombstone',
            columns: ['digest'],
            where:
                'sender_user_id = ? AND sender_device_id = ? AND message_id = ?',
            whereArgs: [
              row['sender_user_id'],
              row['sender_device_id'],
              row['message_id'],
            ],
          );
          if (existing.isNotEmpty &&
              !listEquals(
                existing.single['digest'] as Uint8List,
                row['digest'] as Uint8List,
              )) {
            throw StateError('Conflicting replay tombstone.');
          }
          await txn.insert('replay_tombstone', {
            'sender_user_id': row['sender_user_id'],
            'sender_device_id': row['sender_device_id'],
            'message_id': row['message_id'],
            'digest': row['digest'],
            'accepted_at': row['replay_recorded_at'],
          }, conflictAlgorithm: ConflictAlgorithm.ignore);
        }
        return txn.delete(
          'relay_envelope',
          where: 'expires_at IS NOT NULL AND expires_at <= ?',
          whereArgs: [_clock().millisecondsSinceEpoch],
        );
      }),
    );
  }

  /// Acknowledgement purges ciphertext while retaining the sender/message
  /// digest tombstone for replay protection.
  Future<bool> acknowledgeEnvelope(
    String senderUserId,
    String senderDeviceId,
    String messageId,
  ) async {
    _identity(senderUserId, senderDeviceId);
    if (!_uuid.hasMatch(messageId)) throw ArgumentError('Invalid message id.');
    final db = await _db;
    return _admit(
      () => db.transaction((txn) async {
        final rows = await txn.query(
          'relay_envelope',
          columns: ['digest', 'replay_recorded_at'],
          where:
              'sender_user_id = ? AND sender_device_id = ? AND message_id = ?',
          whereArgs: [senderUserId, senderDeviceId, messageId],
        );
        if (rows.isEmpty) {
          final tombstone = await txn.query(
            'replay_tombstone',
            where:
                'sender_user_id = ? AND sender_device_id = ? AND message_id = ?',
            whereArgs: [senderUserId, senderDeviceId, messageId],
          );
          return tombstone.isNotEmpty;
        }
        final existing = await txn.query(
          'replay_tombstone',
          columns: ['digest'],
          where:
              'sender_user_id = ? AND sender_device_id = ? AND message_id = ?',
          whereArgs: [senderUserId, senderDeviceId, messageId],
        );
        if (existing.isNotEmpty &&
            !listEquals(
              existing.single['digest'] as Uint8List,
              rows.single['digest'] as Uint8List,
            )) {
          throw StateError('Conflicting replay tombstone.');
        }
        await txn.insert('replay_tombstone', {
          'sender_user_id': senderUserId,
          'sender_device_id': senderDeviceId,
          'message_id': messageId,
          'digest': rows.single['digest'],
          'accepted_at': rows.single['replay_recorded_at'],
        }, conflictAlgorithm: ConflictAlgorithm.ignore);
        await txn.delete(
          'relay_envelope',
          where:
              'sender_user_id = ? AND sender_device_id = ? AND message_id = ?',
          whereArgs: [senderUserId, senderDeviceId, messageId],
        );
        return true;
      }),
    );
  }

  RelayEnvelopeRecord _envelope(Map<String, Object?> row) =>
      RelayEnvelopeRecord(
        direction: row['direction']! as String,
        messageId: row['message_id']! as String,
        protocolVersion: row['protocol_version']! as int,
        messageType: row['message_type']! as String,
        senderUserId: row['sender_user_id']! as String,
        senderDeviceId: row['sender_device_id']! as String,
        recipientUserId: row['recipient_user_id']! as String,
        recipientDeviceId: row['recipient_device_id']! as String,
        senderKeyVersion: row['sender_key_version']! as int,
        recipientKeyVersion: row['recipient_key_version']! as int,
        nonce: row['nonce']! as Uint8List,
        ciphertext: row['ciphertext']! as Uint8List,
        signature: row['signature']! as Uint8List,
        digest: row['digest']! as Uint8List,
        createdAt: DateTime.fromMillisecondsSinceEpoch(
          row['created_at']! as int,
          isUtc: true,
        ),
        acceptedAt: row['accepted_at'] == null
            ? null
            : DateTime.fromMillisecondsSinceEpoch(
                row['accepted_at']! as int,
                isUtc: true,
              ),
        expiresAt: row['expires_at'] == null
            ? null
            : DateTime.fromMillisecondsSinceEpoch(
                row['expires_at']! as int,
                isUtc: true,
              ),
      );

  Future<int> cleanupReplay() async => (await _db).delete(
    'replay_tombstone',
    where: 'accepted_at <= ?',
    whereArgs: [
      _clock().subtract(const Duration(days: 8)).millisecondsSinceEpoch,
    ],
  );
  Future<LocalHistoryRetention> historyPolicy() async {
    final r = await (await _db).query('local_history_policy', where: 'id = 1');
    return LocalHistoryRetention.values.byName(
      'days${r.single['retention_days']}',
    );
  }

  Future<void> setHistoryPolicy(LocalHistoryRetention policy) async =>
      (await _db).update('local_history_policy', {
        'retention_days': policy.days,
      }, where: 'id = 1');
  Future<void> addLocalHistory(String plaintext, {DateTime? occurredAt}) async {
    if (plaintext.isEmpty || plaintext.length > 1024 * 1024) {
      throw ArgumentError('Invalid local history payload.');
    }
    final encrypted = await _encrypt(await _keyLoader(), plaintext);
    await addEncryptedLocalHistory(encrypted, occurredAt: occurredAt);
  }

  Future<void> addEncryptedLocalHistory(
    String encrypted, {
    DateTime? occurredAt,
  }) async {
    if (!LocalStorageCrypto.isEncrypted(encrypted) ||
        encrypted.length > 2 * 1024 * 1024) {
      throw ArgumentError('History must be versioned ciphertext.');
    }
    await (await _db).insert('local_history_entry', {
      'encrypted_payload': encrypted,
      'occurred_at': (occurredAt ?? _clock()).millisecondsSinceEpoch,
    });
  }

  Future<List<String>> encryptedLocalHistory() async => (await _db)
      .query('local_history_entry', orderBy: 'occurred_at ASC')
      .then(
        (rows) =>
            rows.map((row) => row['encrypted_payload']! as String).toList(),
      );
  Future<List<String>> readLocalHistory() async {
    final key = await _keyLoader();
    final result = <String>[];
    for (final encrypted in await encryptedLocalHistory()) {
      final value = await _decrypt(key, encrypted);
      if (value == null) throw StateError('Cannot decrypt local history.');
      result.add(value);
    }
    return result;
  }

  Future<int> cleanupHistory() async {
    final days = (await historyPolicy()).days;
    return (await _db).delete(
      'local_history_entry',
      where: 'occurred_at <= ?',
      whereArgs: [
        _clock().subtract(Duration(days: days)).millisecondsSinceEpoch,
      ],
    );
  }
}
