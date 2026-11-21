# MirrorLine State and Error Matrix

## Global presentation rules

| Situation | Presentation | Preserve content? | Primary recovery |
|---|---|---:|---|
| Short success | Snackbar | Yes | None |
| Recoverable row/action failure | Inline error | Yes | Retry |
| Persistent attention | Banner | Yes | Open resolution |
| No usable content | Full-page state | No content exists | Retry or sign in |
| Security-sensitive change | Reauthentication + dialog | Yes until confirmed | Confirm or cancel |
| Destructive failure | Dialog/inline result | Yes | Retry or cancel |

## Authentication

| State/error | UI response | Notes |
|---|---|---|
| Signed out | Welcome with Sign in and Create account | Neither action is hidden |
| Empty required field | Field error | Validate on submit and after blur |
| Invalid email | Email field error | Preserve other fields |
| Weak password | Requirement list plus field error | Show only actual rules |
| Password mismatch | Confirmation field error | Keep both values |
| Terms not accepted | Checkbox/group error | Focus error group |
| Email already used | Inline form banner | Offer Sign in and Forgot password |
| Wrong credentials | Form-level error | Do not identify which credential failed |
| Offline/connection error | Inline banner | Preserve all safe values |
| Verification pending | Dedicated screen | Check again, resend, change email |
| Resend cooldown | Disabled resend with countdown text | Check again remains available |
| Verification expired | Inline warning | Resend verification |
| Reset link expired | Full form message | Request a new reset link |
| Registration verified | Success status then role selection | No decorative celebration |

## Role and Main replacement

| State/error | UI response | Primary action |
|---|---|---|
| No role | Role selection | Choose Main or Source |
| Another Main exists | Security explanation | Keep current Main / Replace Main |
| Reauthentication failed | Inline password error | Retry |
| Replacement processing | Disable repeated submit | Keep screen visible |
| Replacement failed | Dialog/inline error | Retry or cancel |
| Replacement complete | Main ready state | Pair Sources |

## Pairing and quota

| State/error | UI response | Primary action |
|---|---|---|
| Eligibility checking | Device-list skeleton | Wait |
| Eligibility unavailable | Inline/full section error | Retry |
| 5 of 5 | Limit-reached state | Manage devices |
| Eligible | Pairing introduction | Continue |
| Code active | QR + short code + expiry | Cancel |
| Code expiring | Warning label | Refresh when expired |
| Code expired | Disabled code panel | Generate new code |
| Camera denied once | Explanation | Allow camera |
| Camera permanently denied | Explanation | Open Settings |
| Invalid code | Inline code error | Re-enter/request new code |
| Verification mismatch | Security warning | Cancel pairing |
| Pairing rejected | Failure screen | Retry or cancel |
| Pairing timed out | Failure screen | Retry |
| Limit reached during completion | Limit screen | Manage devices |
| Pairing success | Success screen | View device / Set permissions |
| Source already paired | Blocked scanner state | Remove current connection |
| Unpair failed | Preserve current pairing | Retry |

## Permissions and Source capabilities

| Permission/capability state | UI label | Behavior |
|---|---|---|
| Not requested | Set up | Offer rationale and action |
| Granted | Active | Show success status |
| Denied | Disabled | Explain affected feature; continue allowed |
| Permanently denied | Needs Settings | Open system settings |
| OS/policy unavailable | Unavailable | Honest explanation; no retry loop |
| Optional skipped | Not enabled | Continue without warning severity |
| Battery optimized | Recommended action | Feature may be Limited |
| Auto-start unavailable | Not available on this device | Do not show broken action |
| One or more critical features disabled | Needs attention | Source Home banner |
| All enabled | Protection active | Normal Source Home |

## Inbox, lists, and pagination

| State/error | UI response | Preserve content? |
|---|---|---:|
| Initial loading | Layout-matched skeletons | N/A |
| Loaded | Feed/list | Yes |
| Empty | Specific empty state | N/A |
| Cached but refresh failed | Cached list + offline banner | Yes |
| Initial failure without cache | Full-page error | No |
| Pull refresh | Native refresh indicator | Yes |
| Refresh failed | Snackbar/banner | Yes |
| Loading next page | Inline footer skeleton | Yes |
| Next page failed | Inline Retry footer | Yes |
| End reached | Quiet end label | Yes |
| Filter returns empty | Filter-specific empty state | N/A |

## Conversation and outgoing actions

| State/error | UI response | Recovery |
|---|---|---|
| Loading older messages | Header skeleton | Wait |
| Older-page failure | Header Retry row | Retry |
| New message while at bottom | Append normally | None |
| New message while reading history | New messages chip | Jump to latest |
| Sending | Subtle pending status | Wait |
| Queued | Queued label and explanation | None by default |
| Sent | Sent label | None |
| Failed | Failed label | Retry |
| Expired | Expired label | Explain; compose again if relevant |
| Remote action no longer valid | Non-blocking explanation | Return to detail |

## Update check

| State/error | Automatic check | Manual Settings check |
|---|---|---|
| Checking | No blocking UI | Inline checking state |
| Current | No message | Up-to-date confirmation |
| Available, not deferred | Dismissible banner | Update detail |
| Available, exact version deferred | No message | Still visible when manually checked |
| Check failed | Silent | Inline error + Retry |
| User chooses Later | Suppress exact version | Return to app |
| User chooses Update | Open external destination | App remains usable on return |

## Settings and destructive actions

| Action | Required protection | Completion feedback |
|---|---|---|
| Clear local history | Confirmation | Snackbar/result state |
| Remove Source from Main | Confirmation | Device removed state |
| Remove Main from Source | Reauthentication + confirmation | Unpaired Source state |
| Replace Main | Consequence screen + reauthentication + final confirmation | Main ready state |
| Sign out | Confirmation with role-specific consequences | Welcome screen |
