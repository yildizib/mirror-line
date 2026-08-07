import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';

class ConnectivityService {
  final Connectivity _connectivity = Connectivity();
  StreamSubscription<List<ConnectivityResult>>? _subscription;
  void Function(bool isOnline)? onChanged;

  ConnectivityService({this.onChanged});

  void startListening() {
    _subscription = _connectivity.onConnectivityChanged.listen((results) {
      final isOnline = results.any((r) =>
          r == ConnectivityResult.wifi ||
          r == ConnectivityResult.ethernet ||
          r == ConnectivityResult.mobile);
      onChanged?.call(isOnline);
    });
  }

  Future<bool> isOnline() async {
    final result = await _connectivity.checkConnectivity();
    return result.any((r) =>
        r == ConnectivityResult.wifi ||
        r == ConnectivityResult.ethernet ||
        r == ConnectivityResult.mobile);
  }

  void stopListening() {
    _subscription?.cancel();
    _subscription = null;
  }
}