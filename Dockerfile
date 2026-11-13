# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# Multi-stage Dockerfile for tech360-bd/idurar-erp-crm
#
# Stages:
#   1. backend-deps   — installs backend node_modules (cached layer)
#   2. frontend-build — builds the Vite static bundle
#   3. runtime        — slim Node image with backend + frontend dist + tini
#
# Run with docker compose up (uses docker-compose.yml) or standalone:
#   docker build -t idurar-erp-crm .
#   docker run -p 8888:8888 --env-file backend/.env idurar-erp-crm
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

# ─── Stage 1: backend dependencies ──────────────────────────────────
FROM node:20-bookworm-slim AS backend-deps
WORKDIR /app/backend
COPY backend/package.json backend/package-lock.json ./
# --omit=dev would skip nodemon etc.; we keep dev deps so `npm run dev`
# works in the same image. Production users can override with --omit=dev.
RUN npm ci --no-audit --no-fund

# ─── Stage 2: frontend build ────────────────────────────────────────
FROM node:20-bookworm-slim AS frontend-build
WORKDIR /app/frontend
COPY frontend/package.json frontend/package-lock.json ./
RUN npm ci --no-audit --no-fund
COPY frontend/ ./
# VITE_BACKEND_SERVER is baked at build time. Override with --build-arg
# for production deployments. Default points at the same container's
# backend on port 8888.
ARG VITE_BACKEND_SERVER=http://localhost:8888
ARG VITE_FILE_BASE_URL=http://localhost:8888/
ENV VITE_BACKEND_SERVER=${VITE_BACKEND_SERVER}
ENV VITE_FILE_BASE_URL=${VITE_FILE_BASE_URL}
RUN npm run build

# ─── Stage 3: runtime ───────────────────────────────────────────────
FROM node:20-bookworm-slim AS runtime

# tini = proper PID 1 signal handling (so SIGTERM shuts Node down cleanly)
# curl = healthcheck probe
RUN apt-get update \
  && apt-get install -y --no-install-recommends tini curl \
  && rm -rf /var/lib/apt/lists/*

WORKDIR /app

# Copy backend source + node_modules from stage 1
COPY --from=backend-deps /app/backend ./backend

# Copy built frontend dist from stage 2 into backend's static serve path
# idurar's backend serves /public via express.static — placing dist
# there lets the backend serve the SPA on the same origin (single port).
COPY --from=frontend-build /app/frontend/dist ./backend/public

# Copy top-level docs for context (small files)
COPY README.md INSTALLATION-INSTRUCTIONS.md LICENSE ./

WORKDIR /app/backend

# Default env (overridable at runtime via -e or --env-file)
ENV NODE_ENV=production
ENV PORT=8888
ENV PUBLIC_SERVER_FILE=http://localhost:8888/
ENV CLIENT_URL=http://localhost:8888

EXPOSE 8888

# Bind to all interfaces so the container is reachable from the host
# when published with -p 8888:8888.
HEALTHCHECK --interval=30s --timeout=5s --start-period=15s --retries=3 \
  CMD curl -fsS "http://127.0.0.1:${PORT:-8888}/api/health" || exit 1

# Use tini as PID 1 to reap zombies and forward signals
ENTRYPOINT ["/usr/bin/tini", "--"]

# Start the backend (which also serves the built frontend from /public)
CMD ["npm", "run", "start"]
