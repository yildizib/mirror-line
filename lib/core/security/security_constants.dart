/// Centralized security, protocol, transport, and queue policy values.
///
/// These values are declarations for the hardening work. Enforcement belongs
/// to the relevant protocol, socket, queue, and migration tasks.
abstract final class SecurityConstants {
  static const int protocolVersion = 1;

  static const Duration heartbeatInterval = Duration(seconds: 30);
  static const Duration backgroundHeartbeatInterval = Duration(seconds: 60);
  static const Duration receiveTimeout = Duration(seconds: 90);
  static const Duration authenticationTimeout = Duration(seconds: 10);
  static const Duration pairingTimeout = Duration(seconds: 30);
  static const Duration reconnectInterval = Duration(seconds: 30);
  static const Duration pendingSmsTimeout = Duration(minutes: 2);
  static const Duration messageFreshnessWindow = Duration(minutes: 5);
  static const Duration queueItemTtl = Duration(hours: 24);

  static const int maxFrameBytes = 1024 * 1024;
  static const int maxJsonBytes = 1024 * 1024;
  static const int maxPayloadBytes = 768 * 1024;
  static const int maxQueueItems = 500;
  static const int maxQueueItemBytes = 256 * 1024;
  static const int maxQueueRetryCount = 5;
  static const int maxAcceptedMessageIds = 1000;
}
