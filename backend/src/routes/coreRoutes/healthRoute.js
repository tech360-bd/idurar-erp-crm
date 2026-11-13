/**
 * Public health endpoint — mounted at GET /api/health
 *
 * Returns a 200 with a small JSON body as long as the Express process
 * is alive and can dispatch a request. Does NOT require auth.
 *
 * Optionally pings MongoDB if `mongoose` is connected and reports the
 * connection state, but never blocks on DB — a liveness probe should
 * always return quickly even if the DB is down.
 *
 * Used by:
 *   - Dockerfile HEALTHCHECK
 *   - docker-compose.yml healthcheck blocks
 *   - Render Blueprint healthCheckPath
 *   - External uptime monitors
 */
const express = require('express');
const mongoose = require('mongoose');

const router = express.Router();

const READY_STATES = {
  0: 'disconnected',
  1: 'connected',
  2: 'connecting',
  3: 'disconnecting',
};

router.route('/health').get(function healthHandler(_req, res) {
  const readyState = mongoose?.connection?.readyState ?? 0;
  const dbState = READY_STATES[readyState] || 'unknown';

  // Liveness: process is alive and routing works.
  // Readiness: DB connection state is included but does NOT gate the
  // response — orchestrators should look at `data.db` to decide whether
  // to route traffic, while still getting a 200 for liveness.
  return res.status(200).json({
    success: true,
    result: {
      status: 'ok',
      application: 'idurar-erp-crm',
      timestamp: new Date().toISOString(),
      uptimeSeconds: Math.round(process.uptime()),
      db: {
        state: dbState,
        readyState,
        host: mongoose?.connection?.host || null,
        name: mongoose?.connection?.name || null,
      },
    },
    message: 'Service is live',
  });
});

module.exports = router;
