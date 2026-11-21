# MirrorLine Mobile User Flows

## 1. Launch, optional update check, and session routing

```mermaid
flowchart TD
    A[App opens] --> B[Read local session]
    B --> C[Check version in background]
    C -->|Failed or current| D[Continue normally]
    C -->|Update available| E{Version already deferred?}
    E -->|Yes| D
    E -->|No| F[Dismissible update banner]
    F -->|Update| G[Open store or download page]
    F -->|Later| H[Suppress this exact version]
    G --> D
    H --> D
    D --> I{Valid session?}
    I -->|No| J[Welcome]
    J --> K[Sign in]
    J --> L[Create account]
    K --> M[Authentication flow]
    L --> N[Registration flow]
    M --> O{Role assigned?}
    N --> O
    I -->|Yes| O
    O -->|Main| P[Main start]
    O -->|Source| Q[Source start]
    O -->|No| R[Choose role]
```

## 2. Registration and email verification

```mermaid
flowchart TD
    A[Welcome] --> B[Create account]
    B --> C[Email]
    C --> D[Password]
    D --> E[Confirm password]
    E --> F[Accept terms and privacy]
    F --> G[Submit]
    G -->|Field error| H[Inline error; preserve fields]
    H --> C
    G -->|Email exists| I[Account exists]
    I --> J[Sign in]
    I --> K[Forgot password]
    G -->|Connection error| L[Preserve form and retry]
    L --> G
    G -->|Success| M[Verification email sent]
    M --> N[Check verification]
    N -->|Not verified| O[Check again]
    N -->|Wrong email| P[Change email]
    N -->|Not received| Q[Resend with cooldown]
    Q --> M
    O -->|Verified| R[Start session]
    R --> S[Choose role]
```

## 3. Sign in and password reset

```mermaid
flowchart TD
    A[Welcome] --> B[Sign in]
    B --> C[Email and password]
    C --> D[Submit]
    D -->|Success| E{Role assigned?}
    E -->|No| F[Choose role]
    E -->|Yes| G[Role home]
    D -->|Wrong credentials| H[Inline form error]
    H --> C
    D -->|Email unverified| I[Verify email]
    I --> J[Resend verification]
    I --> K[Check again]
    K -->|Verified| D
    B --> L[Forgot password]
    L --> M[Enter email]
    M --> N[Send reset link]
    N --> O[Check email]
    O --> P[Create new password]
    P --> B
```

## 4. Main Phone setup and secure replacement

```mermaid
flowchart TD
    A[Set up as Main] --> B{Active Main state}
    B -->|None| C[Main notification permission]
    B -->|This device| D[Main home]
    B -->|Another device| E[Main already exists]
    E --> F[Keep existing Main]
    E --> G[Replace Main]
    G --> H[Explain consequences]
    H --> I[Reauthenticate]
    I -->|Failed| E
    I -->|Success| J[Final confirmation]
    J -->|Cancel| E
    J -->|Replace| K[Old Main and pairings invalidated]
    K --> C
    C --> L[Main ready]
    L --> M[Guide user to pair Sources]
    M --> D
```

## 5. Add Source from Main

```mermaid
flowchart TD
    A[Devices] --> B[Add Source]
    B --> C[Check pairing eligibility]
    C -->|Unavailable| D[Cannot start now]
    D --> E[Retry]
    E --> C
    C -->|5 of 5| F[Device limit reached]
    F --> G[Manage devices]
    G --> H[Remove a Source]
    H --> B
    C -->|Eligible| I[Pairing explanation]
    I --> J[Show QR and short code]
    J --> K[Wait for Source]
    K -->|Expired| L[Refresh code]
    L --> J
    K -->|Source found| M[Compare verification code]
    M -->|Mismatch| N[Cancel safely]
    M -->|Match| O[Review Source name]
    O --> P[Confirm pairing]
    P -->|Limit reached meanwhile| F
    P -->|Failed| Q[Reason and retry]
    P -->|Success| R[Source added]
    R --> S[Device detail]
```

## 6. Pair Source to Main

```mermaid
flowchart TD
    A[Set up as Source] --> B{Already paired?}
    B -->|Yes| C[Show current Main]
    C --> D[Block new scan]
    D --> E[Remove current connection]
    E --> F[Security warning]
    F -->|Cancel| C
    F -->|Continue| G[Reauthenticate]
    G -->|Failed| C
    G -->|Success| H[Connection removed]
    B -->|No| I[QR scanner]
    H --> I
    I -->|Camera denied| J[Explain and request camera]
    J --> I
    I -->|Invalid or expired| K[Request a new code]
    I -->|Valid| L[Compare verification code]
    L -->|Mismatch| M[Cancel]
    L -->|Match| N[Confirm this Main]
    N -->|Failed| O[Reason and retry]
    N -->|Success| P[Source permission setup]
```

## 7. Role-specific permissions

