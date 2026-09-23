# modulo-world-infrastructure

Docker Compose definitions for [ModuloWorld](https://github.com/gislamog/modulo-world-frontend):
PostgreSQL, the NestJS API, the SvelteKit frontend, and Nginx as the single public origin.

Issues for all three repositories live in
[modulo-world-frontend](https://github.com/gislamog/modulo-world-frontend/issues).

## Getting started

Requires Docker with Compose v2.

```bash
cp .env.example .env   # then fill in the credentials
docker compose up -d
docker compose ps      # wait for STATUS to read "healthy"
```

`.env` is gitignored and holds the real credentials. `.env.example` lists the variables and
is safe to commit because it contains no values.

The database is reachable on `localhost:5432` for GUI clients such as pgAdmin, DBeaver, or
TablePlus. Set `POSTGRES_PORT` in `.env` if that port is already in use.

## Layout

| File | Purpose |
|---|---|
| `compose.yaml` | Base definition for local development |
| `compose.override.yaml` | Local development only; Compose merges it automatically |
| `compose.prod.yaml` | Production. Run alone with `-f`, never merged |
| `nginx/nginx.conf` | Development server block |
| `nginx/nginx.bootstrap.conf` | Production, HTTP only, before a certificate exists |
| `nginx/nginx.prod.conf` | Production steady state: TLS, HSTS, www redirect |

The host port lives in the override file, not the base. This split is how "exposed in
development, not in production" is enforced. There is no flag to remember.

Production is a separate file rather than a second override, because Compose merges
`compose.override.yaml` automatically whenever it is present. A production stack that is one
forgotten flag away from bind-mounting source and publishing the database is not worth the
small amount of duplication it saves.

## Production

The production stack runs on the Oracle Ampere server in `~/modulo-world`. It pulls prebuilt
`linux/arm64` images from GHCR and never builds on the server.

```bash
docker compose -f compose.prod.yaml up -d
```

Note the `-f`. Without it Compose reads `compose.yaml` *and* merges `compose.override.yaml`,
which is the development stack.

### What production does not have

Every one of these is a removal, and each removal is the security property:

| Development | Production |
|---|---|
| Builds from local source | Pulls pinned images by commit SHA |
| Source bind-mounted for hot reload | Nothing mounted but read-only config |
| Postgres published on 5432 | Postgres reachable only on the internal network |
| One port, 80 | 80 and 443, with 80 redirecting |

### Deploying a new version

Images are published to GHCR by CI on merge to main, tagged with the full commit SHA.
Deploying is a matter of pointing `.env` at a different SHA. Nothing is built here.

```bash
gh api repos/gislamog/modulo-world-frontend/commits/main --jq .sha   # run locally
```

Then on the server, set `FRONTEND_IMAGE_TAG` / `BACKEND_IMAGE_TAG` in `.env` and:

```bash
docker compose -f compose.prod.yaml pull
docker compose -f compose.prod.yaml up -d
```

Rolling back is the same operation with an older SHA, which is the reason the tags are SHAs
and not `latest`. A moving tag cannot tell you what is running and cannot be rolled back to.

Migrations run automatically. The `migrate` service applies them and exits, and the API
starts only if it exited successfully, so a failed migration stops the deploy rather than
leaving the code running against a schema it does not match.

### Secrets

`.env` on the server is `chmod 600` and holds the database password and the IP hash salt.
It is not in git and has no counterpart in the repository beyond `.env.example`.

`secrets/cloudflare.ini` holds the Cloudflare API token used for the DNS-01 certificate
challenge, scoped to `Zone:DNS:Edit` on this zone only. Also `chmod 600`, also gitignored.

## PianoPogo

pianopogo.com is a second, unrelated site that shares this server and this Postgres instance
rather than getting its own (this box already uses the whole Always Free Ampere allowance, so
a second free VM isn't available). `piano-pogo-marketing`, `piano-pogo-game`, and
`piano-pogo-backend` pull pinned GHCR images the same way `frontend` and `api` do; nginx routes
`pianopogo.com` to them via a second `server_name` block, entirely separate from
`moduloworld.com`'s.

Its database is a second database on the same Postgres server, not a second container.
`postgres/init-piano-pogo-db.sh` creates it automatically, but **only when the `postgres-data`
volume is first created** — since that volume already exists on this server, the database has
to be created by hand once:

```bash
docker compose -f compose.prod.yaml exec postgres \
  psql -U "$POSTGRES_USER" -d "$POSTGRES_DB" \
  -c "CREATE DATABASE \"$PIANO_POGO_POSTGRES_DB\" OWNER \"$POSTGRES_USER\";"
```

`.env` needs `PIANO_POGO_POSTGRES_DB`, `CLERK_SECRET_KEY`, `PIANO_POGO_BACKEND_IMAGE_TAG`,
`PIANO_POGO_MARKETING_IMAGE_TAG`, and `PIANO_POGO_GAME_IMAGE_TAG` added alongside the existing
variables. Issuing `pianopogo.com`'s certificate is the same `certbot certonly --dns-cloudflare`
flow as `moduloworld.com`'s, just naming the new domain.

## Data

Postgres data is stored in the `postgres-data` named volume, which survives
`docker compose down`.

> **`docker compose down -v` deletes the volume**, and with it the entire database. The
> difference from the harmless command is two characters.

Credentials are read only when the volume is first created. Changing them in `.env` afterwards
has no effect on an existing database; the volume must be recreated for a change to apply.

## After adding a dependency

The `api` and `frontend` services keep `node_modules` in an anonymous volume, so the container
uses its own Linux build rather than whatever the Windows host installed. That volume is
created once and **survives image rebuilds**, which means a plain rebuild does not pick up a
newly installed package:

```bash
docker compose up -d --build api                            # not enough
docker compose up -d --force-recreate --renew-anon-volumes api   # correct
```

The symptom is the container failing with `Cannot find module` for a package that is clearly
in `package.json` and installed on the host. Rebuilding again does not help, because the stale
volume is mounted over the fresh image's `node_modules`.

## Common commands

```bash
docker compose logs api         # why a service is failing
docker compose logs postgres    # why it is not healthy
docker compose exec postgres psql -U "$POSTGRES_USER" -d "$POSTGRES_DB"
docker compose ps               # STATUS shows healthy, not just running
docker compose down             # stop, keeping data
```

## Migrations

Prisma owns the schema and lives in the backend repository. Migrations run from there, against
the database this repository starts:

```bash
cd ../modulo-world-backend
npm run prisma:migrate          # create and apply, development
npm run prisma:deploy           # apply existing migrations only, production
```

The API's `/api/health` endpoint runs a real query, so it returns 503 whenever Postgres is
unreachable. The `api` container's healthcheck consumes it, which is why that container shows
as unhealthy rather than merely running when the database is down.
