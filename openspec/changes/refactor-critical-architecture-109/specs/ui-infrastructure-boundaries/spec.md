# UI infrastructure boundaries

## ADDED Requirements

### Requirement: UI infrastructure access is abstracted
UI screens MUST NOT call KeyStore, PermissionService, InstalledAppsChannel, NotificationService, or native channels directly. Feature controllers/gateways MUST expose testable interfaces and production adapters.

#### Scenario: UI uses platform gateway

- **WHEN** a screen requests identity, permission, or installed-app data
- **THEN** the request is made through an injectable feature gateway
