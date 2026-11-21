# MirrorLine Component Contracts

All components inherit tokens from `00_DESIGN.md`. Components must expose the
states listed here without changing layout unexpectedly.

## App shell

### `MirrorTopBar`

- Optional back button, one-line title, and at most two trailing actions.
- Back target is 48 × 48 px.
- No centered logo except on Launch and Welcome.

### `RoleBottomNavigation`

- Main items: Inbox, Devices, Settings.
- Source items: Status, Privacy, Settings.
- Icon plus visible label for every destination.
- Selected state uses Forest Signal and Forest Wash; no animated pill travel.

## Authentication

### `AuthTextField`

- Label above, input, helper/error below.
- States: idle, focused, valid, invalid, disabled.
- Password variant includes accessible show/hide control.
- Do not clear text after unrelated submission failure.

### `PasswordRequirements`

- Shows only actual rules using text plus pass/pending icons.
- Updates while typing.
- Never represent strength using color alone.

### `VerificationPanel`

- Shows target email, check-again primary action, resend secondary action,
  change-email link, and cooldown label.
- States: pending, checking, resend cooldown, expired, verified, failed.

## Device and pairing

### `DeviceQuotaHeader`

- Displays the received value, such as `4 / 5 Kaynak Telefon`.
- States: available, limit reached, unknown/loading, unavailable.
- The visual count never independently decides eligibility.

### `DeviceRow`

- Leading device icon; device name and short metadata; trailing status and
  chevron/action.
- States: healthy, limited, inactive, disconnected, pending removal.
- Status always has icon and text.

### `SourceBadge`

- Compact pill containing a recognizable Source name.
- Appears on every Main event and conversation header.
- Truncates only after preserving a unique leading portion; full label remains
  accessible.

### `PairingCodePanel`

- High-contrast QR region, large short code, expiration, refresh, and cancel.
- Verification code uses Geist Mono.
- States: active, expiring, expired, refreshing, failed.
- Never show a fake QR placeholder in the accepted screen set; use a clearly
  marked wireframe QR pattern if no real data exists.

### `VerificationComparison`

- Large readable code, device names, Match primary action, Does not match
  secondary destructive-safe action.
- Both actions remain visible without scrolling on common Android heights.

## Permissions and status

### `PermissionRow`

- Leading capability icon; title and plain-language purpose; trailing status.
- Optional action below or trailing: Allow, Open Settings, Try again, Skip.
- States: not requested, granted, denied, needs settings, unavailable.

### `FeatureStatusRow`

- Used on Source Status and permission summary.
- Status vocabulary: Active, Limited, Disabled, Needs attention, Unavailable.
- Color is supplementary to icon and label.

### `AttentionBanner`

- One concise problem statement, affected-feature count, and one recovery
  action. Expanded detail belongs on a separate screen.
- Never blocks navigation.

## Feeds and conversations

### `EventRow`

- Source badge, event icon, primary identity/app, summary, timestamp, and state.
- Content may be hidden by privacy settings; layout must remain stable.
- Variants: call, SMS, app notification.

### `FilterBar`

- Horizontally scrollable only within the chip row, never at page level.
- Type chips: All, Calls, SMS, Apps.
- Source selector opens a bottom sheet with All Sources and individual Sources.
- Active filters provide a clear reset action.

### `PaginationFooter`

- Variants: row-shaped skeleton, inline error with Retry, End of list.
- Never replaces already loaded content.

### `ConversationPaginationHeader`

- Appears above the oldest visible message.
- Loading, retry, and beginning-of-conversation variants.
- Insertion of older items preserves the visible anchor.

### `MessageBubble`

- Direction, text, timestamp, and delivery status.
- Delivery states: Sending, Queued, Sent, Failed, Expired.
- Failed contains Retry; Expired contains an explanation action, not Retry by
  default.

### `NewMessagesChip`

- Appears above the composer when the user is reading history.
- Shows count when available and scrolls to the latest message.

## Settings

### `SettingsSection`

- Section heading plus divider-based rows; no outer card unless the section is
  a security warning.

### `SettingsRow`

- Icon, title, optional summary/current value, and chevron or control.
- Minimum 56 px height and 48 px interaction target.
- Destructive rows use Danger Ink text but no filled red background until the
  confirmation step.

### `UpdateBanner`

- Version summary with Update and Later.
- Dismissible and never modal.
- Later suppresses only the exact offered version.

### `UpdateStatusPanel`

- Installed version is always visible.
- States: checking, current, available, failed.
- Available includes Update and Later; failed includes Retry.

## Feedback and confirmation

### `InlineError`

- Specific issue, retained context, one recovery action where possible.
- Appears next to the failed field, row, or pagination boundary.

### `PersistentBanner`

- Used for cached/offline data, Source needs-attention, or update availability.
- Does not cover navigation or primary actions.

### `SecurityConfirmationDialog`

- Verb-led title, concise irreversible consequences, Cancel, and explicit
  destructive action.
- Destructive action is never the default focused button.
- Main replacement and Source unpairing require reauthentication before final
  confirmation.

### `Skeleton`

- Matches final geometry for auth form, event row, device row, and message.
- Low-contrast shimmer only; no central spinner for page loading.
