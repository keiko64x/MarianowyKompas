'use strict';

const fs = require('fs');
const fsp = require('fs/promises');
const path = require('path');
const crypto = require('crypto');

function createKompasStore(dataDir) {
  const filePath = path.join(dataDir, 'kompas-db.json');

  const emptyDb = () => ({
    users: {},
    locations: {},
    pairs: [],
    pairRequests: [],
    aliases: {},
  });

  let db = emptyDb();
  let writeQueue = Promise.resolve();

  async function ensureLoaded() {
    await fsp.mkdir(dataDir, { recursive: true });
    try {
      const raw = await fsp.readFile(filePath, 'utf8');
      const parsed = JSON.parse(raw);
      db = {
        users: parsed.users || {},
        locations: parsed.locations || {},
        pairs: Array.isArray(parsed.pairs) ? parsed.pairs : [],
        pairRequests: Array.isArray(parsed.pairRequests) ? parsed.pairRequests : [],
        aliases: parsed.aliases || {},
      };
    } catch (err) {
      if (err.code !== 'ENOENT') throw err;
      db = emptyDb();
      await persist();
    }
  }

  function persist() {
    writeQueue = writeQueue.then(async () => {
      const tmp = `${filePath}.${process.pid}.tmp`;
      await fsp.writeFile(tmp, JSON.stringify(db, null, 2), 'utf8');
      await fsp.rename(tmp, filePath);
    });
    return writeQueue;
  }

  function nowIso() {
    return new Date().toISOString();
  }

  function newId(prefix = '') {
    return `${prefix}${crypto.randomBytes(16).toString('hex')}`;
  }

  function aliasKey(ownerId, peerId) {
    return `${ownerId}::${peerId}`;
  }

  function arePaired(a, b) {
    return db.pairs.some(
      (p) => (p.a === a && p.b === b) || (p.a === b && p.b === a),
    );
  }

  function getPeerIds(userId) {
    const ids = [];
    for (const p of db.pairs) {
      if (p.a === userId) ids.push(p.b);
      else if (p.b === userId) ids.push(p.a);
    }
    return ids;
  }

  function formatActivity(timestamp) {
    if (!timestamp) return 'Brak aktywności';
    const ms = Date.now() - new Date(timestamp).getTime();
    if (Number.isNaN(ms) || ms < 0) return 'Ostatnia aktywność: przed chwilą';
    const minutes = Math.floor(ms / 60000);
    if (minutes < 1) return 'Ostatnia aktywność: przed chwilą';
    if (minutes < 60) return `Ostatnia aktywność: ${minutes} min temu`;
    const hours = Math.floor(minutes / 60);
    if (hours < 24) return `Ostatnia aktywność: ${hours} godz. temu`;
    const days = Math.floor(hours / 24);
    return `Ostatnia aktywność: ${days} dn. temu`;
  }

  function publicUser(user) {
    if (!user) return null;
    return {
      userId: user.userId,
      name: user.name,
      createdAt: user.createdAt,
      updatedAt: user.updatedAt,
    };
  }

  async function registerProfile(name) {
    const cleanName = String(name || '').trim() || 'Użytkownik';
    const userId = newId('u_');
    const deviceToken = newId('t_');
    const stamp = nowIso();
    db.users[userId] = {
      userId,
      name: cleanName,
      deviceToken,
      createdAt: stamp,
      updatedAt: stamp,
    };
    await persist();
    return { userId, deviceToken, name: cleanName };
  }

  async function updateProfile(userId, { name } = {}) {
    const user = db.users[userId];
    if (!user) return null;
    if (typeof name === 'string' && name.trim()) {
      user.name = name.trim();
      user.updatedAt = nowIso();
      await persist();
    }
    return publicUser(user);
  }

  function authenticate(userId, deviceToken) {
    const user = db.users[userId];
    if (!user || !deviceToken || user.deviceToken !== deviceToken) return null;
    return user;
  }

  async function createPairRequest(fromUserId, targetUserId) {
    if (!db.users[targetUserId]) {
      const err = new Error('Nie znaleziono użytkownika z kodu QR');
      err.status = 404;
      throw err;
    }
    if (fromUserId === targetUserId) {
      const err = new Error('Nie możesz sparować się sam ze sobą');
      err.status = 400;
      throw err;
    }
    if (arePaired(fromUserId, targetUserId)) {
      const err = new Error('Jesteście już sparowani');
      err.status = 409;
      throw err;
    }

    const existing = db.pairRequests.find(
      (r) =>
        r.status === 'pending' &&
        ((r.fromUserId === fromUserId && r.toUserId === targetUserId) ||
          (r.fromUserId === targetUserId && r.toUserId === fromUserId)),
    );
    if (existing) {
      return existing;
    }

    const request = {
      id: newId('pr_'),
      fromUserId,
      toUserId: targetUserId,
      status: 'pending',
      createdAt: nowIso(),
    };
    db.pairRequests.push(request);
    await persist();
    return request;
  }

  function listPendingFor(userId) {
    return db.pairRequests
      .filter((r) => r.status === 'pending' && r.toUserId === userId)
      .map((r) => ({
        ...r,
        fromUser: publicUser(db.users[r.fromUserId]),
      }));
  }

  async function acceptPairRequest(userId, requestId) {
    const request = db.pairRequests.find((r) => r.id === requestId);
    if (!request || request.status !== 'pending') {
      const err = new Error('Nie znaleziono prośby o parowanie');
      err.status = 404;
      throw err;
    }
    if (request.toUserId !== userId) {
      const err = new Error('Brak uprawnień do akceptacji');
      err.status = 403;
      throw err;
    }

    request.status = 'accepted';
    request.resolvedAt = nowIso();

    if (!arePaired(request.fromUserId, request.toUserId)) {
      db.pairs.push({
        a: request.fromUserId,
        b: request.toUserId,
        createdAt: nowIso(),
      });
    }

    await persist();
    return {
      ok: true,
      peer: publicUser(db.users[request.fromUserId]),
    };
  }

  async function rejectPairRequest(userId, requestId) {
    const request = db.pairRequests.find((r) => r.id === requestId);
    if (!request || request.status !== 'pending') {
      const err = new Error('Nie znaleziono prośby o parowanie');
      err.status = 404;
      throw err;
    }
    if (request.toUserId !== userId) {
      const err = new Error('Brak uprawnień');
      err.status = 403;
      throw err;
    }
    request.status = 'rejected';
    request.resolvedAt = nowIso();
    await persist();
    return { ok: true };
  }

  async function unpair(userId, peerUserId) {
    const before = db.pairs.length;
    db.pairs = db.pairs.filter(
      (p) =>
        !((p.a === userId && p.b === peerUserId) || (p.a === peerUserId && p.b === userId)),
    );
    delete db.aliases[aliasKey(userId, peerUserId)];
    delete db.aliases[aliasKey(peerUserId, userId)];
    if (db.pairs.length === before) {
      const err = new Error('Brak relacji do usunięcia');
      err.status = 404;
      throw err;
    }
    await persist();
    return { ok: true };
  }

  async function setAlias(ownerId, peerId, displayName) {
    if (!arePaired(ownerId, peerId)) {
      const err = new Error('Brak sparowania z tą osobą');
      err.status = 404;
      throw err;
    }
    const clean = String(displayName || '').trim();
    if (!clean) {
      delete db.aliases[aliasKey(ownerId, peerId)];
    } else {
      db.aliases[aliasKey(ownerId, peerId)] = clean;
    }
    await persist();
    return { ok: true, displayName: clean || db.users[peerId]?.name || peerId };
  }

  function listPeers(userId) {
    return getPeerIds(userId).map((peerId) => {
      const user = db.users[peerId];
      const loc = db.locations[peerId];
      const displayName = db.aliases[aliasKey(userId, peerId)] || user?.name || peerId;
      return {
        userId: peerId,
        name: user?.name || peerId,
        displayName,
        lastSeenAt: loc?.timestamp || null,
        lastActivityLabel: formatActivity(loc?.timestamp),
        hasLocation: Boolean(loc),
      };
    });
  }

  function _finiteOrNull(value) {
    const n = Number(value);
    return Number.isFinite(n) ? n : null;
  }

  async function updateLocation(userId, payload) {
    const lat = Number(payload.lat);
    const lng = Number(payload.lng);
    if (!Number.isFinite(lat) || !Number.isFinite(lng)) {
      const err = new Error('Nieprawidłowe współrzędne');
      err.status = 400;
      throw err;
    }
    // Compact keys (acc/spd/hdg/t) and legacy long names both accepted.
    const accuracy = _finiteOrNull(
      payload.acc !== undefined ? payload.acc : payload.accuracy,
    );
    const speed = _finiteOrNull(
      payload.spd !== undefined ? payload.spd : payload.speed,
    );
    const heading = _finiteOrNull(
      payload.hdg !== undefined ? payload.hdg : payload.heading,
    );
    const rawTs = payload.t || payload.timestamp;
    const timestamp = rawTs ? new Date(rawTs).toISOString() : nowIso();

    const next = {
      lat: Math.round(lat * 1e6) / 1e6,
      lng: Math.round(lng * 1e6) / 1e6,
      accuracy: accuracy === null ? null : Math.round(accuracy * 10) / 10,
      speed: speed === null || speed < 0 ? null : Math.round(speed * 10) / 10,
      heading:
        heading === null || heading < 0
          ? null
          : Math.round((((heading % 360) + 360) % 360) * 10) / 10,
      timestamp,
    };

    const prev = db.locations[userId];
    // Skip disk write when the fix is effectively identical (saves I/O).
    const unchanged =
      prev &&
      prev.lat === next.lat &&
      prev.lng === next.lng &&
      prev.accuracy === next.accuracy &&
      prev.speed === next.speed &&
      prev.heading === next.heading;

    db.locations[userId] = next;
    if (db.users[userId]) {
      db.users[userId].updatedAt = nowIso();
    }
    if (!unchanged) {
      await persist();
    }
    return db.locations[userId];
  }

  function getLocation(requesterId, targetUserId) {
    if (requesterId !== targetUserId && !arePaired(requesterId, targetUserId)) {
      const err = new Error('Brak dostępu do pozycji tej osoby');
      err.status = 403;
      throw err;
    }
    const loc = db.locations[targetUserId];
    if (!loc) {
      const err = new Error('Brak znanej pozycji');
      err.status = 404;
      throw err;
    }
    return {
      userId: targetUserId,
      lat: loc.lat,
      lng: loc.lng,
      acc: loc.accuracy,
      spd: loc.speed ?? null,
      hdg: loc.heading ?? null,
      // Legacy aliases for older clients.
      accuracy: loc.accuracy,
      speed: loc.speed ?? null,
      heading: loc.heading ?? null,
      timestamp: loc.timestamp,
      fetchedAt: nowIso(),
      lastActivityLabel: formatActivity(loc.timestamp),
    };
  }

  return {
    ensureLoaded,
    registerProfile,
    updateProfile,
    authenticate,
    createPairRequest,
    listPendingFor,
    acceptPairRequest,
    rejectPairRequest,
    unpair,
    setAlias,
    listPeers,
    updateLocation,
    getLocation,
    publicUser,
  };
}

module.exports = { createKompasStore };
