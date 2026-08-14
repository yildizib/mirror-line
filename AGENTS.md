# Git Workflow for Issue-Based Development

This project uses GitHub Issues to track work and implements a systematic branching strategy based on Gitflow, customized for this team's workflow. Release automation is handled by GitHub Actions workflows that trigger on version tags.

## ⚠️ Core Rule: No Direct Commits to `develop` or `main`

**IMPORTANT:** All commits MUST go through feature/fix/chore branches and Pull Requests:
- ❌ **Never** commit directly to `develop` or `main`
- ✅ **Always** create a branch: `feature/*`, `fix/*`, `bugfix/*`, `chore/*`, `hotfix/*`, `release/*`
- ✅ **Always** create a Pull Request before merging
- ✅ **Always** reference the issue ID in commits: `#ID: description`

**Why?** 
- Maintains clean branch history
- Enables code review via PRs
- Keeps develop/main as stable integration points
- Prevents accidental commits to production branches

**If you accidentally commit to develop:**
```bash
# Reset develop to remote
git checkout develop
git reset --hard origin/develop

# Create proper branch with the commit
git checkout -b feature/your-feature-ID
git cherry-pick <commit-hash>  # Or redo the work on the branch
git push -u origin feature/your-feature-ID
```

## Branch Strategy Overview

```
main (production)
  ↑
  └─── hotfix/* (critical production fixes)
        ↓
    develop (integration)
      ↑
      ├─── feature/* (new features)
      ├─── bugfix/* (non-critical bug fixes)
      ├─── fix/* (alias for bugfix)
      └─── release/* (release preparation)
```

## Branch Types & Naming

| Type | Pattern | From | Merges to | Purpose |
|------|---------|------|-----------|---------|
| **Feature** | `feature/short-slug-#ID` | develop | develop | New features, enhancements |
| **Bugfix** | `bugfix/short-slug-#ID` | develop | develop | Non-critical bug fixes |
| **Fix** | `fix/short-slug-#ID` | develop | develop | Alias for bugfix (use either) |
| **Hotfix** | `hotfix/short-slug-#ID` | main | main + develop | Critical production bugs |
| **Release** | `release/v#.#.#-#ID` | develop | main (via develop) | Release prep, versioning |

### Naming Convention
- Use kebab-case (hyphens, lowercase)
- Keep slug short & descriptive
- Include issue ID: `feature/auth-system-11`
- Examples: `feature/user-authentication-8`, `fix/memory-leak-12`, `hotfix/critical-crash-25`

## Workflow: Standard Task (Feature/Bugfix)

### 1. Create GitHub Issue
```bash
gh issue create --title "Brief title" \
  --body "## Problem\n... ## Solution\n... ## Testing\n..."
```

### 2. Create Branch from `develop`
```bash
git checkout develop && git pull origin develop
git checkout -b fix/short-slug-#ID  # or feature/...
```

### 3. Commit with Issue Reference
```bash
git add -A
git commit -m "#ID: Brief description

Detailed explanation of why this change was made..."
```
- Start with `#ID:` (GitHub auto-links)
- Use imperative mood: "Add", "Fix", "Update" (not "Added")
- Keep subject under 50 characters

### 4. Push & Create PR (target: develop)
```bash
git push -u origin fix/short-slug-#ID
gh pr create --title "Fix: Brief description" \
  --base develop \
  --body "## Summary\n... ## Related Issue\nFixes #ID"
```

### 5. Testing & Merge
- **Developer:** Create PR, request testing
- **User (Ibrahim):** Test on device
- **After verification:** Close issue, merge PR
```bash
gh issue close #ID
gh pr merge <PR#> --squash
```

### 6. Move to Next Task
```bash
git checkout develop && git pull origin develop
git checkout -b feature/next-slug-#ID
```

## Workflow: Release

For version releases, use semantic versioning (`v#.#.#`):

### Manual Release Process

```bash
# 1. Create release branch from develop
git checkout develop && git pull origin develop
git checkout -b release/v0.3.0-#ID

# 2. Update version (pubspec.yaml, CHANGELOG.md, etc.)
# version: 0.3.0+1
git add -A
git commit -m "chore(release): Bump version to v0.3.0

- Fixed watchdog interval (#10)
- Added exact alarm scheduling (#12)"

# 3. Push & create PR targeting main
git push -u origin release/v0.3.0-#ID
gh pr create --title "Release: v0.3.0" --base main \
  --body "## Release v0.3.0\n### Changes\n..."

# 4. After approval, merge to main
gh pr merge <PR#> --squash

# 5. Tag release (triggers GitHub Actions)
git checkout main && git pull origin main
git tag -a v0.3.0 -m "Release v0.3.0"
git push origin v0.3.0

# 6. Sync main back to develop
git checkout develop
git pull origin develop
git merge main
git push origin develop
```

**What GitHub Actions Does:**
- Detects tag (`v*`)
- Builds release APK
- Creates GitHub Release with notes
- Attaches APK to release

### Automated Release (Workflow Dispatch)

From GitHub UI:
- Actions → Android Release → Run workflow
- Enter version: `0.3.0` (without `v`)
- Actions handles versioning, tagging, and release

## Commit Message Format

```
#ID: One-line imperative statement

Detailed explanation of WHY (not WHAT).
Keep lines under 80 characters.

Related issues:
- Depends on #9
- Closes #8
```

