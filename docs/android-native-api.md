# Android Native API

The channel is `io.github.yildizib.mirrorline/telephony`.

- `syncMirroringEligibility({enabled, role, paired})` persists lifecycle state
  and returns `initialized`, `enabled`, `role`, `paired`,
  `permissionsGranted`, `eligible`, and `networkMonitoringEligible`.
- `startListening` and `startService` return `{outcome, error}`. A successful
  synchronous platform request returns `start_requested`; it does not claim
  that Android completed service startup.
- `stopListening` and `stopService` persist the supplied lifecycle fields,
  stop the service, cancel watchdog work, clear buffered native events, and
  return `{outcome: stopped, error: null}`.
- `nativeEventsReady` enables FIFO event delivery. `nativeEventsNotReady` and
  `notReady` disable delivery and clear buffered events from the old lifecycle.

Every `onCall` event with state `RINGING`, `RINGING_UPDATE`, `ANSWERED`,
`MISSED`, or `ENDED` includes `callSessionId`. The identifier is stable for one
native call session and terminal events retain their original identifier even
when their call-log enrichment finishes after a newer call starts.
