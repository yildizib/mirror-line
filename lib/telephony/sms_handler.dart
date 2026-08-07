import '../network/socket_manager.dart';
import 'telephony_channel.dart';

class SmsHandler {
  final SocketManager _socket;

  SmsHandler({required SocketManager socket}) : _socket = socket;

  void startListening() {
    TelephonyChannel.setEventHandler((type, data) {
      if (type == 'onSms') {
        _socket.sendMessage('sms_incoming', {
          'address': data['address'] ?? 'unknown',
          'body': data['body'] ?? '',
          'thread_id': data['threadId']?.toString() ?? '',
          'timestamp': DateTime.now().millisecondsSinceEpoch,
        });
      }
    });
    TelephonyChannel.startListening();
  }

  Future<void> stopListening() => TelephonyChannel.stopListening();

  Future<void> sendSms(String address, String body) async {
    await TelephonyChannel.sendSms(address, body);
  }
}
