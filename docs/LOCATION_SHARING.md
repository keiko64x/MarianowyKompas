# Location sharing architecture

## Behavior (v1.2+)

While Medicine Compass is **running** (foreground or background, process alive):

- GPS is quality-gated (noisy fixes above ~40–85 m accuracy are dropped)
- uploads are **motion-adaptive**:
  - standing still → ~55–90 s between uploads (skip if you barely moved)
  - walking → ~20 s or ~18 m movement
  - faster movement → ~10 s
- compass view raises **priority mode** (denser GPS + 5–12 s uploads)
- Android shows a persistent notification so the OS allows background GPS
- force-closing the app stops sharing

Payloads stay small: rounded lat/lng, short JSON keys (`acc`/`spd`/`hdg`/`t`), and `{ok:true}` replies.

While the **compass view** for a person is open:

- polls `GET /api/kompas/location/:id` at distance- and speed-aware intervals (≈3–45 s)
- uses `If-None-Match` → HTTP **304** when the peer has not moved (almost no body)
- extrapolates peer position locally from last speed/heading between polls (capped)

## Result

Better arrow/distance accuracy when both people move, with less cellular chatter when they stand still or the peer fix is unchanged.
