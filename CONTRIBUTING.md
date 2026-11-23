# Contributing to Grav

Thanks for taking the time to contribute. Grav is built to feel fast, quiet, and native on macOS—any help keeping it that way is appreciated.

## Setup

You'll need:

- **macOS 14.0+**
- **Xcode 16+** (Swift 6 strict concurrency is enabled across the project)
- **[XcodeGen](https://github.com/yonaskolb/XcodeGen)** (only needed if you change `project.yml`)

Clone the repo and make sure the test suite passes before making changes:

```bash
xcodebuild -project Grav.xcodeproj -scheme Grav -configuration Debug test
```

## Project structure

- `Grav/App/` — App lifecycle, menu bar controller, global hotkeys, and preferences.
- `Grav/Core/Telemetry/` — Local Antigravity watchers (`kqueue`, transcript streaming, SQLite WAL probe, diff engine, and state store).
- `Grav/Core/Pets/` — Codex Mini Pet catalog client and sprite sheet slicer.
- `Grav/Features/Notch/` — Collapsed pill, expanded Notch HUD tabs, drop shelf composer, and Spotlight search.
- `Grav/Features/Pets/`, `Settings/`, `Onboarding/` — Desktop pet overlay, preferences window, and onboarding flow.
- `GravTests/` — XCTest unit tests for parsing, diffing, caching, and state transitions.

## Guidelines

- **Keep it light.** Avoid polling timers and heavy work on `@MainActor`. Prefer `DispatchSource` file watchers, off-main parsing, and CoreAnimation layers (`CALayer` / `CAShapeLayer` / `CAGradientLayer`) for continuous animations so idle CPU stays near 0%.
- **Respect Swift 6 concurrency.** New code should compile cleanly with strict concurrency checks enabled and no data-race warnings.
- **Test your changes.** Add or update unit tests in `GravTests/` whenever you touch telemetry parsing, caching, or state machine logic.
- **Keep UI native.** Match macOS spacing, typography, and `Reduce Motion` behavior.

## Submitting a pull request

1. Fork the repository and create a branch from `main` (for example, `fix/notch-drop-focus` or `feat/compact-diff`).
2. Keep each PR focused on one change with clear commit messages.
3. Run the full test suite (`xcodebuild test`) and verify a Release build compiles cleanly.
4. For visual or animation changes, attach a short screen recording or before/after screenshot in the PR description.
5. Never commit personal Antigravity transcripts, API keys, or local build artifacts.

## Reporting bugs

When opening an issue, please include:

- Your macOS version and Mac model (built-in notch or external display).
- Steps to reproduce what happened.
- Screenshots, crash logs, or a quick `sample` / Activity Monitor note if it's a performance issue.
