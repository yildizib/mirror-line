# UI infrastructure boundaries

## Requirements

- UI screens MUST NOT call KeyStore, PermissionService, InstalledAppsChannel, NotificationService or native channels directly.
- Feature controllers/gateways MUST expose testable interfaces and production adapters.
- Existing user-visible permission, navigation and installed-app behavior MUST remain unchanged.
