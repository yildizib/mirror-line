import '../network/socket_manager.dart';
import 'telephony_channel.dart';

class CallHandler {
  final SocketManager _socket;

  CallHandler({required SocketManager socket}) : _socket = socket;

  void startListening() {
    TelephonyChannel.setEventHandler((type, data) {
      if (type == 'onCall') {
        final number = data['number'] as String? ?? 'unknown';
        _socket.sendMessage('call_incoming', {
          'number': number,
          'timestamp': DateTime.now().millisecondsSinceEpoch,
        });
      }
    });
    TelephonyChannel.startListening();
  }

  Future<void> stopListening() => TelephonyChannel.stopListening();

  Future<void> rejectCall() async {
    await TelephonyChannel.rejectCall();
    await _socket.sendMessage('call_rejected', {
      'timestamp': DateTime.now().millisecondsSinceEpoch,
    });
  }
}