```mermaid
flowchart LR
    A[Main permission intro] --> B[Notification permission]
    B -->|Granted| C[Notifications active]
    B -->|Denied| D[Can enable later]
    C --> E[Main home]
    D --> E
```

```mermaid
flowchart TD
    A[Source permission overview] --> B[Call monitoring]
    B --> C[SMS read and reply]
    C --> D[Selected-app notification access]
    D --> E[Foreground-service notification]
    E --> F[Optional contacts]
    F --> G[Battery and auto-start recommendations]
    G --> H[Source home]
    H --> I{Any feature unavailable?}
    I -->|Yes| J[Needs attention]
    I -->|No| K[Protection active]
```

At every Source permission step, Granted enables the feature and Denied marks
only that feature Disabled or Limited. Pairing remains intact.

## 8. Main and Source navigation

```mermaid
flowchart LR
    A[Main] --> B[Inbox]
    A --> C[Devices]
    A --> D[Settings]
    B --> B1[All / Calls / SMS / Apps]
    B --> B2[Source filter]
    C --> C1[Source list 0–5]
    C --> C2[Add Source]
    C --> C3[Device detail and remove]
    D --> D1[Notifications]
    D --> D2[Privacy and appearance]
    D --> D3[Language]
    D --> D4[Storage and history]
    D --> D5[Account and security]
    D --> D6[Check for updates]
    D --> D7[Diagnostics]
    D --> D8[Replace Main / Sign out]
```

```mermaid
flowchart LR
    A[Source] --> B[Status]
    A --> C[Privacy]
    A --> D[Settings]
    B --> B1[Protection and connection]
    B --> B2[Call / SMS / app status]
    B --> B3[Missing permissions]
    C --> C1[Sharing categories]
    C --> C2[Selected apps]
    C --> C3[Content privacy]
    C --> C4[Pause temporarily]
    D --> D1[Main information]
    D --> D2[Android permissions]
    D --> D3[Battery and auto-start]
    D --> D4[Storage and language]
    D --> D5[Check for updates]
    D --> D6[Diagnostics]
    D --> D7[Remove connection / Sign out]
```

## 9. Update check

```mermaid
flowchart TD
    A[Settings] --> B[Check for updates]
    B --> C[Show installed version]
    C --> D[Checking]
    D -->|Current| E[MirrorLine is up to date]
    D -->|Failed| F[Inline error]
    F --> G[Retry]
    D -->|Available| H[Update information]
    H --> I[Update]
    H --> J[Later]
    I --> K[Open store or download page]
    J --> L[Suppress exact version]
    K --> M[Return to app]
    L --> M
```

## 10. Inbox and conversation pagination

```mermaid
flowchart TD
    A[Open Inbox] --> B[Initial skeleton]
    B -->|Has data| C[Combined feed]
    B -->|Empty| D[Empty state]
    B -->|Cached only| E[Cached feed and offline banner]
    B -->|No data and failed| F[Full-page retry]
    C --> G[Scroll down]
    G -->|More| H[Inline load-more skeleton]
    H -->|Success| C
    H -->|Failed| I[Inline retry row]
    H -->|End| J[End of list]
    C --> K[Pull to refresh]
    K -->|Success| C
    K -->|Failed| L[Keep feed and show warning]
    C --> M[Change Source filter]
    M --> B
```

```mermaid
flowchart TD
    A[SMS conversation] --> B[Recent messages]
    B --> C[Scroll upward]
    C -->|Older exist| D[Load above]
    D -->|Success| E[Preserve scroll anchor]
    D -->|Failed| F[Top retry row]
    B --> G[Compose reply]
    G --> H[Sending]
    H -->|Queued| I[Queued]
    H -->|Sent| J[Sent]
    H -->|Failed| K[Failed with retry]
    I -->|Expired| L[Expired]
    B --> M[New message arrives]
    M -->|At bottom| N[Append visibly]
    M -->|Reading history| O[New messages chip]
```

## 11. Event detail and feedback hierarchy

```mermaid
flowchart TD
    A[Inbox item] --> B{Type}
    B -->|Call| C[Call detail]
    C --> D[Source, person/number, time, duration, status]
    D --> E[Offer action only when valid]
    E -->|Stale| F[Action unavailable message]
    B -->|App notification| G[Notification detail]
    G --> H[Source, app, time, privacy state]
    H --> I{Reply supported?}
    I -->|Yes| J[Compose and send]
    I -->|No| K[View only]
    J -->|Failed| L[Inline retry]
```

```mermaid
flowchart TD
    A[Event] --> B{Can user continue?}
    B -->|Yes| C{Can content remain?}
    C -->|Yes| D[Snackbar, banner, or inline error]
    C -->|No| E[Empty/error state with retry]
    B -->|No| F{Security-sensitive?}
    F -->|Yes| G[Confirmation and reauthentication]
    F -->|No| H[Full-page resolution state]
```
