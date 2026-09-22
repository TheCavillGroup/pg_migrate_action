#!/usr/bin/env bash
#
# migrate.sh — apply Postgres schema migrations in CI/CD
#
# Usage:
#   DATABASE_URL="postgres://user:pass@host:5432/dbname" ./migrate.sh
#
# Optional env vars:
#   MIGRATIONS_DIR   Directory of .sql files (default: ./migrations)
#   DRY_RUN          If "true", print what would run without applying it
#   SCHEMA           Schema to run migrations against (default: public)
#
# Migration file naming convention:
#   0001_create_users_table.sql
#   0002_add_email_index.sql
#   (leading numeric prefix determines order; must be unique)
#
# Each file is applied inside its own transaction. A migrations table
# tracks what has already been applied and a checksum of its contents,
# so the script is safe to re-run and will fail loudly if a previously
# applied file has been edited after the fact.

set -euo pipefail

MIGRATIONS_DIR="${MIGRATIONS_DIR:-./migrations}"
DRY_RUN="${DRY_RUN:-false}"
SCHEMA="${SCHEMA:-public}"

if [[ -z "${DATABASE_URL:-}" ]]; then
    echo "ERROR: DATABASE_URL is not set." >&2
    exit 1
fi

if [[ ! -d "$MIGRATIONS_DIR" ]]; then
    echo "ERROR: migrations directory '$MIGRATIONS_DIR' does not exist." >&2
    exit 1
fi

if ! command -v psql >/dev/null 2>&1; then
    echo "ERROR: psql is not installed on this runner." >&2
    exit 1
fi

PSQL="psql -v ON_ERROR_STOP=1 -X -q -A -t"

echo "==> Ensuring schema '${SCHEMA}' exists"

# CREATE SCHEMA IF NOT EXISTS still requires CREATE privilege on the database
# even when the schema already exists, so check first — this lets roles that
# only have privileges on their own pre-created schema run migrations fine.
SCHEMA_EXISTS="$($PSQL "$DATABASE_URL" -c \
    "SELECT 1 FROM pg_namespace WHERE nspname = '${SCHEMA}';")"

if [[ -n "$SCHEMA_EXISTS" ]]; then
    echo "    schema already exists, skipping creation"
else
    $PSQL "$DATABASE_URL" -c "CREATE SCHEMA \"${SCHEMA}\";"
fi

export PGOPTIONS="--search_path=${SCHEMA}"

echo "==> Ensuring schema_migrations table exists"
$PSQL "$DATABASE_URL" <<'SQL'
CREATE TABLE IF NOT EXISTS schema_migrations (
    version      TEXT PRIMARY KEY,
    checksum     TEXT NOT NULL,
    applied_at   TIMESTAMPTZ NOT NULL DEFAULT now()
);
SQL

# Collect migration files, sorted by filename (numeric prefix controls order)
mapfile -t FILES < <(find "$MIGRATIONS_DIR" -maxdepth 1 -type f -name '*.sql' | sort)

if [[ ${#FILES[@]} -eq 0 ]]; then
    echo "No .sql files found in $MIGRATIONS_DIR — nothing to do."
    exit 0
fi

APPLIED_COUNT=0

for FILE in "${FILES[@]}"; do
    VERSION="$(basename "$FILE" .sql)"
    CHECKSUM="$(sha256sum "$FILE" | awk '{print $1}')"

    EXISTING_CHECKSUM="$($PSQL "$DATABASE_URL" -c \
        "SELECT checksum FROM schema_migrations WHERE version = '${VERSION}';")"

    if [[ -n "$EXISTING_CHECKSUM" ]]; then
        if [[ "$EXISTING_CHECKSUM" != "$CHECKSUM" ]]; then
            echo "ERROR: '${VERSION}' has already been applied but its checksum" >&2
            echo "       has changed. Never edit an applied migration — add a new" >&2
            echo "       migration file instead." >&2
            exit 1
        fi
        echo "==> Skipping ${VERSION} (already applied)"
        continue
    fi

    echo "==> Applying ${VERSION}"

    if [[ "$DRY_RUN" == "true" ]]; then
        echo "    (dry run — not executed)"
        continue
    fi

    # Run the migration and record it in the same transaction, so a
    # failure partway through the migration leaves nothing recorded.
    {
        cat "$FILE"
        echo
        echo "INSERT INTO schema_migrations (version, checksum) VALUES ('${VERSION}', '${CHECKSUM}');"
    } | $PSQL "$DATABASE_URL" -1

    APPLIED_COUNT=$((APPLIED_COUNT + 1))
done

echo "==> Done. Applied ${APPLIED_COUNT} new migration(s)."