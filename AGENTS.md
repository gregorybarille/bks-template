# AGENTS.md

## Quick Reference

| Task | Command |
|------|---------|
| Install deps | `yarn install` |
| Start dev (hot reload) | `yarn start` |
| Type check | `yarn tsc` |
| Lint | `yarn lint` |
| Test | `yarn test` |
| Build backend | `yarn build:backend` |
| Scaffold new plugin | `yarn new` |

## Architecture

**Monorepo structure:**
- `packages/app` — Frontend (React, new frontend system)
- `packages/backend` — Backend (Node.js, new backend system)
- `plugins/` — Custom plugins (frontend, backend, or common)

**Workspace layout:**
```
packages/
  app/          # Frontend, port 3000
  backend/      # Backend, port 7007
plugins/
  <plugin-id>/  # Frontend plugin
  <plugin-id>-backend/  # Backend plugin
  <plugin-id>-common/   # Shared types/API
```

## Toolchain

- **Node.js:** 22 || 24 (engines enforced)
- **Yarn:** 4.13.0 via corepack (`.yarn/releases/yarn-4.13.0.cjs`)
- **Package manager:** Yarn with `nodeLinker: node-modules`
- **TypeScript:** ~5.8.0
- **React:** ^18.0.2
- **Backstage:** Latest stable (v1.52+)

## Backend Registration

Plugins are registered in `packages/backend/src/index.ts`:
```ts
backend.add(import('@internal/plugin-my-plugin-backend'));
```

Frontend plugins are auto-discovered when added to `packages/app/package.json` dependencies.

## Docker

**Two modes via profiles:**
```sh
# Dev mode (hot reload, source mounted)
docker compose --profile dev up

# Production mode (built image)
docker compose --profile prod up
```

**Base images:** `registry.access.redhat.com/ubi9/nodejs-24` (OpenShift-compatible)

**Production database:** PostgreSQL 16 (configured via `app-config.production.yaml`)
**Local dev database:** SQLite in-memory (configured via `app-config.yaml`)

## Plugin Development

**Frontend plugin:**
- Use `createFrontendPlugin` from `@backstage/frontend-plugin-api`
- Use Blueprints: `PageBlueprint`, `EntityContentBlueprint`, `ApiBlueprint`
- Lazy load all page components

**Backend plugin:**
- Use `createBackendPlugin` from `@backstage/backend-plugin-api`
- Declare deps via `coreServices` (logger, httpRouter, database, httpAuth)
- Register in `packages/backend/src/index.ts`

**Full-stack plugin:** 3 packages
- `plugins/<name>/` — Frontend
- `plugins/<name>-backend/` — Backend
- `plugins/<name>-common/` — Shared types

## Important Conventions

- **New frontend/backend system only** — Do not use legacy `createPlugin`/`createRouter`
- **Workspace dependencies:** Use `"workspace:*"` for internal packages
- **better-sqlite3:** In `devDependencies` (not needed in production with PostgreSQL)
- **Docker entrypoint:** Must be `[]` to override UBI9's container-entrypoint
- **Yarn invocation in Docker:** Use `node .yarn/releases/yarn-4.13.0.cjs` (UBI9 lacks yarn in PATH)

## Verification Order

When making changes:
1. `yarn tsc` — Type check first
2. `yarn lint` — Lint
3. `yarn test` — Run tests
4. `yarn build:backend` — Verify production build

## Config Files

- `app-config.yaml` — Main config (local dev, SQLite)
- `app-config.production.yaml` — Production config (PostgreSQL)
- `.yarnrc.yml` — Yarn config (nodeLinker: node-modules)
- `Dockerfile` — Multi-stage UBI9 build (packages → install → dev → build → production)
