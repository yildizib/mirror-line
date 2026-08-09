// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get appTitle => 'MirrorLine';

  @override
  String get splashTagline => 'Two phones, end-to-end encrypted connection';

  @override
  String get navCalls => 'Calls';

  @override
  String get navSms => 'SMS';

  @override
  String get navSettings => 'Settings';

  @override
  String get roleTitle => 'Role Selection';

  @override
  String get rolePrompt => 'Which role should this phone take?';

  @override
  String get roleHint => 'You can change the role later in settings.';

  @override
  String get roleMain => 'Main Phone';

  @override
  String get roleMainDesc =>
      'Sees notifications, can reject calls, reply to SMS.';

  @override
  String get roleSource => 'Other Phone';

  @override
  String get roleSourceDesc =>
      'The device with the SIM that captures call and SMS events in the background.';

  @override
  String get roleMainSelected => 'Main Phone selected';

  @override
  String get roleSourceSelected => 'Other Phone selected';

  @override
  String get batteryDialogTitle => 'Reliable background operation';

  @override
  String get batteryDialogBody =>
      'Since this device is the \"Other Phone\", it must keep running continuously, even with the screen off, to capture call/SMS events. You need to exempt this app from Android\'s battery optimization.\n\nNote: this means slightly higher battery consumption -- a conscious trade-off for keeping the connection alive. You can also enable this later in Settings.';

  @override
  String get later => 'Later';

  @override
  String get setupNow => 'Set Up Now';

  @override
  String get pairingTitle => 'Pair Device';

  @override
  String get pairingShowQr => 'Show QR';

  @override
  String get pairingScanQr => 'Scan QR';

  @override
  String get pairingSelectRoleFirst => 'You must select a role first.';

  @override
  String get pairingSelectRoleButton => 'Select Role';

  @override
  String get pairingOtherScanHint => 'Have the other phone scan this QR code.';

  @override
  String get pairingRequestReceived => 'Pairing request received!';

  @override
  String get verificationCodeLabel => 'VERIFICATION CODE';

  @override
  String get pairingCodeMatch => 'The code must be the same on both devices.';

  @override
  String pairingWaiting(String device) {
    return 'Waiting to pair with $device...';
  }

  @override
  String get pairingCancel => 'Cancel';

  @override
  String get pairingRetry => 'Retry';

  @override
  String get pairingScanPrompt => 'Scan the other device\'s QR code';

  @override
  String get pairingStartScan => 'Start Scanning';

  @override
  String get pairingRequestTitle => 'Pairing Request';

  @override
  String pairingRequestFrom(String device) {
    return '$device wants to pair with you.';
  }

  @override
  String get pairingReject => 'Reject';

  @override
  String get pairingConfirm => 'Confirm';

  @override
  String get pairingConfirmTitle => 'Confirm Pairing';

  @override
  String pairingConfirmBody(String device) {
    return 'You will pair with $device.';
  }

  @override
  String pairingPairedWith(String device) {
    return 'Paired with $device!';
  }

  @override
  String get pairingInvalidQr => 'Invalid QR code format';

  @override
  String get pairingUnknownDevice => 'Unknown Device';

  @override
  String get pairingErrorConnectionFailed => 'Could not connect.';

  @override
  String get pairingErrorRejectedOrTimedOut =>
      'Pairing was rejected or timed out.';

  @override
  String get pairingErrorHandshake => 'Pairing error';

  @override
  String get pairingErrorRejected => 'Pairing rejected.';

  @override
  String get pairingErrorAckTimeout =>
      'Pairing could not complete (no confirmation from the other device). Try again.';

  @override
  String get settingsThisDevice => 'This Device';

  @override
  String get settingsNoDeviceInfo => 'No device info yet. Select a role.';

  @override
  String get settingsPairedDevice => 'Paired Device';

  @override
  String get settingsNotPairedHint =>
      'Not paired yet. Scan on the other device:';

  @override
  String get settingsConnectionDiag => 'Connection Diagnostics';

  @override
  String get settingsLocalIp => 'This device IP';

  @override
  String get settingsPeerIp => 'Peer device IP';

  @override
  String get settingsServer => 'Server';

  @override
  String settingsServerRunning(int port) {
    return 'running (port $port)';
  }

  @override
  String get settingsServerStopped => 'stopped';

  @override
  String get settingsLastBeacon => 'Last beacon';

  @override
  String get settingsNoBeacon => 'none yet';

  @override
  String get settingsConnectAttempts => 'Attempt count';

  @override
  String get settingsPairedDevices => 'Paired Devices';

  @override
  String get settingsNoPairedDevices => 'No paired devices yet.';

  @override
  String get settingsPort => 'Port';

  @override
  String get settingsIpLabel => 'IP';

  @override
  String get settingsPublicKeyLabel => 'Public Key';

  @override
  String get settingsRoleLabel => 'Role';

  @override
  String get settingsCounterpartSuffix => ' (peer)';

  @override
  String get settingsIpUnknown => 'unknown';

  @override
  String get settingsForceReconnect => 'Force Reconnect';

  @override
  String get settingsPairDevice => 'Pair Device';

  @override
  String get settingsChangeRole => 'Change Role';

  @override
  String get settingsSystem => 'System';

  @override
  String get settingsRemoveBatteryOpt => 'Remove battery optimization';

  @override
  String get settingsRemoveBatteryOptDesc =>
      'For the app to run reliably in the background';

  @override
  String get settingsBatteryOpened => 'Battery settings opened';

  @override
  String get settingsNotifAccess => 'Notification access';

  @override
  String get settingsNotifAccessDesc =>
      'Required to mirror notifications from the other phone';

  @override
  String get settingsKeepPermissions => 'Don\'t remove permissions when unused';

  @override
  String get settingsKeepPermissionsDesc =>
      'Turn off \"Remove permissions if unused\" (\"App not in use\" on HyperOS) in App Info -- if left on, Android may revoke SMS/call permissions after a few months';

  @override
  String get settingsAutoStart => 'Background autostart permission';

  @override
  String get settingsAutoStartKnown =>
      'This device\'s manufacturer (Xiaomi/Huawei/OPPO/Vivo/Samsung etc.) may apply extra background restrictions -- add this app to the allowlist here';

  @override
  String get settingsAutoStartFallback =>
      'If manufacturer settings aren\'t found, App Info opens';

  @override
  String get settingsBatterySaver => 'Battery saver exception';

  @override
  String get settingsBatterySaverDesc =>
      'This device\'s manufacturer (HyperOS/MIUI) uses a separate battery saver list -- select \"No restrictions\" here too so the connection doesn\'t drop with the screen off';

  @override
  String get settingsResetDevice => 'Reset Device';

  @override
  String get settingsResetDesc => 'Delete all data and generate new QR';

  @override
  String get settingsResetConfirmTitle => 'Reset Device';

  @override
  String get settingsResetConfirmBody =>
      'All pairing info, call and SMS history will be deleted. A new QR will be generated.';

  @override
  String get settingsResetDone => 'Device reset';

  @override
  String get settingsLanguage => 'Language';

  @override
  String get settingsLanguageSystem => 'System language';

  @override
  String get connStatusConnected => 'Connected';

  @override
  String get connStatusDisconnected => 'Disconnected';

  @override
  String get connStatusConnecting => 'Connecting...';

  @override
  String get connBannerOffline =>
      'No connection. Searching for peer; make sure you\'re on the same WiFi network.';

  @override
  String get connErrorServerStartFailed => 'Could not start server';

  @override
  String get connErrorPeerIpUnknown =>
      'Peer device IP unknown (waiting for beacon)';

  @override
  String get connErrorConnectFailed =>
      'Connection failed (server down or unreachable)';

  @override
  String get callStatusRinging => 'Ringing';

  @override
  String get callStatusAnswered => 'Answered';

  @override
  String get callStatusMissed => 'Missed';

  @override
  String get callStatusRejected => 'Rejected';

  @override
  String get callStatusEnded => 'Ended';

  @override
  String get callStatusFailed => 'Failed';

  @override
  String get callUnknownNumber => 'Unknown number';

  @override
  String get callsEmpty => 'No incoming calls yet';

  @override
  String callsSelectedCount(int count) {
    return '$count selected';
  }

  @override
  String get callsDeleteSelected => 'Delete selected calls';

  @override
  String callsDeleteConfirmBody(int groups, int count) {
    return '$count calls from $groups contacts will be permanently deleted.';
  }

  @override
  String get callsDeleted => 'Selected calls deleted';

  @override
  String callsCallCount(int count) {
    return '$count calls';
  }

  @override
  String get callsRejected => 'Call rejected';

  @override
  String get callsSelectMode => 'Select calls';

  @override
  String callsDeleteOne(int count) {
    return '$count call(s) will be permanently deleted.';
  }

  @override
  String get smsStatusReceived => 'Received';

  @override
  String get smsStatusSent => 'Sent';

  @override
  String get smsStatusDelivered => 'Delivered';

  @override
  String get smsStatusSending => 'Sending';

  @override
  String get smsStatusFailed => 'Failed';

  @override
  String get smsUnknownSender => 'Unknown sender';

  @override
  String get smsEmpty => 'No messages yet';

  @override
  String smsSelectedCount(int count) {
    return '$count selected';
  }

  @override
  String get smsDeleteSelected => 'Delete selected conversations';

  @override
  String smsDeleteConfirmBody(int count) {
    return '$count conversation(s) and all their messages will be permanently deleted.';
  }

  @override
  String get smsDeleted => 'Selected conversations deleted';

  @override
  String get smsSelectMode => 'Select messages';

  @override
  String get smsReplyHint => 'Type your reply...';

  @override
  String get commonDelete => 'Delete';

  @override
  String get commonReset => 'Reset';

  @override
  String get commonCancel => 'Cancel';

  @override
  String commonError(String error) {
    return 'Error: $error';
  }

  @override
  String get commonSelect => 'Select';

  @override
  String get commonDeleteSelected => 'Delete selected';

  @override
  String get commonToday => 'Today';
}
