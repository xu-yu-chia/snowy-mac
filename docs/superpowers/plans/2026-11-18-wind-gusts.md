# Wind Gusts Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans. Steps use checkbox (`- [ ]`) syntax.

**Goal:** The set wind gusts: ±30° direction swing, 60–130% strength, all displays in step, toggleable.

**Architecture:** Pure `WindGusts` in SnowCore; `SnowSimulation.airflow` override for moving
material; the app computes gusts per frame and feeds simulations and lights.

**Tech Stack:** Swift 6, AppKit, XCTest.

**Spec:** docs/superpowers/specs/2026-11-18-wind-gusts-design.md

## Global Constraints
- Corner wind keeps reading the set `wind`; `airflow` never sets `cornerWindDirty`.
- Calm (< 1% strength) never gusts; Reduce Motion never gusts.
- Persist the toggle as UserDefaults bool `windGusts`, default true.

## Review Focus
- Gust output stays finite and within ±30° / 60–130% (capped at 1) for any time value, including huge `now`.
- Setting `airflow` every frame must not trigger corner-wind rebuilds.
- Turning gusts off or Reduce Motion on returns to the exact set wind.

---

### Task 1: WindGusts + simulation airflow (SnowCore)

**Files:** Create `Sources/SnowCore/WindGusts.swift`, `Tests/SnowCoreTests/WindGustsTests.swift`;
Modify `Sources/SnowCore/SnowSimulation.swift`, `SnowSimulation+Particles.swift`, `SnowSimulation+Rain.swift`.

**Produces:** `public enum WindGusts { public static func wind(base: WindSettings, at time: Double) -> WindSettings }`;
`public var airflow: WindSettings?` on `SnowSimulation`; internal `var air: WindSettings { airflow ?? wind }`.

- [ ] Tests: heading stays within base ±30°, strength within [0.6, 1.3]×base (≤ 1), both vary over 60 s
  (spread > 15° and > 0.3×base); calm base returns calm; finite at time 1e9; setting `airflow`
  leaves corner wind clean (flake drift follows airflow: mean flake vx sign follows airflow).
- [ ] Implement; replace moving-material reads of `wind.velocity` (flakes, upwind entry, loose snow,
  raindrops) with `air.velocity`. Scene/corner code unchanged.
- [ ] Full suite green; commit.

### Task 2: App wiring + Gusts toggle

**Files:** Modify `Sources/Snowy/DesktopCoordinator.swift`, `Sources/Snowy/WindControl.swift`, `Sources/Snowy/AppDelegate.swift`.

- [ ] `DesktopCoordinator.gusts: Bool` (UserDefaults `windGusts`, default true); per frame in
  `beforeFrame`: `let air = gusts && !policy.reducedMotion ? WindGusts.wind(base: wind, at: now) : wind`;
  set `display.renderer.simulation.airflow = air`; pass `air` to `lights.advance`.
- [ ] Popover: `Gusts` checkbox bound to `coordinator.gusts`.
- [ ] Build app, suite green, commit.
