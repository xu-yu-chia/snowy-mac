# Rain mode — design

Status: approved by user · 2026-11-17 · branch `snow-physics-improvements`

## Intent

A **Rain** weather mode that replaces snow entirely while it is on. It is not snow with a
different sprite: the physics changes with it. Rain collects as **water** on window and widget
tops, runs off them, and **floods the bottom of the screen**, rising over time until it reaches
the height of the Dock. The flood is not a static fill: it **behaves a little like a fluid**
when things interact with it (the pointer, raindrops, runoff, windows), with waves and splashes.

Why: the user wants a rainy-day desktop with the same "things react physically" feel the snow
now has. Snow behaviour must be unaffected when the mode is Snow.

## Goals

1. Weather setting **Snow / Rain**, saved like the other weather settings.
2. Rain falls as fast, thin, slanted streaks; wind slants them.
3. Tops (windows, widgets, Dock tray) hold a **shallow, level puddle**; excess runs off the ends
   and down the sides into the flood.
4. A **flood** at the bottom of each display rises with the rain that reaches it and stops at
   the Dock's top edge.
5. The flood surface is a **1D wave field**: raindrops, runoff, the pointer and windows make
   ripples and waves that travel and die out; fast pointer strokes splash droplets.
6. Switching Snow ↔ Rain transitions naturally (melt / drain), never an instant wipe.
7. Load no higher than snow at the same density (Snowy CPU, WindowServer, GPU within the snow
   ranges measured on the M1: Snowy ≈ 7–11 %, GPU ≈ 12–36 %).

## Non-goals

- 2D fluid flowing across the desktop between windows, or reflections/refraction (basins between
  windows are in scope, see Containers).
- Rain sound, thunder or lightning.
- Water on Spotlight's temporary cap (Spotlight just gets wet flakes passing by).
- Puddles on decorations/props (see Decorations below).
- Persisting the flood level across launches (a fresh launch starts dry).

## Anti-goals (would make it a failure even if it "works")

- Water drawn **over** windows. Like snow, all water is drawn on the desktop plane behind
  native windows (the Dock tray and widgets stay above it, as today).
- The flood rising above the Dock's top edge, or covering the whole screen.
- Flicker, popping, or a visible jump when switching modes.
- Snow mode changing in any way (all existing tests stay green; snow code paths untouched
  except for the mode switch).

## Approaches considered

| | Approach | Trade-off |
|---|---|---|
| A | Reuse the snow engine with water parameters (drops = fast flakes, puddles/flood = drifts) | Least new code, but drift profiles are per-sample heights capped at ~18–28 pt; water needs level surfaces and an ~80 pt flood, so it would need many "if water" exceptions. |
| **B (chosen, modified)** | A small separate **water system**: streak particles; one **level depth per top** for puddles; a **1D wave height field** for the flood with a rising mean level | Matches water (always level, flows downhill), simple and cheap. Needs new rendering for streaks, puddles and the flood surface. |
| C | Real 2D fluid simulation | Most realistic, too heavy for the M1 and bug-prone. Rejected. |

The user chose B, with the flood upgraded from a single level to a wave field so it reacts like
a fluid when touched.

## Physics

All numbers below are the builder's starting values (**proposed**) and may be tuned in review
with the user; tests should pin behaviour (ranges, ordering, conservation), not exact constants.

### Raindrops

- Particle with position, velocity, life. Rendered as a **streak** along its velocity:
  length 8–20 pt (∝ speed), width 1–1.5 pt, opacity 0.35–0.7 by depth.
- Fall speed 450–750 pt/s (depth-scaled), plus `wind.velocity` (horizontal) — no per-particle
  sway like snow. Upwind-edge entry reuses the snow rule (flux share).
- Count: same flake budget as snow, scaled by the density setting
  (Light/Steady/Flurry → drizzle/rain/downpour).
