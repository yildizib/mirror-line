import 'package:flutter/material.dart';

class ConnectionBanner extends StatelessWidget {
  final bool isConnected;

  const ConnectionBanner({required this.isConnected, super.key});

  @override
  Widget build(BuildContext context) {
    if (isConnected) return const SizedBox.shrink();

    return Container(
      width: double.infinity,
      color: Colors.orange[100],
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
      child: Row(
        children: [
          Icon(Icons.wifi_off, size: 18, color: Colors.orange[800]),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Aynı ağda değilsiniz. Senkronizasyon duraklatıldı.',
              style: TextStyle(fontSize: 13, color: Colors.orange[900]),
            ),
          ),
        ],
      ),
    );
  }
}
