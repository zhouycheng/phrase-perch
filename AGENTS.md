# Repository Guidelines

## Project Structure & Module Organization

PhrasePerch is a Swift 6 macOS application using SwiftUI and AppKit.

- `Sources/App/`: application bootstrap, dependency composition, and lifecycle.
- `Sources/Domain/`: configuration models, business rules, and state machines.
- `Sources/Features/`: feature-specific Views, ViewModels, components, layouts, window controllers, and animation.
- `Sources/Services/`: editing, preferences, authorization, trigger sessions, and insertion workflows.
- `Sources/Persistence/`: the observable configuration repository, storage protocol, JSON actor, and entry preferences.
- `Sources/Platform/macOS/`: native system APIs and platform adapters.
- `Sources/Shared/`: reusable presentation components and styling.
- `Tests/`: Domain, ViewModels, Services, Persistence, Presentation, and Support suites.
- `ARCHITECTURE.md`: ownership, dependency boundaries, and extension guidance.
- `Resources/`: application icons and third-party licensing. `AppIcon.icns` is packaged; `AppIcon.png` supports README presentation.
- `PhrasePerch.xcodeproj/` and `Info.plist`: build settings, shared scheme, dependency resolution, and bundle metadata.
- `.build/`: generated builds, test results, and previews.

## Build, Test, and Development Commands

Use Xcode 27 or a compatible newer version. The target is Apple Silicon, macOS 14 or later.

```bash
open PhrasePerch.xcodeproj
xcodebuild -project PhrasePerch.xcodeproj -scheme PhrasePerch \
  -configuration Release -destination 'platform=macOS,arch=arm64' \
  -derivedDataPath .build build
xcodebuild -project PhrasePerch.xcodeproj -scheme PhrasePerch \
  -configuration Debug -destination 'platform=macOS,arch=arm64' \
  -derivedDataPath .build test
open .build/Build/Products/Release/PhrasePerch.app
```

These commands open the project, build the application, run tests, and launch the Release artifact.

## Coding Style & Naming Conventions

Use four-space indentation, `UpperCamelCase` types, and `lowerCamelCase` members. Match surrounding Swift style. Give each independent component and primary type its own matching filename. Views send actions to ViewModels; services own business changes; ConfigurationRepository owns configuration. Services must not reference concrete Views or ViewModels. Keep UI state on `@MainActor`; isolate disk work in the persistence actor. Maintain Swift 6 strict concurrency checks. Use Xcode diagnostics and `git diff --check` during verification.

## Testing Guidelines

Name XCTest methods `test<Behavior>`. Add focused regressions for changed behavior, especially trigger eligibility, selection, cancellation, and configuration recovery. Use temporary directories and injected dependencies. Default runs render previews offscreen; enable `PHRASEPERCH_VISIBLE_UI_TESTS=1` in the Test scheme for planned desktop checks. Verify UI changes at 960 × 620, 880 × 560, and 1280 × 800 points.

## Commit & Pull Request Guidelines

Use concise Chinese commit summaries: `refactor(content): 重构 UI` or `fix(content): 优化交互方式`. Split commits by coherent behavior. PRs should explain the resulting behavior, link relevant issues, report validation, and include screenshots for UI changes.

## Configuration & Agent Guidance

Preserve configuration compatibility and user data under `~/Library/Application Support/local.FloatingInputBar/`. Test permissions against the actual built application; ad hoc signing can require reauthorization.

For repository documentation, apply the `no-negative-echo` skill at `/Users/zhou/.agents/skills/no-negative-echo/SKILL.md`. Describe accepted behavior directly and review headings, filenames, and final text. Preserve existing user changes; commit and push when requested.
