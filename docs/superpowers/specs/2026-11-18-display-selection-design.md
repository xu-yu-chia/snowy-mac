# Display Selection — Design

**Status:** approved 2026-11-18

## Intent
Let the person choose which displays get snow (e.g. leave a secondary or built-in display alone).

## Design
- Menu **Displays ▸** lists each connected display by its localized name with a checkmark;
  clicking toggles it. The submenu is rebuilt each time it opens, so hot-plugging is reflected.
- A deselected display gets no panel, renderer or simulation at all (snow, decorations and
  lights), so it costs no GPU/CPU. The flake budget is split over the selected displays only,
  keeping per-area density.
- Persisted as the set of **excluded** display hardware UUIDs (`CGDisplayCreateUUIDFromDisplayID`),
  UserDefaults `excludedDisplays`; UUIDs survive reboots and replugging, display IDs may not.
  A newly connected display is included by default. A display without a UUID is always included.
- All displays may be deselected; the state line then reads "No display selected".
- Coordinates keep using the system primary display as origin, even when it is deselected.

## Approaches
Only one sensible way: filter screens in `configureDisplays`. Hiding panels instead would keep
paying for simulation on deselected displays.

## Builder's calls
- `DisplaySelection` (SnowCore) holds the excluded set and is unit-tested; the AppKit wiring is
  verified by build and on the real machine.
