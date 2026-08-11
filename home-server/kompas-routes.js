'use strict';

const express = require('express');
const { createKompasStore } = require('./kompas-store');

function createKompasRouter(dataDir) {
  const router = express.Router();
  const store = createKompasStore(dataDir);
  const ready = store.ensureLoaded();

  async function withStore(req, res, next) {
    try {
      await ready;
      next();
    } catch (err) {
      next(err);
    }
  }

  router.use(withStore);

  function requireKompasAuth(req, res, next) {
    const userId = String(req.headers['x-user-id'] || req.body?.userId || '').trim();
    const deviceToken = String(
      req.headers['x-device-token'] || req.body?.deviceToken || '',
    ).trim();
    const user = store.authenticate(userId, deviceToken);
    if (!user) {
      return res.status(401).json({ error: 'Wymagana rejestracja profilu' });
    }
    req.kompasUser = user;
    return next();
  }

  router.get('/health', (req, res) => {
    res.json({ ok: true, service: 'kompas' });
  });

  router.post('/profile/register', async (req, res) => {
    try {
      const profile = await store.registerProfile(req.body?.name);
      return res.status(201).json(profile);
    } catch (err) {
      return res.status(err.status || 500).json({ error: err.message || 'Błąd rejestracji' });
    }
  });

  router.get('/profile/me', requireKompasAuth, (req, res) => {
    return res.json(store.publicUser(req.kompasUser));
  });

  router.patch('/profile', requireKompasAuth, async (req, res) => {
    try {
      const updated = await store.updateProfile(req.kompasUser.userId, {
        name: req.body?.name,
      });
      return res.json(updated);
    } catch (err) {
      return res.status(err.status || 500).json({ error: err.message || 'Błąd aktualizacji' });
    }
  });

  router.get('/peers', requireKompasAuth, (req, res) => {
    return res.json({ peers: store.listPeers(req.kompasUser.userId) });
  });

  router.patch('/peers/:peerUserId', requireKompasAuth, async (req, res) => {
    try {
      const result = await store.setAlias(
        req.kompasUser.userId,
        String(req.params.peerUserId),
        req.body?.displayName,
      );
      return res.json(result);
    } catch (err) {
      return res.status(err.status || 500).json({ error: err.message || 'Błąd aliasu' });
    }
  });

  router.post('/pair/request', requireKompasAuth, async (req, res) => {
    try {
      let targetUserId = String(req.body?.targetUserId || '').trim();
      if (!targetUserId && req.body?.qr) {
        const qr = typeof req.body.qr === 'string' ? JSON.parse(req.body.qr) : req.body.qr;
        targetUserId = String(qr?.userId || '').trim();
      }
      if (!targetUserId) {
        return res.status(400).json({ error: 'Brak targetUserId z kodu QR' });
      }
      const request = await store.createPairRequest(req.kompasUser.userId, targetUserId);
      return res.status(201).json({
        ok: true,
        request: {
          id: request.id,
          fromUserId: request.fromUserId,
          toUserId: request.toUserId,
          status: request.status,
          createdAt: request.createdAt,
        },
      });
    } catch (err) {
      if (err instanceof SyntaxError) {
        return res.status(400).json({ error: 'Nieprawidłowy format kodu QR' });
      }
      return res.status(err.status || 500).json({ error: err.message || 'Błąd parowania' });
    }
  });

  router.get('/pair/pending', requireKompasAuth, (req, res) => {
    return res.json({ pending: store.listPendingFor(req.kompasUser.userId) });
  });

  router.post('/pair/accept', requireKompasAuth, async (req, res) => {
    try {
      const requestId = String(req.body?.requestId || '').trim();
      if (!requestId) {
        return res.status(400).json({ error: 'Brak requestId' });
      }
      const result = await store.acceptPairRequest(req.kompasUser.userId, requestId);
      return res.json(result);
    } catch (err) {
      return res.status(err.status || 500).json({ error: err.message || 'Błąd akceptacji' });
    }
  });

  router.post('/pair/reject', requireKompasAuth, async (req, res) => {
    try {
      const requestId = String(req.body?.requestId || '').trim();
      if (!requestId) {
        return res.status(400).json({ error: 'Brak requestId' });
      }
      const result = await store.rejectPairRequest(req.kompasUser.userId, requestId);
      return res.json(result);
    } catch (err) {
      return res.status(err.status || 500).json({ error: err.message || 'Błąd odrzucenia' });
    }
  });

  router.post('/unpair', requireKompasAuth, async (req, res) => {
    try {
      const peerUserId = String(req.body?.peerUserId || '').trim();
      if (!peerUserId) {
        return res.status(400).json({ error: 'Brak peerUserId' });
      }
      const result = await store.unpair(req.kompasUser.userId, peerUserId);
      return res.json(result);
    } catch (err) {
      return res.status(err.status || 500).json({ error: err.message || 'Błąd odparowania' });
    }
  });

  router.post('/location/update', requireKompasAuth, async (req, res) => {
    try {
      await store.updateLocation(req.kompasUser.userId, req.body || {});
      // Compact OK — avoid echoing the full fix (saves cellular uplink+downlink).
      return res.json({ ok: true });
    } catch (err) {
      return res.status(err.status || 500).json({ error: err.message || 'Błąd lokalizacji' });
    }
  });

  router.get('/location/:targetUserId', requireKompasAuth, (req, res) => {
    try {
      const location = store.getLocation(
        req.kompasUser.userId,
        String(req.params.targetUserId),
      );
      const etag = `"${location.timestamp}"`;
      res.set('ETag', etag);
      res.set('Cache-Control', 'private, no-cache');
      if (req.headers['if-none-match'] === etag) {
        return res.status(304).end();
      }
      return res.json(location);
    } catch (err) {
      return res.status(err.status || 500).json({ error: err.message || 'Błąd pobierania pozycji' });
    }
  });

  return router;
}

module.exports = { createKompasRouter };
