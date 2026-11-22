# Grav

Native macOS 14+ SwiftUI + AppKit menu-bar and hardware-notch telemetry companion for Google **Antigravity** (`/Applications/Antigravity.app`), powered by [NotchKit](https://github.com/duongductrong/NotchKit) (`1.3.0`).

Grav turns the MacBook hardware notch — and falls back cleanly to a standalone top-edge pill on external displays — into a 120Hz flight-deck telemetry island driven exclusively by real local Antigravity runtime files under `~/.gemini/antigravity/brain/`.

## Architecture

- **`Grav/App/`**: Accessory lifecycle (`LSUIElement = YES`), `AppDelegate`, `PreferencesStore` (`SMAppService.mainApp`), and native monochrome template `MenuBarController`.
- **`Grav/Core/Telemetry/`**: Event-driven, zero-mock local Antigravity ingestion engine:
  - `AntigravityAppDetector`: Bundle (`com.google.antigravity`) and `/Applications/Antigravity.app` detection, cached real icon extraction, window activation, and optional security-scoped bookmarking.
  - `ConversationDiscovery`: `DispatchSource.makeFileSystemObjectSource` directory watcher for `~/.gemini/antigravity/brain/<uuid>/.system_generated/logs/transcript.jsonl`.
  - `TranscriptTailer`: Swift `actor` maintaining persisted byte offsets, partial-line buffering, truncation/rotation recovery, and on-demand single-step lookups in `transcript_full.jsonl`.
  - `TaskLogTailer`: Incremental live tailer for `.system_generated/tasks/task-<id>.log` and `.system_generated/steps/<idx>/output.txt` with `ANSIStripper` normalization.
  - `DiffComputer` & `DestructiveCommandParser`: Real line-level LCS diff hunks (`+added / -removed`) for `edit_file`, `replace_file_content`, `multi_replace_file_content`, `write_file`, and shell `rm` / `git rm` / `unlink` path extraction.
  - `EventClassifier` & `AntigravityTelemetryStore`: Pure `Sendable` state machine (`idle -> thinking -> editing / runningCommand -> idle`) and `@MainActor @Observable` store with active-only idle decay (`< 0.5%` idle CPU).
- **`Grav/Features/Notch/`**: `NotchKit 1.3.0` single-shape morphing HUD (`NotchHUDCoordinator`, `CollapsedNotchView` via `NotchCutoutLayout` + CALayer `NotchBars`, and 3-tab `ExpandedNotchView` across `Live`, `Files`, and `Terminal` with `1`/`2`/`3`, `Esc`, and `⌘C` shortcuts).
- **`Grav/Features/Onboarding/`**: Dark Liquid Glass borderless floating onboarding window (`1060×720`–`1280×826`), 7-beat Glacial Teal-Cyan organic portal welcome choreography, 3-step live setup flow, and full-screen curved-arc notch arrival finale.
- **`Grav/Features/Settings/`**: Full Light/Dark adaptive macOS Settings window (`520×440`, unified titlebar).
- **`Grav/DesignSystem/`**: Aerospace Obsidian (`#05080C`) × Glacial Teal-Cyan (`#14B8A6` → `#38BDF8`) palette, continuous corner geometry tokens, Dark Liquid Glass primitives, and semantic telemetry indicators.

## Building & Testing

Requires macOS 14.0+ and Xcode 16+ (Swift 6 strict concurrency enabled).

```bash
# Regenerate Xcode project from project.yml (optional)
xcodegen generate

# Build Grav.app
xcodebuild -project Grav.xcodeproj -scheme Grav -configuration Debug -destination 'platform=macOS,arch=arm64' build

# Run XCTest unit suite
xcodebuild -project Grav.xcodeproj -scheme Grav -configuration Debug -destination 'platform=macOS,arch=arm64' test
```
