import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mirrorline/features/settings/settings_controller.dart';

class _FakeNativeOperations implements SettingsNativeOperations {
  final calls = <String>[];

  @override
  Future<bool> hasKnownAutoStartSettings() async {
    calls.add('hasAutoStart');
    return true;
  }

  @override
  Future<bool> hasKnownBatterySaverSettings() async {
    calls.add('hasBatterySaver');
    return false;
  }

  @override
  Future<void> openNotificationListenerSettings() async {
    calls.add('openNotifications');
  }

  @override
  Future<void> openAutoStartSettings() async {
    calls.add('openAutoStart');
  }

  @override
  Future<void> openBatterySaverSettings() async {
    calls.add('openBatterySaver');
  }
}

void main() {
  test('routes native Settings operations through the UI controller', () async {
    final native = _FakeNativeOperations();
    final container = ProviderContainer(
      overrides: [
        settingsControllerProvider.overrideWith(
          (ref) => SettingsController(ref, native: native),
        ),
      ],
    );
    addTearDown(container.dispose);
    final controller = container.read(settingsControllerProvider);

    expect(await controller.hasKnownAutoStartSettings(), isTrue);
    expect(await controller.hasKnownBatterySaverSettings(), isFalse);
    await controller.openNotificationListenerSettings();
    await controller.openAutoStartSettings();
    await controller.openBatterySaverSettings();

    expect(native.calls, [
      'hasAutoStart',
      'hasBatterySaver',
      'openNotifications',
      'openAutoStart',
      'openBatterySaver',
    ]);
  });
}
