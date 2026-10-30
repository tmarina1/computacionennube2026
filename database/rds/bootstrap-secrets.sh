#!/usr/bin/env bash

set -euo pipefail

# ============================================================
# File: bootstrap-secrets.sh
# Purpose:
#
# Run bootstrap.sh with the three database passwords read from
# AWS Secrets Manager instead of written in bootstrap.env.
#
# Usage:
#   ./bootstrap-secrets.sh           read secrets and run bootstrap.sh
#   ./bootstrap-secrets.sh --check   read secrets and verify them only
#
# Required secret ids (each secret is a JSON with a "password" field):
#   DB_ADMIN_SECRET_ID    -> DB_ADMIN_PASSWORD
#   DB_APP_SECRET_ID      -> APP_DB_PASSWORD
#   DB_INGEST_SECRET_ID   -> INGEST_DB_PASSWORD
#
# Region: AWS_REGION, or us-east-1.
#
# Precedence (how bootstrap.sh reads its configuration):
#   bootstrap.sh loads bootstrap.env only when DB_HOST is empty,
#   and that file OVERRIDES variables already exported. To keep the
#   Secrets Manager passwords from being replaced by the CHANGE_ME
#   placeholders, this wrapper loads bootstrap.env itself first (when
#   DB_HOST is empty), then exports the passwords from Secrets
#   Manager, so bootstrap.sh finds DB_HOST defined and skips the file.
#   Passwords live only in this process and its child; nothing is
#   written to disk.
# ============================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_FILE="${SCRIPT_DIR}/bootstrap.env"
REGION="${AWS_REGION:-us-east-1}"

CHECK_ONLY=false

fail() {
    printf 'ERROR: %s\n' "$1" >&2
    exit 1
}

case "${1:-}" in
    "") ;;
    --check) CHECK_ONLY=true ;;
    *) fail "Unknown argument: $1 (only --check is supported)" ;;
esac

for tool in aws jq; do
    command -v "${tool}" >/dev/null 2>&1 \
        || fail "${tool} is not installed or is not available in PATH."
done

: "${DB_ADMIN_SECRET_ID:?DB_ADMIN_SECRET_ID is required}"
: "${DB_APP_SECRET_ID:?DB_APP_SECRET_ID is required}"
: "${DB_INGEST_SECRET_ID:?DB_INGEST_SECRET_ID is required}"

# Non-secret configuration: from the environment or bootstrap.env.
if [[ "${CHECK_ONLY}" == false && -z "${DB_HOST:-}" ]]; then
    [[ -f "${ENV_FILE}" ]] \
        || fail "DB_HOST is not set and bootstrap.env was not found. Set the environment variables or copy bootstrap.env.example to bootstrap.env."

    set -a
    # shellcheck disable=SC1090
    source "${ENV_FILE}"
    set +a
fi

if [[ "${CHECK_ONLY}" == false ]]; then
    : "${DB_HOST:?DB_HOST is required}"
    : "${DB_ADMIN_USER:?DB_ADMIN_USER is required}"
fi

# Prints the password of a secret on stdout; messages never include values.
read_password() {
    local secret_id="$1"
    local secret_string
    local password

    secret_string="$(aws secretsmanager get-secret-value \
        --region "${REGION}" \
        --secret-id "${secret_id}" \
        --query SecretString \
        --output text 2>/dev/null)" \
        || fail "Could not read secret ${secret_id} from Secrets Manager."

    password="$(jq -er '.password' <<<"${secret_string}" 2>/dev/null)" \
        || fail "Secret ${secret_id} has no valid \"password\" field."

    [[ -n "${password}" ]] \
        || fail "Secret ${secret_id} has an empty \"password\" field."

    printf '%s' "${password}"
}

DB_ADMIN_PASSWORD="$(read_password "${DB_ADMIN_SECRET_ID}")"
APP_DB_PASSWORD="$(read_password "${DB_APP_SECRET_ID}")"
INGEST_DB_PASSWORD="$(read_password "${DB_INGEST_SECRET_ID}")"

if [[ "${CHECK_ONLY}" == true ]]; then
    printf 'OK: %s campo password\n' \
        "${DB_ADMIN_SECRET_ID}" "${DB_APP_SECRET_ID}" "${DB_INGEST_SECRET_ID}"
    exit 0
fi

export DB_ADMIN_PASSWORD APP_DB_PASSWORD INGEST_DB_PASSWORD

printf 'Passwords loaded from Secrets Manager: %s, %s, %s (field password)\n' \
    "${DB_ADMIN_SECRET_ID}" "${DB_APP_SECRET_ID}" "${DB_INGEST_SECRET_ID}"

exec /bin/bash "${SCRIPT_DIR}/bootstrap.sh"
