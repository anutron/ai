---
name: disk-cleanup
description: Scan local disk for large storage consumers and identify cleanup opportunities. Read-only — never deletes without explicit approval.
---

# Disk Cleanup

Scan this Mac for hidden storage hogs: caches, build artifacts, old toolchain versions, logs, and more.

## Instructions

**User input**: $ARGUMENTS

### Step 1: Disk Overview

Run `df -H /` to show total/used/free space, then `diskutil apfs list` to get true APFS container-level free space.

### Step 2: Scan Known Targets

Measure each of these directories with `du -sm <path> 2>/dev/null`. Skip any that don't exist. Only report items >= 100 MB (or user-specified threshold).

**Known targets to scan:**

| Label | Path |
|---|---|
| Homebrew cache | ~/Library/Caches/Homebrew |
| npm cache | ~/.npm |
| yarn cache | ~/Library/Caches/Yarn |
| pip cache | ~/Library/Caches/pip |
| CocoaPods cache | ~/Library/Caches/CocoaPods |
| Xcode DerivedData | ~/Library/Developer/Xcode/DerivedData |
| Xcode Archives | ~/Library/Developer/Xcode/Archives |
| Xcode iOS DeviceSupport | ~/Library/Developer/Xcode/iOS DeviceSupport |
| Xcode watchOS DeviceSupport | ~/Library/Developer/Xcode/watchOS DeviceSupport |
| CoreSimulator Devices | ~/Library/Developer/CoreSimulator/Devices |
| Docker data | ~/Library/Containers/com.docker.docker |
| OrbStack data | ~/Library/Group Containers/HUAQ24HBR6.dev.orbstack |
| Trash | ~/.Trash |
| Logs | ~/Library/Logs |
| Claude app data | ~/Library/Application Support/Claude |
| Claude worktrees | ~/.claude |
| Gradle cache | ~/.gradle |
| Maven cache | ~/.m2 |
| Go modules | ~/go |
| Cargo cache | ~/.cargo |
| Ruby gems | ~/.gem |
| rbenv versions | ~/.rbenv/versions |
| nodenv versions | ~/.nodenv/versions |
| nvm versions | ~/.nvm/versions |
| pyenv versions | ~/.pyenv/versions |
| asdf versions | ~/.asdf |
| Spotify cache | ~/Library/Application Support/Spotify/PersistentCache |
| Slack cache | ~/Library/Application Support/Slack |
| Chrome cache | ~/Library/Application Support/Google/Chrome |
| Safari cache | ~/Library/Caches/com.apple.Safari |
| Granola cache | ~/Library/Application Support/Granola |
| Downloads | ~/Downloads |
| Desktop | ~/Desktop |
| Movies | ~/Movies |
| Android SDK | ~/Library/Android/sdk |
| Devbox cache | ~/.cache/devbox |
| Nix store | /nix |
| macOS Software Updates | /Library/Updates |
| System caches | /Library/Caches |
| Photos Library | ~/Pictures/Photos Library.photoslibrary |

### Step 3: Scan Top-Level Home

Also scan `~/` for any large directories NOT already covered by known targets. Use `du -sm ~/* ~/.* 2>/dev/null` and filter to >= 100 MB items not already reported.

### Step 4: Present Results

1. Show disk overview (total/used/free)
2. Present results as a sorted table (largest first) with label, size, and path
3. Highlight surprises — things the user likely doesn't know about
4. For each category, explain what it is and whether it's safe to clean
5. **NEVER delete anything** — only suggest what could be cleaned and the commands to do it
6. Wait for explicit approval before running any cleanup commands

### Gotchas

- **Docker Desktop vs OrbStack**: `~/Library/Containers/com.docker.docker` is Docker Desktop data. If the user runs OrbStack, this entire directory is dead weight (often 50+ GB). OrbStack stores its data in `~/Library/Group Containers/HUAQ24HBR6.dev.orbstack`. Check which runtime is active before suggesting `docker system prune` — prune only works on the active runtime.
- **Photos Library**: `~/Pictures/Photos Library.photoslibrary` can be 20-30 GB even if the user never uses Photos.app. Always flag it and ask if they use Photos.app.
- **asdf versions**: `~/.asdf` can accumulate old language versions. Run `asdf list` to show installed versions — starred ones are active, the rest can be uninstalled.
- **Nix store**: `nix-collect-garbage -d` may not be on PATH. Fall back to `/nix/var/nix/profiles/default/bin/nix-collect-garbage -d`.
- **APFS reporting**: `df -H` shows per-volume usage. Use `diskutil apfs list` to see true container-level free space.
- **Claude worktrees**: `~/.claude` can accumulate worktrees from Claude Code sessions. Check `~/.claude/worktrees/` for stale worktrees.

### Cleanup Command Reference (only run with approval)

| Category | Cleanup Command |
|---|---|
| Homebrew cache | `brew cleanup --prune=all` |
| npm cache | `npm cache clean --force` |
| Xcode DerivedData | `rm -rf ~/Library/Developer/Xcode/DerivedData/*` |
| Xcode Archives | `rm -rf ~/Library/Developer/Xcode/Archives/*` |
| Xcode iOS DeviceSupport | `rm -rf ~/Library/Developer/Xcode/iOS\ DeviceSupport/*` |
| CoreSimulator | `xcrun simctl delete unavailable` |
| Docker (active runtime) | `docker system prune -a` |
| Docker Desktop (if using OrbStack) | `rm -rf ~/Library/Containers/com.docker.docker` |
| Trash | `rm -rf ~/.Trash/*` |
| pip cache | `pip cache purge` |
| yarn cache | `yarn cache clean` |
| Go modules | `go clean -modcache` |
| Gradle cache | `rm -rf ~/.gradle/caches` |
| Nix garbage | `nix-collect-garbage -d` (or `/nix/var/nix/profiles/default/bin/nix-collect-garbage -d`) |
| asdf old versions | `asdf uninstall <plugin> <version>` for each non-active version |
| CocoaPods cache | `pod cache clean --all` |
| Android SDK (if unused) | `rm -rf ~/Library/Android/sdk ~/.android` |
| Photos Library (if unused) | `rm -rf ~/Pictures/Photos\ Library.photoslibrary` |
| Claude stale worktrees | Remove directories in `~/.claude/worktrees/` |
