import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mirrorline/core/data/database.dart';
import 'package:mirrorline/core/data/daos/call_event_dao.dart';
import 'package:mirrorline/core/data/daos/notification_event_dao.dart';
import 'package:mirrorline/core/data/daos/peer_dao.dart';
import 'package:mirrorline/core/data/daos/queue_dao.dart';
import 'package:mirrorline/core/data/daos/sms_message_dao.dart';
import 'package:mirrorline/core/data/models/call_event.dart';
import 'package:mirrorline/core/data/models/notification_event.dart';
import 'package:mirrorline/core/data/models/peer.dart';
import 'package:mirrorline/core/data/models/queue_item.dart';
import 'package:mirrorline/core/data/models/sms_message.dart';
import 'package:mirrorline/core/security/local_storage_crypto.dart';
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
    'persists ciphertext while returning original readable models',
    () async {
      final db = await databaseFactory.openDatabase(
        inMemoryDatabasePath,
        options: OpenDatabaseOptions(
          version: AppDatabase.schemaVersion,
          singleInstance: false,
          onCreate: AppDatabase.instance.createTables,
        ),
      );
      final callDao = CallEventDao.forDatabase(db);
      final notificationDao = NotificationEventDao.forDatabase(db);
      final peerDao = PeerDao.forDatabase(db);
      final queueDao = QueueDao.forDatabase(db);
      final smsDao = SmsMessageDao.forDatabase(db);
      final timestamp = DateTime(2026, 1, 1);

      await callDao.insert(
        CallEvent(
          id: 'call-1',
          direction: 'incoming',
          number: '+905550000001',
          contactName: 'Private Caller',
          timestamp: timestamp,
          encrypted: '',
          status: 'missed',
          createdAt: timestamp,
        ),
      );
      await notificationDao.insert(
        NotificationEvent(
          id: 'notification-1',
          nativeId: 'private-native-id',
          packageName: 'com.private.app',
          appName: 'Private App',
          title: 'Private title',
          text: 'Private text',
          encrypted: '',
          timestamp: timestamp,
          createdAt: timestamp,
        ),
      );
      await peerDao.insert(
        Peer(
          id: 'peer-1',
          deviceName: 'Private Device',
          role: 'main',
          ip: '192.168.1.10',
          port: 45678,
          key: 'private-network-key',
          publicKey: 'private-public-key',
          createdAt: timestamp,
        ),
      );
      await queueDao.insert(
        QueueItem(
          type: 'sms',
          payload: '{"body":"Private queue payload"}',
          createdAt: timestamp,
        ),
      );
      await smsDao.insert(
        SmsMessage(
          id: 'sms-1',
          threadId: 'private-thread',
          address: '+905550000002',
          contactName: 'Private Sender',
          body: 'Private SMS body',
          encrypted: '',
          direction: 'incoming',
          status: 'received',
          timestamp: timestamp,
          createdAt: timestamp,
        ),
      );

      for (final table in [
        'peer',
        'call_event',
        'sms_message',
        'notification_event',
        'offline_queue',
      ]) {
        final rows = await db.query(table);
        final raw = rows.single.values.whereType<String>().join('|');
        expect(raw, isNot(contains('Private')));
        expect(raw, isNot(contains('+905550000')));
        expect(raw, isNot(contains('private-')));
      }

      expect((await callDao.getAll()).single.number, '+905550000001');
      expect((await notificationDao.getAll()).single.text, 'Private text');
      expect((await peerDao.getPeer())!.deviceName, 'Private Device');
      expect(
        (await queueDao.getAll()).single.payload,
        '{"body":"Private queue payload"}',
      );
      expect((await smsDao.getAll()).single.body, 'Private SMS body');
      expect(LocalStorageCrypto.currentPrefix, 'v1:');

      await db.close();
    },
  );
}
