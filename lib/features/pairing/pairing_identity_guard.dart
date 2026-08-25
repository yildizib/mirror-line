bool isValidRemoteIdentity({
  required String remoteId,
  required String remotePublicKey,
  required String localId,
  required String localPublicKey,
}) {
  if (remoteId.isEmpty || remotePublicKey.isEmpty) return false;
  if (localId.isEmpty || localPublicKey.isEmpty) return false;
  return remoteId != localId && remotePublicKey != localPublicKey;
}
