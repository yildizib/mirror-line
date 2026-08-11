<!-- rtk-instructions v2 -->
# RTK (Rust Token Killer) - Token-Optimized Commands

## Golden Rule

**Always prefix commands with `rtk`**. If RTK has a dedicated filter, it uses it. If not, it passes through unchanged. This means RTK is always safe to use.

**Important**: Even in command chains with `&&`, use `rtk`:
```bash
# ❌ Wrong
git add . && git commit -m "msg" && git push

# ✅ Correct
rtk git add . && rtk git commit -m "msg" && rtk git push
```

## RTK Commands by Workflow

### Build & Compile (80-90% savings)
```bash
rtk cargo build         # Cargo build output
rtk cargo check         # Cargo check output
rtk cargo clippy        # Clippy warnings grouped by file (80%)
rtk tsc                 # TypeScript errors grouped by file/code (83%)
rtk lint                # ESLint/Biome violations grouped (84%)
rtk prettier --check    # Files needing format only (70%)
rtk next build          # Next.js build with route metrics (87%)
```

### Test (60-99% savings)
```bash
rtk cargo test          # Cargo test failures only (90%)
rtk go test             # Go test failures only (90%)
rtk jest                # Jest failures only (99.5%)
rtk vitest              # Vitest failures only (99.5%)
rtk playwright test     # Playwright failures only (94%)
rtk pytest              # Python test failures only (90%)
rtk rake test           # Ruby test failures only (90%)
rtk rspec               # RSpec test failures only (60%)
rtk test <cmd>          # Generic test wrapper - failures only
```

### Git (59-80% savings)
```bash
rtk git status          # Compact status
rtk git log             # Compact log (works with all git flags)
rtk git diff            # Compact diff (80%)
rtk git show            # Compact show (80%)
rtk git add             # Ultra-compact confirmations (59%)
rtk git commit          # Ultra-compact confirmations (59%)
rtk git push            # Ultra-compact confirmations
rtk git pull            # Ultra-compact confirmations
rtk git branch          # Compact branch list
rtk git fetch           # Compact fetch
rtk git stash           # Compact stash
rtk git worktree        # Compact worktree
```

Note: Git passthrough works for ALL subcommands, even those not explicitly listed.

### GitHub (26-87% savings)
```bash
rtk gh pr view <num>    # Compact PR view (87%)
rtk gh pr checks        # Compact PR checks (79%)
rtk gh run list         # Compact workflow runs (82%)
rtk gh issue list       # Compact issue list (80%)
rtk gh api              # Compact API responses (26%)
```

### JavaScript/TypeScript Tooling (70-90% savings)
```bash
rtk pnpm list           # Compact dependency tree (70%)
rtk pnpm outdated       # Compact outdated packages (80%)
rtk pnpm install        # Compact install output (90%)
rtk npm run <script>    # Compact npm script output
rtk npx <cmd>           # Compact npx command output
rtk prisma              # Prisma without ASCII art (88%)
```

### Files & Search (60-75% savings)
```bash
rtk ls <path>           # Tree format, compact (65%)
rtk read <file>         # Code reading with filtering (60%)
rtk grep <pattern>      # Search grouped by file (75%). Format flags (-c, -l, -L, -o, -Z) run raw.
rtk find <pattern>      # Find grouped by directory (70%)
```

### Analysis & Debug (70-90% savings)
```bash
rtk err <cmd>           # Filter errors only from any command
rtk log <file>          # Deduplicated logs with counts
rtk json <file>         # JSON structure without values
rtk deps                # Dependency overview
rtk env                 # Environment variables compact
rtk summary <cmd>       # Smart summary of command output
rtk diff                # Ultra-compact diffs
```

### Infrastructure (85% savings)
```bash
rtk docker ps           # Compact container list
rtk docker images       # Compact image list
rtk docker logs <c>     # Deduplicated logs
rtk kubectl get         # Compact resource list
rtk kubectl logs        # Deduplicated pod logs
```

### Network (65-70% savings)
```bash
rtk curl <url>          # Compact HTTP responses (70%)
rtk wget <url>          # Compact download output (65%)
```

### Meta Commands
```bash
rtk gain                # View token savings statistics
rtk gain --history      # View command history with savings
rtk discover            # Analyze Claude Code sessions for missed RTK usage
rtk proxy <cmd>         # Run command without filtering (for debugging)
rtk init                # Add RTK instructions to CLAUDE.md
rtk init --global       # Add RTK to ~/.claude/CLAUDE.md
```

## Token Savings Overview

| Category | Commands | Typical Savings |
|----------|----------|-----------------|
| Tests | vitest, playwright, cargo test | 90-99% |
| Build | next, tsc, lint, prettier | 70-87% |
| Git | status, log, diff, add, commit | 59-80% |
| GitHub | gh pr, gh run, gh issue | 26-87% |
| Package Managers | pnpm, npm, npx | 70-90% |
| Files | ls, read, grep, find | 60-75% |
| Infrastructure | docker, kubectl | 85% |
| Network | curl, wget | 65-70% |

Overall average: **60-90% token reduction** on common development operations.
<!-- /rtk-instructions -->

---

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

---
