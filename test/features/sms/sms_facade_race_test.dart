import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:logger/logger.dart';
import 'package:mirrorline/core/data/daos/sms_message_dao.dart';
import 'package:mirrorline/core/data/daos/platform_operation_dao.dart';
import 'package:mirrorline/core/data/models/sms_message.dart';
import 'package:mirrorline/core/network/message_protocol.dart';
import 'package:mirrorline/core/services/notification_service.dart';
import 'package:mirrorline/features/connection/connection_facade.dart';
import 'package:mirrorline/features/sms/sms_facade.dart';

class _FakeSmsMessageDao extends SmsMessageDao {
  _FakeSmsMessageDao({Future<List<SmsMessage>>? initialMessages})
    : _initialMessages = initialMessages ?? Future.value([]);

  final Future<List<SmsMessage>> _initialMessages;
  final Map<String, SmsMessage> messages = {};
  bool insertCalled = false;

  @override
  Future<List<SmsMessage>> getAll() => _initialMessages;

  @override
  Future<void> insert(SmsMessage message) async {
    insertCalled = true;
    messages[message.id] = message;
  }

  @override
  Future<void> updateStatus(String id, String status) async {
    final message = messages[id];
    if (message != null) messages[id] = message.copyWith(status: status);
  }
}

class _FakePlatformOperationDao extends PlatformOperationDao {
  final Map<String, PlatformOperation> operations = {};

  @override
  Future<bool> claim({
    required String operationId,
    required String kind,
    required String payload,
  }) async {
    if (operations.containsKey(operationId)) return false;
    operations[operationId] = PlatformOperation(
      id: operationId,
      kind: kind,
      state: 'received',
      payload: payload,
    );
    return true;
  }

  @override
  Future<bool> transition(
    String operationId, {
    required Iterable<String> from,
    required String to,
  }) async {
    final operation = operations[operationId];
    if (operation == null || !from.contains(operation.state)) return false;
    operations[operationId] = PlatformOperation(
      id: operation.id,
      kind: operation.kind,
      state: to,
      payload: operation.payload,
    );
    return true;
  }

  @override
  Future<String?> payload(String operationId) async =>
      operations[operationId]?.payload;

  @override
  Future<int> recoverExecuting({String? kind}) async {
    var recovered = 0;
    for (final operation in operations.values.toList()) {
      if (operation.state == 'executing' &&
          (kind == null || operation.kind == kind)) {
        await transition(operation.id, from: ['executing'], to: 'received');
        recovered++;
      }
    }
    return recovered;
  }

  @override
  Future<List<PlatformOperation>> list({
    required String kind,
    required Iterable<String> states,
  }) async => operations.values
      .where(
        (operation) =>
            operation.kind == kind && states.contains(operation.state),
      )
      .toList();
}

SmsMessage _message(String id, {String status = 'received'}) {
  final timestamp = DateTime(2026, 8, 16, 12);
  return SmsMessage(
    id: id,
    threadId: 'thread-1',
    address: '+15555550100',
    contactName: 'Test',
    body: 'hello',
    encrypted: '',
    direction: status == 'received' ? 'incoming' : 'outgoing',
    status: status,
    timestamp: timestamp,
    createdAt: timestamp,
  );
}

