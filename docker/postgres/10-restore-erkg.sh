#!/bin/bash
# Restore the pre-loaded, entity-resolved, geocoded workshop database.
#
# Postgres runs this exactly once: on first start with an empty data directory,
# right after it creates the database named by POSTGRES_DB. It runs against a
# temporary server listening on the unix socket ONLY - which is why the
# healthcheck in docker-compose.yml connects over TCP. That keeps the service
# "unhealthy" until this finishes, so nothing starts against a half-restored
# database.
set -euo pipefail

DUMP=/opt/erkg/erkg.dump

echo "Restoring the pre-loaded workshop database into '${POSTGRES_DB}'..."

pg_restore \
    --username "${POSTGRES_USER}" \
    --dbname "${POSTGRES_DB}" \
    --jobs 4 \
    --no-owner \
    --no-privileges \
    "$DUMP"

# The sandbox: a second database holding an empty Senzing repository, so
# attendees can register a data source and load their own records under the
# free 500-record licence. Kept separate from the main database on purpose -
# that one is already far past the free limit and is read-only for them.
echo "Creating the empty sandbox repository..."
psql --username "${POSTGRES_USER}" --dbname "${POSTGRES_DB}" \
    --command "CREATE DATABASE sandbox" > /dev/null
pg_restore \
    --username "${POSTGRES_USER}" \
    --dbname sandbox \
    --no-owner \
    --no-privileges \
    /opt/erkg/sandbox.dump

records=$(psql --username "${POSTGRES_USER}" --dbname "${POSTGRES_DB}" \
    --tuples-only --no-align --command "SELECT count(*) FROM dsrc_record")
geo=$(psql --username "${POSTGRES_USER}" --dbname "${POSTGRES_DB}" \
    --tuples-only --no-align --command "SELECT count(*) FROM workshop.entity_geo")

echo "Restore complete: ${records} records already entity-resolved, ${geo} geocoded."
