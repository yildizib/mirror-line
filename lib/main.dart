import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logger/logger.dart';

import 'app.dart';
import 'services/notification_service.dart';
import 'services/permission_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  try {
    await NotificationService.init();
  } catch (e) {
    Logger().e('NotificationService init failed: $e');
  }

  try {
    await PermissionService.requestNotifications();
  } catch (e) {
    Logger().e('Notification permission request failed: $e');
  }

  runApp(const ProviderScope(child: MirrorLineApp()));
}
