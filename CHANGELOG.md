# Changelog

## [0.1.1] — 2026-05-20 — Engine power scaler wired

- Fix: the `EnginePower` sandbox option (Drivetrain page, range 0.25–3.0,
  default 1.0) is now actually applied. The option existed since 0.1.0 but
  wasn't multiplied into the HP/Weight overhaul's `engineForce` write —
  changing it had no effect. Now `engineForce = hp × 10 × EnginePower`,
  giving users a knob to dial up top-end and acceleration without losing
  the realism baseline. Default 1.0 preserves 0.1.0 behaviour exactly.
- Note: only takes effect with **Reference power & weight** enabled. The
  scaler is a multiplier on the researched values; if you opt out of the
  overhaul, vanilla engineForce is unchanged.
- Lua-only change. No manual install update needed.

## [0.1.0] — 2026-05-19 — Initial release

- Independent drivetrain & traction overhaul for B42.18.
- Torque-curve acceleration with tunable low-speed shove.
- Surface- & weather-aware grip (road / rain / snow / off-road).
- Tyre-type per-surface grip model (worn / standard / modern).
- Load → handling (sandbox-tunable launch penalty) and load → fuel use.
- Configurable air drag + rolling resistance; opt-in reference
  power/weight table with a public registration API.
- Cargo-capacity rescale; arcade drift mode (off by default).
- Tyre marks that self-expire (~10 in-game min).
- Docked vehicle info panel.
- Server-authoritative vehicle ground-clip (Z-sink) guard.
- Sandbox taxonomy: Mode preset + Handling / Tyres & Load /
  Drivetrain / Readout pages.
- Clean-room Java engine bundle better-vehicle-dynamics-42.
