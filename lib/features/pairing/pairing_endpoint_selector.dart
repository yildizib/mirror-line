import 'package:mirrorline/features/connection/connection_endpoint_guard.dart';

enum PairingEndpointStage { request, accept }

enum PairingEndpointIssue {
  invalidClaim,
  locallyOwnedClaim,
  staleClaim,
  noUsableEndpoint,
  localInventoryUnavailable,
}

class PairingEndpointDiagnostic {
  final PairingEndpointStage stage;
  final PairingEndpointIssue issue;

  const PairingEndpointDiagnostic({required this.stage, required this.issue});
}

class PairingEndpointSelection {
  final String? ip;
  final PairingEndpointDiagnostic? diagnostic;

  const PairingEndpointSelection({this.ip, this.diagnostic});

  bool get isUsable => ip != null;
}

PairingEndpointSelection selectPairingEndpoint({
  required PairingEndpointStage stage,
  required Object? claimedIp,
  required String? liveIp,
  required String? fallbackIp,
  required int port,
  required Iterable<String> localIps,
}) {
  final claim = validateEndpoint(
    ip: claimedIp is String ? claimedIp : '',
    port: port,
    localIps: localIps,
  );
  final live = validateEndpoint(
    ip: liveIp ?? '',
    port: port,
    localIps: localIps,
  );

  if (claim.isUsable) {
    final differsFromLive =
        live.isUsable &&
        !areSameIpAddresses(claim.normalizedIp!, live.normalizedIp!);
    return PairingEndpointSelection(
      ip: claim.normalizedIp,
      diagnostic: differsFromLive
          ? PairingEndpointDiagnostic(
              stage: stage,
              issue: PairingEndpointIssue.staleClaim,
            )
          : null,
    );
  }

  final issue = claim.rejectionReason == EndpointRejectionReason.locallyOwned
      ? PairingEndpointIssue.locallyOwnedClaim
      : PairingEndpointIssue.invalidClaim;
  if (live.isUsable) {
    return PairingEndpointSelection(
      ip: live.normalizedIp,
      diagnostic: PairingEndpointDiagnostic(stage: stage, issue: issue),
    );
  }

  final fallback = validateEndpoint(
    ip: fallbackIp ?? '',
    port: port,
    localIps: localIps,
  );
  if (fallback.isUsable) {
    return PairingEndpointSelection(
      ip: fallback.normalizedIp,
      diagnostic: PairingEndpointDiagnostic(stage: stage, issue: issue),
    );
  }

  return PairingEndpointSelection(
    diagnostic: PairingEndpointDiagnostic(
      stage: stage,
      issue: PairingEndpointIssue.noUsableEndpoint,
    ),
  );
}
