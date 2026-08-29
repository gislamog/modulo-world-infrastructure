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
| `compose.yaml` | Base definition — true in every environment |
| `compose.override.yaml` | Local development only; Compose merges it automatically |

The host port lives in the override file, not the base. Production runs `compose.yaml`
alone, leaving the database reachable only on the internal Docker network. This split is how
"exposed in development, not in production" is enforced — there is no flag to remember.

## Data

Postgres data is stored in the `postgres-data` named volume, which survives
`docker compose down`.

> **`docker compose down -v` deletes the volume**, and with it the entire database. The
> difference from the harmless command is two characters.

Credentials are read only when the volume is first created. Changing them in `.env` afterwards
has no effect on an existing database; the volume must be recreated for a change to apply.

## Common commands

```bash
docker compose logs postgres    # why it is not healthy
docker compose exec postgres psql -U "$POSTGRES_USER" -d "$POSTGRES_DB"
docker compose down             # stop, keeping data
```
