#!/bin/sh
# Runs once, only when the postgres-data volume is first created (Postgres's
# own entrypoint convention for docker-entrypoint-initdb.d/). Adds PianoPogo's
# database to this shared Postgres server, owned by the same POSTGRES_USER
# that already owns ModuloWorld's database.
set -eu

psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname "$POSTGRES_DB" \
  -c "CREATE DATABASE \"${PIANO_POGO_POSTGRES_DB}\" OWNER \"${POSTGRES_USER}\";"
