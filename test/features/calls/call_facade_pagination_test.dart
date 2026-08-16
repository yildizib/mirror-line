import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:logger/logger.dart';
import 'package:mirrorline/core/data/database.dart';
import 'package:mirrorline/core/data/daos/inbox_dao.dart';
import 'package:mirrorline/core/data/daos/platform_operation_dao.dart';
import 'package:mirrorline/core/data/models/inbox_record.dart';
import 'package:mirrorline/core/data/models/call_event.dart';
import 'package:mirrorline/core/network/message_protocol.dart';
import 'package:mirrorline/core/services/notification_service.dart';
import 'package:mirrorline/features/calls/call_facade.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FakePathProviderPlatform extends PathProviderPlatform
    with MockPlatformInterfaceMixin {
  _FakePathProviderPlatform(this._path);
  final String _path;

  @override
  Future<String?> getApplicationDocumentsPath() async => _path;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory tempDir;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    SharedPreferences.setMockInitialValues({});
  });

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp(
      'mirrorline_call_facade_test',
    );
    PathProviderPlatform.instance = _FakePathProviderPlatform(tempDir.path);
  });

  tearDown(() async {
    await AppDatabase.instance.close();
    await tempDir.delete(recursive: true);
  });

  ProviderContainer buildContainer({
    bool Function()? isSource,
    Future<bool> Function({required String operationId})? rejectCall,
    Future<bool> Function(String operationId)? hasCallRejection,
    Future<bool> Function(String, Map<String, dynamic>)? sendOrQueue,
  }) {
    final container = ProviderContainer(
      overrides: [
        callFacadeProvider.overrideWith((ref) {
          return CallFacade(
            ref: ref,
            logger: Logger(),
            isSource: isSource ?? () => false,
            sendOrQueue: sendOrQueue ?? (type, payload) async => true,
            notify:
                ({
                  required int id,
                  required String title,
                  required String body,
                  NotificationPayload? payload,
                }) async {},
            rejectCall: rejectCall,
            hasCallRejection: hasCallRejection,
          );
        }),
      ],
    );
    addTearDown(container.dispose);
    return container;
  }

  CallEvent makeEvent({required String id, required DateTime timestamp}) {
    return CallEvent(
      id: id,
      direction: 'incoming',
      number: '+15555550100',
      contactName: 'Test',
      timestamp: timestamp,
      encrypted: '',
      status: 'missed',
      createdAt: timestamp,
    );
  }

  test('loadRecent returns newest-first with limit', () async {
    final container = buildContainer();
    final facade = container.read(callFacadeProvider.notifier);

    final base = DateTime(2025, 1, 1, 12);
    for (var i = 0; i < 30; i++) {
      await facade.add(
        makeEvent(
          id: 'c$i',
          timestamp: base.add(Duration(minutes: i)),
        ),
      );
    }

    final recent = await facade.loadRecent(limit: 10);
    expect(recent.length, 10);
    expect(recent.first.id, 'c29');
    expect(recent.last.id, 'c20');
  });

  test(
    'failed native rejection preserves ringing and sends no status',
    () async {
      final sentTypes = <String>[];
      final container = buildContainer(
        isSource: () => true,
        rejectCall: ({required operationId}) async => false,
        sendOrQueue: (type, payload) async {
          sentTypes.add(type);
          return true;
        },
      );
      final facade = container.read(callFacadeProvider.notifier);
      await facade.initialized;
      final now = DateTime(2025, 1, 1, 12);
      await facade.handleNativeEvent(
        {'state': 'RINGING', 'number': '+15555550100'},
        id: 'active-call',
        now: now,
      );
      sentTypes.clear();

      final rejected = await facade.handleIncomingMessage(
        MessageTypes.callRejected,
        {'id': 'active-call'},
        MirrorMessage(
          type: MessageTypes.callRejected,
          id: 'command',
          timestamp: now.millisecondsSinceEpoch,
          payload: '',
        ),
        now,
      );

      expect(rejected, false);
      expect(facade.state.single.status, 'ringing');
      expect(sentTypes, isEmpty);
      expect(await PlatformOperationDao().state('command'), 'failed');
    },
  );

  test(
    'call reject uses transport message ID and ignores duplicate execution',
    () async {
      var rejections = 0;
      final container = buildContainer(
        isSource: () => true,
        rejectCall: ({required operationId}) async {
          rejections++;
          return true;
        },
      );
      final facade = container.read(callFacadeProvider.notifier);
      final now = DateTime(2025, 1, 1, 12);
      await facade.handleNativeEvent(
        {'state': 'RINGING', 'number': '+15555550100'},
        id: 'domain-call-id',
        now: now,
      );
      await facade.handleIncomingMessage(
        MessageTypes.callRejected,
        {'id': 'domain-call-id'},
        MirrorMessage(
          type: MessageTypes.callRejected,
          id: 'transport-command-id',
          timestamp: now.millisecondsSinceEpoch,
          payload: '',
        ),
        now,
      );

      expect(rejections, 1);
      expect(
        await PlatformOperationDao().state('transport-command-id'),
        'succeeded',
      );
      expect(await facade.executeCallReject('transport-command-id'), isFalse);
      expect(rejections, 1);
    },
  );

  test(
    'recovery never retries an uncertain call rejection against a new call',
    () async {
      var rejections = 0;
      final container = buildContainer(
        isSource: () => true,
        rejectCall: ({required operationId}) async {
          rejections++;
          return true;
        },
      );
      final facade = container.read(callFacadeProvider.notifier);
      await facade.initialized;
      await PlatformOperationDao().claim(
        operationId: 'uncertain-old-call',
        kind: 'call_reject',
        payload: '{"callId":"old-call","nativeSessionId":"old-session"}',
      );
      await PlatformOperationDao().transition(
        'uncertain-old-call',
        from: ['received'],
        to: 'ready',
      );
      await facade.handleNativeEvent(
        {
          'state': 'RINGING',
          'callSessionId': 'new-session',
          'number': '+15555550101',
        },
        id: 'new-call',
        now: DateTime(2025, 1, 1, 12),
      );

      await facade.recoverCallRejects();

      expect(rejections, 0);
      expect(
        await PlatformOperationDao().state('uncertain-old-call'),
        'failed',
      );
    },
  );

  test(
    'restart reconciles accepted rejection without another native call or status',
    () async {
      var nativeAccepted = false;
      var rejections = 0;
      final reconciliationQueries = <String>[];
      final now = DateTime(2025, 1, 1, 12);
      final firstContainer = buildContainer(
        isSource: () => true,
        rejectCall: ({required operationId}) async {
          nativeAccepted = true;
          // Model a process death after Android accepts endCall but before
          // Dart receives the channel result and persists its terminal state.
          throw StateError('lost native reply');
        },
        hasCallRejection: (operationId) async => nativeAccepted,
      );
      final firstFacade = firstContainer.read(callFacadeProvider.notifier);
      await firstFacade.handleNativeEvent(
        {
          'state': 'RINGING',
          'callSessionId': 'old-session',
          'number': '+15555550100',
        },
        id: 'old-call',
        now: now,
      );
      await firstFacade.handleIncomingMessage(
        MessageTypes.callRejected,
        {'id': 'old-call'},
        MirrorMessage(
          type: MessageTypes.callRejected,
          id: 'accepted-command',
          timestamp: now.millisecondsSinceEpoch,
          payload: '',
        ),
        now,
      );
      expect(await PlatformOperationDao().state('accepted-command'), 'ready');
      firstContainer.dispose();

      final sentTypes = <String>[];
      final secondContainer = buildContainer(
        isSource: () => true,
        rejectCall: ({required operationId}) async {
          rejections++;
          return true;
        },
        hasCallRejection: (operationId) async {
          reconciliationQueries.add(operationId);
          return nativeAccepted;
        },
        sendOrQueue: (type, payload) async {
          sentTypes.add(type);
          return true;
        },
      );
      final secondFacade = secondContainer.read(callFacadeProvider.notifier);
      await secondFacade.handleNativeEvent(
        {
          'state': 'RINGING',
          'callSessionId': 'new-session',
          'number': '+15555550101',
        },
        id: 'new-call',
        now: now.add(const Duration(seconds: 1)),
      );
      sentTypes.clear();

      await secondFacade.recoverCallRejects();

      expect(rejections, 0);
      expect(reconciliationQueries, ['accepted-command']);
      expect(
        await PlatformOperationDao().state('accepted-command'),
        'submitted',
      );
      expect(
        secondFacade.state.singleWhere((call) => call.id == 'old-call').status,
        'ringing',
      );
      expect(
        secondFacade.state.singleWhere((call) => call.id == 'new-call').status,
        'ringing',
      );
      expect(sentTypes, isEmpty);
    },
  );

  test('delayed call A events update A without mutating call B', () async {
    final sentTypes = <String>[];
    final container = buildContainer(
      isSource: () => true,
      sendOrQueue: (type, payload) async {
        sentTypes.add(type);
        return true;
      },
    );
    final facade = container.read(callFacadeProvider.notifier);
    final now = DateTime(2025, 1, 1, 12);

    await facade.handleNativeEvent(
      {
        'state': 'RINGING',
        'callSessionId': 'session-a',
        'number': '+15555550101',
        'contactName': 'Call A',
      },
      id: 'call-a',
      now: now,
    );
    await facade.handleNativeEvent(
      {
        'state': 'RINGING',
        'callSessionId': 'session-b',
        'number': '+15555550102',
        'contactName': 'Call B',
      },
      id: 'call-b',
      now: now.add(const Duration(seconds: 1)),
    );
    sentTypes.clear();

    await facade.handleNativeEvent(
      {
        'state': 'RINGING_UPDATE',
        'callSessionId': 'session-a',
        'number': '+19999999999',
        'contactName': 'Delayed A',
      },
      id: 'ignored-update',
      now: now.add(const Duration(seconds: 2)),
    );
    await facade.handleNativeEvent(
      {'state': 'MISSED', 'callSessionId': 'session-a'},
      id: 'ignored-terminal',
      now: now.add(const Duration(seconds: 3)),
    );
    await facade.handleNativeEvent(
      {'state': 'RINGING_UPDATE', 'contactName': 'Missing Session'},
      id: 'ignored-sessionless-update',
      now: now.add(const Duration(milliseconds: 3500)),
    );
    await facade.handleNativeEvent(
      {
        'state': 'RINGING_UPDATE',
        'callSessionId': 'unknown-session',
        'contactName': 'Unknown Session',
      },
      id: 'ignored-unknown-update',
      now: now.add(const Duration(milliseconds: 3750)),
    );

    final callA = facade.state.singleWhere((call) => call.id == 'call-a');
    final callB = facade.state.singleWhere((call) => call.id == 'call-b');
    expect(callA.status, 'missed');
    expect(callA.number, '+19999999999');
    expect(callA.contactName, 'Delayed A');
    expect(callB.status, 'ringing');
    expect(callB.number, '+15555550102');
    expect(callB.contactName, 'Call B');
    expect(sentTypes, [MessageTypes.callInfo, MessageTypes.callStatus]);

    await facade.handleNativeEvent(
      {'state': 'ENDED', 'callSessionId': 'session-b'},
      id: 'call-b-terminal',
      now: now.add(const Duration(seconds: 4)),
    );

    expect(
      facade.state.singleWhere((call) => call.id == 'call-b').status,
      'ended',
    );
    expect(sentTypes, [
      MessageTypes.callInfo,
      MessageTypes.callStatus,
      MessageTypes.callStatus,
    ]);
  });

  test('answered call retains session correlation until ended', () async {
    final sentStatuses = <String>[];
    var nativeRejectCalls = 0;
    final container = buildContainer(
      isSource: () => true,
      rejectCall: ({required operationId}) async {
        nativeRejectCalls++;
        return true;
      },
      sendOrQueue: (type, payload) async {
        if (type == MessageTypes.callStatus) {
          sentStatuses.add(payload['status'] as String);
        }
        return true;
      },
    );
    final facade = container.read(callFacadeProvider.notifier);
    final now = DateTime(2025, 1, 1, 12);

    await facade.handleNativeEvent(
      {
        'state': 'RINGING',
        'callSessionId': 'answered-session',
        'number': '+15555550100',
      },
      id: 'answered-call',
      now: now,
    );
    await facade.handleNativeEvent(
      {'state': 'ANSWERED', 'callSessionId': 'answered-session'},
      id: 'answered-transition',
      now: now.add(const Duration(seconds: 1)),
    );

    expect(facade.state.single.status, 'answered');
    final rejected = await facade.handleIncomingMessage(
      MessageTypes.callRejected,
      {'id': 'answered-call'},
      MirrorMessage(
        type: MessageTypes.callRejected,
        id: 'reject-command',
        timestamp: now.millisecondsSinceEpoch,
        payload: '',
      ),
      now.add(const Duration(seconds: 2)),
    );
    expect(rejected, isFalse);
    expect(nativeRejectCalls, 0);

    await facade.handleNativeEvent(
      {'state': 'ENDED', 'callSessionId': 'answered-session'},
      id: 'ended-transition',
      now: now.add(const Duration(seconds: 3)),
    );

    expect(facade.state.single.status, 'ended');
    expect(sentStatuses, ['answered', 'ended']);
  });

  test('sessionless legacy call transitions remain correlated', () async {
    final container = buildContainer(isSource: () => true);
    final facade = container.read(callFacadeProvider.notifier);
    final now = DateTime(2025, 1, 1, 12);

    await facade.handleNativeEvent(
      {'state': 'RINGING', 'number': '+15555550100'},
      id: 'legacy-call',
      now: now,
    );
    await facade.handleNativeEvent(
      {'state': 'MISSED'},
      id: 'legacy-terminal',
      now: now.add(const Duration(seconds: 1)),
    );

    expect(facade.state.single.status, 'missed');
  });

  test(
    'call Inbox transaction persists before post-commit state publication',
    () async {
      final container = buildContainer();
      final facade = container.read(callFacadeProvider.notifier);
      final db = await AppDatabase.instance.database;
      final inbox = InboxDao();
      final now = DateTime(2026, 8, 16, 12);
      final message = MirrorMessage(
        type: MessageTypes.callIncoming,
        id: 'call-transport-id',
        timestamp: now.millisecondsSinceEpoch,
        payload: 'ciphertext',
        sourcePeerId: 'peer-a',
      );
      final payload = {
        'id': 'call-domain-id',
        'number': '+15555550100',
        'contact_name': 'Test',
        'timestamp': now.millisecondsSinceEpoch,
      };

      expect(
        () => db.transaction((transaction) async {
          await inbox.insertIfAbsentOn(
            transaction,
            InboxRecord(
              sourcePeerId: 'peer-a',
              messageId: message.id,
              type: message.type,
              receivedAt: now,
              updatedAt: now,
            ),
          );
          await facade.persistIncomingMessageOn(
            message.type,
            payload,
            message,
            now,
            transaction,
          );
          throw StateError('rollback');
        }),
        throwsStateError,
      );
      expect(await db.query('inbox'), isEmpty);
      expect(await db.query('call_event'), isEmpty);
      expect(facade.state, isEmpty);

      await db.transaction((transaction) async {
        await inbox.insertIfAbsentOn(
          transaction,
          InboxRecord(
            sourcePeerId: 'peer-a',
            messageId: message.id,
            type: message.type,
            receivedAt: now,
            updatedAt: now,
          ),
        );
        await facade.persistIncomingMessageOn(
          message.type,
          payload,
          message,
          now,
          transaction,
        );
      });
      await facade.handleIncomingMessage(
        message.type,
        payload,
        message,
        now,
        alreadyPersisted: true,
      );

      expect(await db.query('call_event'), hasLength(1));
      expect(facade.state.single.id, 'call-domain-id');
    },
  );

  test('loadRecent filters by since', () async {
    final container = buildContainer();
    final facade = container.read(callFacadeProvider.notifier);

    await facade.add(makeEvent(id: 'old', timestamp: DateTime(2025, 6, 1)));
    await facade.add(
      makeEvent(id: 'yesterday', timestamp: DateTime(2025, 6, 14, 9)),
    );
    await facade.add(
      makeEvent(id: 'today', timestamp: DateTime(2025, 6, 15, 8)),
    );

    final since = DateTime(2025, 6, 14);
    final recent = await facade.loadRecent(limit: 100, since: since);
    expect(recent.length, 2);
    expect(recent.map((e) => e.id).toList(), ['today', 'yesterday']);
  });

  test('loadOlder paginates with offset', () async {
    final container = buildContainer();
    final facade = container.read(callFacadeProvider.notifier);

    final base = DateTime(2025, 1, 1, 12);
    for (var i = 0; i < 50; i++) {
      await facade.add(
        makeEvent(
          id: 'c$i',
          timestamp: base.add(Duration(minutes: i)),
        ),
      );
    }

    final page1 = await facade.loadOlder(limit: 10, offset: 0);
    expect(page1.length, 10);
    expect(page1.first.id, 'c49');

    final page2 = await facade.loadOlder(limit: 10, offset: 10);
    expect(page2.length, 10);
    expect(page2.first.id, 'c39');
  });
}