**Rules:**
- ✅ Start with `#ID:` for auto-linking
- ✅ Imperative mood: "Add", "Fix", "Update"
- ✅ Explain WHY, not WHAT
- ✅ Reference related issues

## GitHub CLI Essentials

```bash
gh issue create --title "..." --body "..."  # Create issue
gh issue close #ID                          # Close issue
gh pr create --title "..." --base develop   # Create PR (target: develop)
gh pr merge #PR --squash                    # Merge PR
gh release view v0.3.0                      # View release
```

## Quick Example

```bash
# Create issue → gets #10
gh issue create --title "Fix watchdog" --body "..."

# Work on task
git checkout develop && git pull
git checkout -b fix/watchdog-interval-10
# ... make changes ...
git add -A && git commit -m "#10: Reduce watchdog interval to 5 min"

# Push & PR (target: develop)
git push -u origin fix/watchdog-interval-10
gh pr create --title "Fix: Watchdog interval" --base develop --body "..."

# After testing, close & merge
gh issue close #10
gh pr merge 11 --squash

# Next task
git checkout develop && git pull
git checkout -b feature/exact-alarms-12
```

## Branch Protection (Recommended)

For `main` and `develop` branches:
- ✅ Require pull request reviews
- ✅ Require branches up to date before merging
- ✅ Require status checks pass (CI/CD, tests)
- ✅ Dismiss stale PR approvals

## CI/CD Workflows

Located in `.github/workflows/`:
- **ci.yml:** Runs on every push/PR to main/develop (analyze, test)
- **android-release.yml:** Triggered by `v*` tag or manual dispatch

## Division of Labor

**Claude** handles implementation:
```
develop (pull) → new branch → implement → test → compile → commit → push
```

**User** handles reviews and merges:
```
PR review → approve → merge to develop
```

This keeps the mainline (`develop`/`main`) clean and ensures all changes are reviewed before landing. No direct commits to `develop`/`main` at any time.

---

# Release Workflow (Simple Explanation)

## Flow Summary

```
develop ──●──●──●──●──●──●──●──●── merge main (back-sync)
              \               /
               release/v0.3.0
                  │
                squash merge
                  ↓
main ──────────────S ← tag v0.3.0 → Actions → APK
```

In 3 sentences:
1. **Open a release branch from develop, bump the version, squash merge it into main**
2. **Tag main → GitHub Actions automatically builds the APK**
3. **Back-merge main into develop so develop stays up to date**

## Step by Step

### Starting state

```
develop:  A──B──C──D──E    (50 commits accumulated)
main:     A                  (old release)
```

Develop is ahead, main is behind. We need to release.

### Step 1 — Create release branch (from develop)

```
git checkout develop && git pull origin develop
git checkout -b release/v0.3.0-59
```

```
develop:  A──B──C──D──E
                 \
                  R      ← release/v0.3.0-59
```

### Step 2 — Version bump

```
# pubspec.yaml: 0.2.1+2 → 0.3.0+3
git add pubspec.yaml
git commit -m "chore(release): Bump version to v0.3.0"
```

Only `pubspec.yaml` changes. No other code changes.

### Step 3 — Create PR (target: main!)

```
git push -u origin release/v0.3.0-59
gh pr create --title "Release: v0.3.0" --base main --body "..."
```

**Important:** The PR target is **main** (not develop).

### Step 4 — Squash merge (into main)

```
gh pr merge <PR#> --squash --admin
```

```
develop:  A──B──C──D──E
main:     A──────────────S    ← S = squash (50 commits into one)
```

**Squash =** compresses 50 commits into a single commit, keeping main clean.

### Step 5 — Tag (on main)

```
git checkout main && git pull origin main
git tag -a v0.3.0 -m "Release v0.3.0"
git push origin v0.3.0
```

Pushing the tag triggers **GitHub Actions** (`android-release.yml`) automatically:
- Builds the APK
- Creates a GitHub Release
- Attaches the APK to the Release

### Step 6 — Back-merge (main → develop)

```
git checkout develop
git merge main --no-edit
git push origin develop
```

```
develop:  A──B──C──D──E──M    ← M = merge main
main:     A──────────────S
```

**Why?** Develop must always contain main. Otherwise the next release will have conflicts.

### Step 7 — Cleanup

```
git branch -d release/v0.3.0-59
git push origin --delete release/v0.3.0-59
```

## Version Number (Semantic Versioning)

```
v0.3.0+3
  ^  ^  ^
  │  │  └── patch: bug fix (0.3.1)
  │  └───── minor: new feature (0.3.0 → 0.4.0)
  └──────── major: breaking change (0.x → 1.0.0)
```

- Bug fix → patch bump (`0.3.0` → `0.3.1`)
- New feature → minor bump (`0.3.0` → `0.4.0`)
- Breaking change → major bump (`0.x` → `1.0.0`)

`pubspec.yaml` format: `version: MAJOR.MINOR.PATCH+BUILD_NUMBER`

## Key Points

- PR base = **main** (releases merge into main, not develop)
- Tag is placed **on main** (CI builds the release commit on main)
- Squash merge: main stays clean (50 commits → 1 commit)
- Develop back-merges main afterwards (Gitflow rule: develop ≥ main)
- Don't wait for builds — use `--admin --squash` to force merge
- `pubspec.lock` is never included in commits
- Release branch is deleted after the release is done (not permanent)

---
