#!/usr/bin/env bash
#
# build_database_url.sh — construct a postgres:// URL from discrete fields.
#
# Reads DB_USERNAME, DB_PASSWORD, DB_HOST, DB_PORT and DB_NAME from the
# environment, percent-encodes the username and password (so special
# characters like @ : / don't break the URL), and prints the result to
# stdout.

set -euo pipefail
export LC_ALL=C

for VAR in DB_USERNAME DB_PASSWORD DB_HOST DB_NAME; do
    if [[ -z "${!VAR:-}" ]]; then
        echo "ERROR: ${VAR} is not set." >&2
        exit 1
    fi
done

DB_PORT="${DB_PORT:-5432}"

urlencode() {
    local string="$1" strlen pos c o encoded=""
    strlen=${#string}
    for (( pos=0; pos<strlen; pos++ )); do
        c="${string:pos:1}"
        case "$c" in
            [a-zA-Z0-9.~_-]) o="$c" ;;
            *) printf -v o '%%%02X' "'$c" ;;
        esac
        encoded+="$o"
    done
    printf '%s' "$encoded"
}

ENC_USERNAME="$(urlencode "$DB_USERNAME")"
ENC_PASSWORD="$(urlencode "$DB_PASSWORD")"

echo "postgres://${ENC_USERNAME}:${ENC_PASSWORD}@${DB_HOST}:${DB_PORT}/${DB_NAME}"
