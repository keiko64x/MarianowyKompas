# Szadejkompas — API serwera domowego

Moduły Node.js pod ścieżką `https://server.szadejko.net/api/kompas`.

## Instalacja na dashboardzie

Skopiuj `kompas-store.js` i `kompas-routes.js` do katalogu dashboardu
(`C:\Users\SERVER.SZADEJKO.NET\dashboard`) i zamontuj router:

```js
const { createKompasRouter } = require('./kompas-routes');
app.use('/api/kompas', createKompasRouter(path.join(__dirname, 'data')));
```

Endpointy:

- `POST /api/kompas/profile/register`
- `POST /api/kompas/pair/request`
- `POST /api/kompas/pair/accept`
- `POST /api/kompas/location/update`
- `GET  /api/kompas/location/:targetUserId`
- `GET  /api/kompas/peers`
- `GET  /api/kompas/pair/pending`

Autoryzacja aplikacji mobilnej: nagłówki `X-User-Id` oraz `X-Device-Token`.
