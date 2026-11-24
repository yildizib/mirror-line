## Why

MirrorLine's approved product direction is a server-mediated, end-to-end
encrypted synchronization service. The existing LAN/VPN transport cannot pair
devices on independent networks and does not provide the account, device,
mailbox, rotation, or audit contracts required for that product.

## What Changes

- Define the server-mediated identity, pairing, signed-envelope, replay,
  encrypted-mailbox, retention, key-lifecycle, session, and audit contracts.
- Define stable API groups and error codes before server or mobile runtime work.
- Set the approved product limits: one Main, up to five Sources, seven-day
  server mailbox retention, eight-day device replay records, and local-history
  choices of 7/30/90/180 days (30 by default).
- Update the bilingual product document and the wireframe manifest to the
  approved 97-screen future product.

## Capabilities

### New Capabilities

- `server-backed-e2e-sync`: Signed E2E relay envelopes, replay policy, mailbox
  retention, and local-history policy.
- `server-mediated-pairing`: Cross-network pairing transactions, proofs, and
  comparison confirmation.
- `device-key-lifecycle`: Registered device identities and key rotation.
- `security-audit-and-sessions`: Session semantics and retained security audit.
- `server-api-contract`: Versioned API groups and stable error codes.

## Impact

This change is contracts and documentation only. It intentionally does not
implement server endpoints, database migrations, mobile relay clients,
cryptographic primitives, push delivery, or the seven newly documented
wireframe screens. Those changes are sequenced as T2 through T17 below.

## Non-Goals

- Retaining any LAN, VPN, UDP beacon, subnet scanning, or direct socket path
  in the target product contract.
- Uploading private keys, decrypted content, or E2E session keys to the server.
- Claiming that the current repository implements these future contracts.
