import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:logger/logger.dart';
import 'package:mirrorline/core/data/daos/sms_message_dao.dart';
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
  }) {
    final container = ProviderContainer(
      overrides: [
        smsFacadeProvider.overrideWith(
          (ref) => SmsFacade(
            ref: ref,
            logger: Logger(),
            isSource: () => false,
            sendOrQueue: sendOrQueue,
            notify:
                ({
                  required int id,
                  required String title,
                  required String body,
                  NotificationPayload? payload,
                }) async {},
            dao: dao,
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
}