- **On contact**
  - **Top with a puddle surface** (any drift surface): adds its water to that top's puddle,
    spawns 1–3 splash droplets (visual only, ≤ 0.3 s life, small upward arc), recycles.
  - **Vertical wall** (window side, screen edge): does not cling like snow; it becomes a short
    **runoff drip** sliding down at ~120 pt/s (see Runoff) — or simply recycles if the drip
    budget is full.
  - **Flood surface**: adds its water to the flood (see Flood volume) and an impulse to the
    wave field at that x (ripple), spawns splash droplets, recycles.
  - Underside / anything else: recycles.
- Water per drop is chosen like snow's `flakeMassScale`: so the **flood reaches the Dock top in
  about 5 min at Steady** (≈ 10 min drizzle, ≈ 2.5 min downpour) on a 1920×1080 display with
  no windows. With windows, rain that lands on tops reaches the flood later via runoff.

### Puddles on tops

- Each drift surface (window, widget, Dock tray) gets a **single puddle depth** `d` (pt), drawn
  as a level water layer of thickness `d` along the visible top, following the rounded shoulders.
- Max depth `d_max = 3 pt` (Dock tray 2 pt). Water above `d_max` **runs off**.
- **Surface tension (user requests, 2026-11-17)**: once full, the water surface stays at the
  overflow level; the excess gathers at the overflow point into a hanging drop that falls once it
  holds ~12 pt². A glove stroke that touches a puddle carries the whole puddle off.
- **Containers (user request, 2026-11-17)**: a top with a taller window right beside each visible end
  is a basin. It fills like the flood up to the shorter wall's top and spills over that wall.
- Runoff split: on a level top, equally to both exposed ends; on a tilted (Stage Manager) top,
  all to the lower end; an end covered by another window or facing a neighbour within 16 pt
  (the existing bridge rule) passes its share to the other end / neighbour.
- Puddles **move with their window**? No: consistent with "snow stays put", a moved or resized
  window drops its puddle as runoff at its old ends (water falls); a new or uncovered top starts
  dry. Closed/minimized windows release their puddle as falling water.
- Evaporation: puddles shrink ~2 %/s only while it is **not** raining (after switching to Snow).

### Runoff

- Water leaving a top becomes **drips**: small particles (2 pt) that slide down the nearest wall
  at ~120 pt/s, then fall freely (gravity 900 pt/s²) when the wall ends, and on reaching the
  flood add their water and a wave impulse. Budget: ≤ 64 drips; excess water is added directly
  to the flood (conserved).
- Visual: drips are drawn as short vertical streaks (reuse the raindrop streak style, shorter).

### Flood

- Per display: a 1D height field `h[i]` over the display width, sample spacing ≈ 4 pt
  (≈ 480 samples at 1920 pt), plus a **mean level** `L` (pt above the screen bottom).
- **Volume**: incoming water (drops, drips, melt) raises `L` by `area / width`. `L` is capped at
  `L_max` = the top edge of the **Dock tray body Snowy already derives** (`DesktopSceneBuilder`'s
  dock body), measured above the screen bottom, so the water line meets the tray's top; with no
  bottom Dock (hidden, side, auto-hide off-screen), `L_max = 60 pt` (**proposed**). Water
  arriving at the cap is discarded.
