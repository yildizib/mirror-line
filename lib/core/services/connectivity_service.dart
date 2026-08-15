import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:logger/logger.dart';

class ConnectivityService {
  final Connectivity _connectivity = Connectivity();
  StreamSubscription<List<ConnectivityResult>>? _subscription;
  void Function(bool isOnline)? onChanged;

  ConnectivityService({this.onChanged});

  void startListening() {
    try {
      _subscription = _connectivity.onConnectivityChanged.listen((results) {
        final isOnline = results.any(
          (r) =>
              r == ConnectivityResult.wifi ||
              r == ConnectivityResult.ethernet ||
              r == ConnectivityResult.mobile,
        );
        onChanged?.call(isOnline);
      });
    } catch (e) {
      Logger().e('Connectivity listen failed: $e');
    }
  }

  Future<bool> isOnline() async {
    try {
      final result = await _connectivity.checkConnectivity();
      return result.any(
        (r) =>
            r == ConnectivityResult.wifi ||
            r == ConnectivityResult.ethernet ||
            r == ConnectivityResult.mobile,
      );
    } catch (_) {
      return true;
    }
  }

  void stopListening() {
    _subscription?.cancel();
    _subscription = null;
    onChanged = null;
  }
}
