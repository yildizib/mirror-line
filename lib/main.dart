import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logger/logger.dart';

import 'app.dart';
import 'services/notification_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  try {
    await NotificationService.init();
  } catch (e) {
    Logger().e('NotificationService init failed: $e');
  }

  // Notification permission is requested from HomeScreen after its first
  // frame, not here -- so the user sees the splash screen and app UI
  // before any system permission dialog pops up.
  runApp(const ProviderScope(child: MirrorLineApp()));
}