- *(Builder's call)* `L_max` can change at runtime (Dock moved, resized, display changed). If it
  drops below `L`, the level eases down to the new cap over ~2 s (no pop; water above the cap
  is discarded as it drains). If it rises, the level stays and keeps filling normally.
- **Waves**: damped wave equation on `h` (the deviation from `L`):
  `a[i] = c²·(h[i-1] + h[i+1] − 2h[i]) / dx² − k·v[i]`, explicit integration at the 60 Hz
  fixed step the granular field already uses, with `c ≈ 260 pt/s`, damping `k ≈ 1.6 /s`;
  amplitude clamped to ±12 pt. Mean of `h` is kept at 0 (volume lives in `L`).
- **Interactions** (impulses on `v[i]`):
  - raindrop landing: small down impulse at x (ripple);
  - drip landing: larger impulse;
  - **pointer**: when the cursor is below the surface (y > water line) and moving, push the
    columns it sweeps in the stroke direction (wake: down in front, up behind, ∝ speed);
    strokes faster than the snow fling speed (450 pt/s) **splash** droplets up and forward
    (reuse the clump flight: arc, fall back, add water and an impulse where they land);
    shovel tool = stronger push;
  - **windows**: a window whose bottom edge is below the water line and that moves sideways
    pushes waves out from its leading side (∝ speed); a window lowered into the water raises a
    bow wave at both sides. Windows do **not** change the volume (water is behind them visually).
- The flood occupies the whole width, including under windows (hidden behind them like snow).
  The Dock tray sits above it; at `L_max` the water line meets the tray's top edge.
- Floor snow (`groundID` drift) is unused in rain mode.

### Mode transitions

- **Snow → Rain**: snowfall stops spawning; raindrops start. Existing settled snow **melts**
  over ~40 s (all piles lose height at a rate that empties a full cap in ~40 s). **Melted snow
  becomes one tenth of its area in water (10:1, user's choice)**, so melt is only a thin top-up
  and the rain is what raises the flood: on tops it fills the puddle (overflow runs off), on the
  floor it raises the flood. Loose granular snow and clumps melt into the flood (also 10:1)
  immediately on landing.
- **Rain → Snow**: raindrops stop; snowflakes start. The flood **drains** to 0 over ~20 s
  (level falls smoothly; waves die out naturally); puddles evaporate over ~20 s. *(Builder's
  call)* A flake that lands on water still present (flood surface or a puddle) melts into it
  and adds its water; snow only starts settling on the floor once the flood is gone, and on a
  top once its puddle is gone.
- *(Builder's call)* During Snow → Rain, a top that still carries snow draws its puddle on the
  snow surface (water sits on the melting snow), not at the window top.
- Switching back mid-transition continues from the current state (no reset).

### Decorations

*(Builder's call)* Decorations and hanging lights stay visible in rain. Raindrops hit prop
 bodies and splash/recycle like on a wall or top, but props get **no puddle** (their drift
 surfaces are skipped for water). Snow already on props melts like any other snow during
 Snow → Rain.

### Wind, glove, settings

- Wind slants rain via its horizontal velocity; the wind panel works unchanged.
- Glove/shovel on puddles: brushing a top pushes its puddle water off the brushed end as drips
  (fast strokes: splash droplets in the stroke direction).
- Menu: new **Weather ▸ Snow / Rain**. The density items keep their labels (Light/Steady/Flurry)
  and map to drizzle/rain/downpour. **Melting** and **Grain Size** are greyed out in Rain mode.
  "Clear Settled Snow" also clears puddles and the flood.
- Performance policies (low power, thermal, zoomed-window 20 fps, full-screen pause) apply to
  rain exactly as to snow.

## Rendering (summary — details are the builder's call)

- Raindrops, drips and splash droplets: a new instanced **streak** pipeline (position, direction,
  length, width, opacity) alongside the flake quads, sharing the instance-buffer budget.
- Puddles: a thin translucent water band on each visible top (desktop plane, behind windows).
- Flood: a triangle strip from `h` + `L` to the screen bottom; translucent blue-grey body with a
  brighter 1 px surface line; drawn on the desktop plane, behind windows, under the Dock tray.
- Colours must read in light and dark wallpapers (semi-transparent, not saturated blue).

## Testing

New SnowCore tests (no GPU), mirroring the snow approach:
- flood rises with incoming water, stops at `L_max`, rate ordering drizzle < rain < downpour;
- puddle depth capped at `d_max`, overflow conserved into drips/flood, split rules (level, tilted,
  covered end, neighbour bridge);
- moved/closed window releases its puddle (no water carried, none lost);
- wave field: impulse spreads both ways and decays; mean level unchanged by waves; amplitude
  clamp; pointer wake direction; fast stroke spawns splash droplets that return their water;
- transitions: snow melts into water within ~40 s at 10:1 (a full snowy desktop adds only a
  thin layer); flood drains within ~20 s; switching back mid-way continues;
- Snow mode unchanged: entire existing suite stays green.
- Load check on the real app: rain at Steady within the measured snow ranges.

## Left to the builder

Exact constants within the stated ranges, data-structure layout, shader details, how the water
mesh shares the existing render pass, and test fixtures — provided the behaviour above holds and
snow mode is untouched.
