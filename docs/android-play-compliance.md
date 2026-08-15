# Android Play Compliance

MirrorLine uses the `remoteMessaging` foreground-service type to maintain the
user-enabled, cross-device mirroring connection. A persistent notification is
shown while mirroring is active, and native lifecycle policy prevents the
service from starting unless the device is enabled, paired, in the source role,
and has all required runtime permissions.

The app does not request exact-alarm, `MANAGE_OWN_CALLS`, phone-call foreground
service, or broad package-query access. Call, SMS, contacts, and notification
access are used only for the mirroring features the user enables. Launchable
apps are discovered through a scoped manifest query. App backup and device
transfer are disabled. Both credential-protected and device-protected files,
databases, preferences, roots, and valid external storage domains are explicitly
excluded by the Android backup rules. Lifecycle preferences contain only
initialized, enabled, role, and paired flags and never credentials or pairing
secrets.
