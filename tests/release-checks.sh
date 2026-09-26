#!/usr/bin/env bash
# State, redaction, checksum parsing, and secret-hygiene checks.
# These do not install packages and do not need root.
set -euo pipefail
cd "$(dirname "$0")/.."

tmp="$(mktemp -d)"
trap 'rm -rf "${tmp}"' EXIT
export INSTALLER_STATE_DIR="${tmp}/state"
export INSTALLER_STATE="${tmp}/state/state.env"
export INSTALLER_SECRETS="${tmp}/state/secrets.env"
export INSTALLER_SUMMARY="${tmp}/state/summary.txt"
export INSTALLER_LOG="${tmp}/installer.log"
# shellcheck disable=SC1091
source scripts/lib.sh

state_init
state_set stage_install-php complete
state_set stage_install-wings failed
state_is_complete install-php
if state_is_complete install-wings; then
  echo "A failed stage was treated as complete." >&2
  exit 1
fi
state_clear_stages
if grep -q '^stage_' "${INSTALLER_STATE}"; then
  echo "Start again left stage markers behind." >&2
  exit 1
fi

secrets_set APP_KEY 'base64:abc+def/ghi='
PANEL_DB_PASSWORD='s3cret*'
redacted="$(printf '%s\n' \
  'plain text' \
  'password s3cret* stays literal' \
  'APP_KEY=base64:abc+def/ghi=' \
  'Generated app key: base64:should-not-appear' \
  | redact_stream)"
grep -qxF 'plain text' <<<"${redacted}"
grep -qxF 'password [redacted] stays literal' <<<"${redacted}"
grep -qxF 'APP_KEY=[redacted]' <<<"${redacted}"
grep -qxF '[redacted application key]' <<<"${redacted}"
if grep -q 's3cret' <<<"${redacted}"; then
  echo "Password survived redaction." >&2
  exit 1
fi
if grep -q 'base64:abc' <<<"${redacted}" || grep -q 'should-not-appear' <<<"${redacted}"; then
  echo "Application key survived redaction." >&2
  exit 1
fi

payload="${tmp}/panel.tar.gz"
printf 'panel' >"${payload}"
hash="$(sha256sum "${payload}" | awk '{ print $1 }')"
printf '%s  panel.tar.gz\n' "${hash}" >"${tmp}/checksum.txt"
verify_sha256_file "${payload}" "${tmp}/checksum.txt" "panel.tar.gz"
printf '0000000000000000000000000000000000000000000000000000000000000000  panel.tar.gz\n' >"${tmp}/checksum-bad.txt"
if ( verify_sha256_file "${payload}" "${tmp}/checksum-bad.txt" "panel.tar.gz" ) >/dev/null 2>&1; then
  echo "A bad checksum was accepted." >&2
  exit 1
fi
tag="$(release_tag_from_url "https://github.com/pelican/panel/releases/download/v1.0.0-beta38/panel.tar.gz")"
[[ "${tag}" == "v1.0.0-beta38" ]]
if release_tag_from_url "https://release-assets.githubusercontent.com/github-production-release-asset/1/abc?sp=r" >/dev/null; then
  echo "A CDN download URL was accepted as a release tag." >&2
  exit 1
fi

export INSTALLER_LOGGING=1
export INSTALLER_STAGE=install-mariadb
export INSTALLER_DIE_FOOTER=1
set +e
footer="$(die "boom" 2>&1)"
footer_status=$?
set -e
[[ "${footer_status}" -eq 1 ]]
grep -q 'Installation failed during: install-mariadb' <<<"${footer}"
grep -q 'You can rerun the installer to resume.' <<<"${footer}"
grep -Fq "Log:" <<<"${footer}"
grep -Fq "${INSTALLER_LOG}" <<<"${footer}"
if grep -q 's3cret' "${INSTALLER_LOG}"; then
  echo "Password reached the installer log." >&2
  exit 1
fi

if grep -nE '(^|[[:space:]])set[[:space:]]+-[A-Za-z]*x' install.sh lib/*.sh scripts/*.sh tests/*.sh; then
  echo "set -x would trace secrets into the log." >&2
  exit 1
fi
if grep -nE 'log[[:space:]]+.*PANEL_DB_PASSWORD|log[[:space:]]+.*\$\{?key_line|log[[:space:]]+"\$\{key_line\}"' \
  install.sh lib/*.sh scripts/*.sh; then
  echo "A log call includes a password or the Docker app-key line." >&2
  exit 1
fi

echo "release_checks_ok"