void main() {
  ProviderContainer buildContainer({
    required _FakeSmsMessageDao dao,
    required SendOrQueue sendOrQueue,
    bool Function()? isSource,
    PlatformOperationDao? operations,
    Future<void> Function(String, String, {required String operationId})?
    sendSms,
    Future<bool> Function(String operationId)? hasSmsSubmission,
  }) {
    final container = ProviderContainer(
      overrides: [
        smsFacadeProvider.overrideWith(
          (ref) => SmsFacade(
            ref: ref,
            logger: Logger(),
            isSource: isSource ?? () => false,
            sendOrQueue: sendOrQueue,
            notify:
                ({
                  required int id,
                  required String title,
                  required String body,
                  NotificationPayload? payload,
                }) async {},
            dao: dao,
            operations: operations,
            sendSms: sendSms,
            hasSmsSubmission: hasSmsSubmission,
          ),
        ),
      ],
    );
    addTearDown(container.dispose);
    return container;
  }

  test('constructor load completes before a newer mutation', () async {
    final loadCompleter = Completer<List<SmsMessage>>();
    final dao = _FakeSmsMessageDao(initialMessages: loadCompleter.future);
    final container = buildContainer(
      dao: dao,
      sendOrQueue: (_, _) async => true,
    );
    final facade = container.read(smsFacadeProvider.notifier);

    final addFuture = facade.add(_message('new'));
    await Future<void>.delayed(Duration.zero);
    expect(dao.insertCalled, isFalse);

    loadCompleter.complete([_message('old')]);
    await addFuture;

    expect(facade.state.map((message) => message.id), ['new', 'old']);
    expect(dao.messages['new'], isNotNull);
  });

  test('reply is persisted before transport is invoked', () async {
    final dao = _FakeSmsMessageDao();
    late SmsFacade facade;
    var transportCalled = false;
    final container = buildContainer(
      dao: dao,
      sendOrQueue: (type, payload) async {
        transportCalled = true;
        final id = payload['id']! as String;
        expect(type, MessageTypes.smsOutgoing);
        expect(dao.messages[id]?.status, 'pending');
        expect(facade.state.single.id, id);
        return false;
      },
    );
    facade = container.read(smsFacadeProvider.notifier);

    final sent = await facade.sendReplySms(
      '+15555550100',
      'reply',
      id: 'reply-1',
      contactName: 'Test',
      threadId: 'thread-1',
      timestamp: DateTime(2026, 8, 16, 13),
    );

    expect(sent, isFalse);
    expect(transportCalled, isTrue);
    expect(facade.state.single.status, 'pending');
  });

  test('an immediate status callback replaces pending state', () async {
    final dao = _FakeSmsMessageDao();
    late SmsFacade facade;
    final container = buildContainer(
      dao: dao,
      sendOrQueue: (type, payload) async {
        final id = payload['id']! as String;
        await facade.handleIncomingMessage(
          MessageTypes.smsStatus,
          {'id': id, 'status': 'sent'},
          MirrorMessage(
            type: MessageTypes.smsStatus,
            id: 'ack-1',
            timestamp: 0,
            payload: '',
          ),
          DateTime(2026, 8, 16, 13),
        );
        return true;
      },
    );
    facade = container.read(smsFacadeProvider.notifier);

    await facade.sendReplySms('+15555550100', 'reply', id: 'reply-1');

    expect(facade.state.single.status, 'sent');
    expect(dao.messages['reply-1']?.status, 'sent');
  });

  test('status received before its message is reconciled on add', () async {
    final dao = _FakeSmsMessageDao();
    final container = buildContainer(
      dao: dao,
      sendOrQueue: (_, _) async => true,
    );
    final facade = container.read(smsFacadeProvider.notifier);

    await facade.updateStatus('reply-1', 'delivered');
    await facade.add(_message('reply-1', status: 'pending'));

    expect(facade.state.single.status, 'delivered');
    expect(dao.messages['reply-1']?.status, 'delivered');
  });

  test(
    'recovery submits received SMS from durable operation payload once',
    () async {
      final operations = _FakePlatformOperationDao();
      final submissions = <String>[];
      final container = buildContainer(
        dao: _FakeSmsMessageDao(),
        isSource: () => true,
        operations: operations,
        sendOrQueue: (_, _) async => true,
        sendSms: (address, body, {required operationId}) async {
          submissions.add('$operationId:$address:$body');
        },
      );
      final facade = container.read(smsFacadeProvider.notifier);
      final message = MirrorMessage(
        type: MessageTypes.smsOutgoing,
        id: 'transport-message-id',
        timestamp: 0,
        payload: '',
      );

      await facade.handleIncomingMessage(
        MessageTypes.smsOutgoing,
        {'id': 'domain-sms-id', 'address': '+15555550100', 'body': 'reply'},
        message,
        DateTime(2026, 8, 16),
      );
      await facade.recoverOutgoingSms();
      await facade.recoverOutgoingSms();

      expect(submissions, ['transport-message-id:+15555550100:reply']);
      expect(operations.operations['transport-message-id']?.state, 'submitted');
    },
  );

  test(
    'recovery never blindly retries an SMS already submitted to Android',
    () async {
      final operations = _FakePlatformOperationDao();
      final submissions = <String>[];
      final container = buildContainer(
        dao: _FakeSmsMessageDao(),
        isSource: () => true,
        operations: operations,
        sendOrQueue: (_, _) async => true,
        sendSms: (_, _, {required operationId}) async {
          submissions.add(operationId);
        },
      );
      final facade = container.read(smsFacadeProvider.notifier);
      await operations.claim(
        operationId: 'submitted-operation',
        kind: 'sms_send',
        payload:
            '{"messageId":"sms-1","address":"+15555550100","body":"reply"}',
      );

      await facade.executeOutgoingSms('submitted-operation');
      await facade.recoverOutgoingSms();

      expect(submissions, ['submitted-operation']);
      expect(operations.operations['submitted-operation']?.state, 'submitted');
    },
  );

  test(
    'recovery promotes a native-accepted ready SMS without resubmitting',
    () async {
      final operations = _FakePlatformOperationDao();
      final submissions = <String>[];
      final container = buildContainer(
        dao: _FakeSmsMessageDao(),
        isSource: () => true,
        operations: operations,
        sendOrQueue: (_, _) async => true,
        hasSmsSubmission: (_) async => true,
        sendSms: (_, _, {required operationId}) async {
          submissions.add(operationId);
        },
      );
      final facade = container.read(smsFacadeProvider.notifier);
      await operations.claim(
        operationId: 'native-accepted',
        kind: 'sms_send',
        payload:
            '{"messageId":"sms-1","address":"+15555550100","body":"reply"}',
      );
      await operations.transition(
        'native-accepted',
        from: ['received'],
        to: 'ready',
      );

      await facade.recoverOutgoingSms();

      expect(submissions, isEmpty);
      expect(operations.operations['native-accepted']?.state, 'submitted');
    },
  );
}
