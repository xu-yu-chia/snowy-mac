# Wind Gusts — Design

**Status:** approved 2026-11-18 (approach A, implementation 1)

## Intent
The wind set in **Wind…** is fixed. The user wants it to vary: the direction swings around the
set heading and the strength rises and falls, so falling snow and rain look alive. The set wind
stays the mean; it is not replaced.

## Goals
- Direction swings within ±30° of the set heading; strength varies between 60% and 130% of the
  set strength (capped at full strength), a gust every ~4–8 s, irregular (summed sines of
  unrelated periods), never a visible loop.
- Flakes, raindrops, drips, loose snow and the hanging lights follow the gusting wind.
- All displays gust in step (one function of the shared frame clock).
- A **Gusts** checkbox in the Wind popover, on by default, persisted (`windGusts`).

## Non-goals / anti-goals
- No roaming to arbitrary headings (that was approach B).
- Corner wind (where caps build up beside windows) keeps using the set wind: re-deriving
  capacities every frame would cost a scene rebuild per frame and make caps twitch.
- Calm stays calm: no gusts when the set strength is below 1%.

## Approaches
1. **Chosen:** a pure SnowCore function `WindGusts.wind(base:at:)`; the app evaluates it once per
   frame with the frame clock and hands the result to each display's simulation (`airflow`, which
   does not dirty corner wind) and to the lights. Testable, synced, corner wind untouched.
2. Gusts inside each simulation: fewer touch points, but displays drift out of step and the
   lights need their own copy.

## Builder's calls
- Reduce Motion turns gusts off (steady wind), like other ambient motion.
- `SnowSimulation.airflow: WindSettings?` overrides `wind` for moving material only; `nil` = use
  `wind`. Corner wind and scene rebuilds keep reading `wind`.
- Popover grows by 26 pt to fit the checkbox under the hint.
