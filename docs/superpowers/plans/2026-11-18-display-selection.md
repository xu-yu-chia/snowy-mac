# Display Selection Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans.

**Goal:** Per-display snow on/off from a Displays submenu, persisted by display UUID.
**Spec:** docs/superpowers/specs/2026-11-18-display-selection-design.md

## Global Constraints
- UserDefaults key `excludedDisplays` ([String] of UUIDs); new displays default to included.
- Deselected displays create no panel/renderer; primaryTop always from `NSScreen.screens.first`.

## Review Focus
- Deselecting the primary display must not shift the other displays' coordinates.
- Deselecting every display must not crash, leak panels, or keep timers running.

### Task 1: DisplaySelection (SnowCore) — `Sources/SnowCore/DisplaySelection.swift`, tests in `Tests/SnowCoreTests/DisplaySelectionTests.swift`
- `includes(_ uuid: String?) -> Bool` (nil → true), `setIncluded(_:for:)`, `stored: [String]` (sorted), `init(stored:)`.

### Task 2: App wiring — `DesktopCoordinator.swift`, `AppDelegate.swift`
- Coordinator `displaySelection` (didSet: persist, reconfigure, notify), `availableDisplays`, `noDisplaySelected`;
  `configureDisplays` filters screens. Displays submenu rebuilt in `menuNeedsUpdate`. State line text.
