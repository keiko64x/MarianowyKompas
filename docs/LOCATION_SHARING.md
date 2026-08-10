# Location sharing architecture

## Behavior (v1.1+)

While Medicine Compass is **running** (foreground or background, process alive):

- the phone uploads GPS to `POST /api/kompas/location/update` about every 30s (sooner if you move ~20m+)
- Android shows a persistent notification so the OS allows background GPS
- force-closing the app stops sharing

While the **compass view** for a person is open:

- the app also polls `GET /api/kompas/location/:id` at distance-based intervals
- that is when A sees B's arrow/distance live

## Result

If A has the app open in the background and B opens compass toward A, B sees A's fresh position.
If A's app is force-stopped, B only sees A's last uploaded point.
