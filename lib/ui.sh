#!/usr/bin/env bash
# Questions for install.sh. Stage scripts do not prompt.
# Prompts are Charm's gum: https://github.com/charmbracelet/gum
# The answer is written to stdout. Gum draws the prompt on stderr.

# Charm's Debian/Ubuntu instructions:
# https://github.com/charmbracelet/gum#installation
ensure_gum() {
  local id version pretty keytmp
  if command -v gum >/dev/null 2>&1; then
    return 0
  fi
  if [[ ! -r /etc/os-release ]]; then
    die "Cannot read /etc/os-release."
  fi
  id="$(. /etc/os-release && printf '%s' "${ID:-}")"
  version="$(. /etc/os-release && printf '%s' "${VERSION_ID:-}")"
  pretty="$(. /etc/os-release && printf '%s' "${PRETTY_NAME:-unknown}")"
  if [[ "${id}" != "ubuntu" || "${version}" != "24.04" ]]; then
    die "This installer targets Ubuntu 24.04. This host is ${pretty}."
  fi

  log "Installing gum for the install questions."
  export DEBIAN_FRONTEND=noninteractive
  # apt writes the package list to stdout. This function runs inside a
  # captured prompt, so that list must stay on stderr.
  if ! command -v gpg >/dev/null 2>&1 || ! command -v curl >/dev/null 2>&1; then
    apt-get update >&2
    apt-get install -y ca-certificates curl gnupg >&2
  fi
  install -d -m 0755 /etc/apt/keyrings
  keytmp="$(mktemp)"
  curl -fsSL https://repo.charm.sh/apt/gpg.key | gpg --dearmor >"${keytmp}"
  install -m 0644 "${keytmp}" /etc/apt/keyrings/charm.gpg
  rm -f "${keytmp}"
  printf 'deb [signed-by=/etc/apt/keyrings/charm.gpg] https://repo.charm.sh/apt/ * *\n' >/etc/apt/sources.list.d/charm.list
  apt-get update >&2
  apt-get install -y gum >&2
  if ! command -v gum >/dev/null 2>&1; then
    die "gum was not installed."
  fi
}

gum_cancelled() {
  die "Installation aborted."
}

trim_answer() {
  local value="$1"
  value="${value#"${value%%[![:space:]]*}"}"
  value="${value%"${value##*[![:space:]]}"}"
  printf '%s' "${value}"
}

# ask "Prompt" "default"
# Enter keeps the value already shown. Clearing the field keeps the default.
ask() {
  local prompt="$1" default="$2" answer status=0
  ensure_gum
  if [[ -n "${default}" ]]; then
    answer="$(gum input --header "${prompt}" --value "${default}" --placeholder "${default}")" || status=$?
  else
    answer="$(gum input --header "${prompt}" --placeholder "${prompt}")" || status=$?
  fi
  if [[ "${status}" -ne 0 ]]; then
    gum_cancelled
  fi
  answer="$(trim_answer "${answer}")"
  if [[ -z "${answer}" ]]; then
    printf '%s' "${default}"
  else
    printf '%s' "${answer}"
  fi
}

# ask_yes_no "Prompt" "1"|"0"
# Gum confirm exits 0 for Yes and 1 for No. Ctrl+C aborts the installer.
ask_yes_no() {
  local prompt="$1" default="$2" status=0
  ensure_gum
  if [[ "${default}" == "1" ]]; then
    gum confirm --default=true "${prompt}" || status=$?
  else
    gum confirm --default=false "${prompt}" || status=$?
  fi
  if [[ "${status}" -eq 130 ]]; then
    gum_cancelled
  fi
  if [[ "${status}" -eq 0 ]]; then
    printf '1'
  else
    printf '0'
  fi
}

ask_password() {
  local answer status header
  ensure_gum
  if [[ -n "${PANEL_DB_PASSWORD:-}" ]]; then
    header="MariaDB password for pelican@127.0.0.1. Leave empty to keep the current password."
  else
    header="MariaDB password for pelican@127.0.0.1"
  fi
  while true; do
    status=0
    answer="$(gum input --password --header "${header}" --placeholder "password")" || status=$?
    if [[ "${status}" -ne 0 ]]; then
      gum_cancelled
    fi
    if [[ -n "${answer}" ]]; then
      printf '%s' "${answer}"
      return 0
    fi
    if [[ -n "${PANEL_DB_PASSWORD:-}" ]]; then
      printf '%s' "${PANEL_DB_PASSWORD}"
      return 0
    fi
    printf 'A password is required.\n' >&2
  done
}

ask_email() {
  local prompt="$1" default="$2" answer
  while true; do
    answer="$(ask "${prompt}" "${default}")"
    if [[ "${answer}" =~ ^[^@[:space:]]+@[^@[:space:]]+\.[^@[:space:]]+$ && "${answer}" != *\"* ]]; then
      printf '%s' "${answer}"
      return 0
    fi
    printf 'Enter an email address.\n' >&2
  done
}

# ui_menu "Prompt" "default-id" "id|Label" ...
# Enter selects the highlighted row. The highlighted row starts on the default id.
ui_menu() {
  local prompt="$1" default="$2"
  shift 2
  local -a ids=() labels=()
  local item id label selected="" answer status=0 i
  if [[ "$#" -eq 0 ]]; then
    die "ui_menu called without choices."
  fi
  for item in "$@"; do
    id="${item%%|*}"
    label="${item#*|}"
    if [[ "${item}" != *"|"* || -z "${id}" || -z "${label}" ]]; then
      die "ui_menu choice must be id|label."
    fi
    ids+=("${id}")
    labels+=("${label}")
    if [[ "${id}" == "${default}" ]]; then
      selected="${label}"
    fi
  done
  if [[ -z "${selected}" ]]; then
    selected="${labels[0]}"
  fi
  ensure_gum
  answer="$(gum choose --header "${prompt}" --selected "${selected}" --height "$#" "${labels[@]}")" || status=$?
  if [[ "${status}" -ne 0 ]]; then
    gum_cancelled
  fi
  for i in "${!labels[@]}"; do
    if [[ "${labels[$i]}" == "${answer}" ]]; then
      printf '%s' "${ids[$i]}"
      return 0
    fi
  done
  die "Unknown choice ${answer}."
}
