# modulo-world-infrastructure

Docker Compose definitions for [ModuloWorld](https://github.com/gislamog/modulo-world-frontend).
Currently a PostgreSQL database; Nginx and the application services follow.

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
| `compose.yaml` | Base definition, true in every environment |
| `compose.override.yaml` | Local development only; Compose merges it automatically |

The host port lives in the override file, not the base. Production runs `compose.yaml`
alone, leaving the database reachable only on the internal Docker network. This split is how
"exposed in development, not in production" is enforced. There is no flag to remember.

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
