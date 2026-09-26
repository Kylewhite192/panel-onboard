#!/usr/bin/env bash
# Remembers a run so a later install can skip finished stages.
# Choices live in state.env. Passwords and APP_KEY live in secrets.env.
# Neither file is written during a dry-run.

installer_file_set() {
  local file="$1" key="$2" value="$3" tmp
  if [[ "${value}" == *$'\n'* || "${key}" == *$'\n'* ]]; then
    die "Installer state cannot contain a newline."
  fi
  install -d -m 700 "$(dirname "${file}")"
  # Write the whole file, then rename it. mv on the same directory replaces
  # the previous file in one step, so a crash cannot leave a half-written state.
  tmp="$(mktemp "${file}.tmp.XXXXXX")"
  if [[ -f "${file}" ]]; then
    grep -v "^${key}=" "${file}" >"${tmp}" || true
  fi
  printf '%s=%s\n' "${key}" "${value}" >>"${tmp}"
  chmod 600 "${tmp}"
  mv -f "${tmp}" "${file}"
}

installer_file_get() {
  local file="$1" key="$2" line
  [[ -f "${file}" ]] || return 1
  line="$(grep "^${key}=" "${file}" | tail -n 1 || true)"
  [[ -n "${line}" ]] || return 1
  printf '%s' "${line#*=}"
}

state_init() {
  install -d -m 700 "${INSTALLER_STATE_DIR}"
  touch "${INSTALLER_STATE}" "${INSTALLER_LOG}"
  chmod 600 "${INSTALLER_STATE}" "${INSTALLER_LOG}"
  INSTALLER_LOGGING=1
  export INSTALLER_LOGGING
  if ! installer_file_get "${INSTALLER_STATE}" INSTALLER_VERSION >/dev/null; then
    installer_file_set "${INSTALLER_STATE}" INSTALLER_VERSION "${INSTALLER_VERSION}"
  fi
  log "Installer state: ${INSTALLER_STATE}"
  log "Installer log: ${INSTALLER_LOG}"
}

state_set() {
  installer_file_set "${INSTALLER_STATE}" "$1" "$2"
}

state_get() {
  installer_file_get "${INSTALLER_STATE}" "$1"
}

state_is_complete() {
  local value=""
  value="$(state_get "stage_$1" || true)"
  [[ "${value}" == "complete" ]]
}

state_clear_stages() {
  local tmp
  tmp="$(mktemp "${INSTALLER_STATE}.tmp.XXXXXX")"
  grep -v '^stage_' "${INSTALLER_STATE}" >"${tmp}" || true
  chmod 600 "${tmp}"
  mv -f "${tmp}" "${INSTALLER_STATE}"
}

warn_installer_version() {
  local saved=""
  saved="$(state_get INSTALLER_VERSION || true)"
  if [[ -n "${saved}" && "${saved}" != "${INSTALLER_VERSION}" ]]; then
    log "Saved installation state: ${saved}"
    log "Current installer:         ${INSTALLER_VERSION}"
    log "This state was written by a different installer version. Finished stages may not match these scripts."
  fi
}

log_new_run() {
  local stamp
  stamp="$(date -Iseconds)"
  {
    printf '==================================================\n'
    printf 'New installation run\n'
    printf '%s\n' "${stamp}"
    printf '==================================================\n'
  } >&2
  if [[ "${INSTALLER_LOGGING:-0}" == "1" ]]; then
    {
      printf '==================================================\n'
      printf 'New installation run\n'
      printf '%s\n' "${stamp}"
      printf '==================================================\n'
    } >>"${INSTALLER_LOG}"
  fi
}

state_save_choices() {
  local key
  state_set INSTALLER_VERSION "${INSTALLER_VERSION}"
  for key in INSTALL_MODE PANEL_DOMAIN PANEL_HTTPS PANEL_WEBSERVER PHP_VERSION \
    PANEL_DATABASE PANEL_REDIS PANEL_DIR PANEL_FIREWALL PANEL_CERTBOT \
    WINGS_DOMAIN CERTBOT_EMAIL APP_URL ADMIN_EMAIL DOCKER_DIR DOCKER_UPSTREAM_IP; do
    state_set "${key}" "${!key-}"
  done
}

state_load_choices() {
  local key value
  for key in INSTALL_MODE PANEL_DOMAIN PANEL_HTTPS PANEL_WEBSERVER PHP_VERSION \
    PANEL_DATABASE PANEL_REDIS PANEL_DIR PANEL_FIREWALL PANEL_CERTBOT \
    WINGS_DOMAIN CERTBOT_EMAIL APP_URL ADMIN_EMAIL DOCKER_DIR DOCKER_UPSTREAM_IP; do
    if value="$(state_get "${key}")"; then
      printf -v "${key}" '%s' "${value}"
      export "${key}"
    fi
  done
}

secrets_set() {
  install -d -m 700 "${INSTALLER_STATE_DIR}"
  touch "${INSTALLER_SECRETS}"
  chmod 600 "${INSTALLER_SECRETS}"
  installer_file_set "${INSTALLER_SECRETS}" "$1" "$2"
}

secrets_get() {
  installer_file_get "${INSTALLER_SECRETS}" "$1"
}

secrets_save_app_key() {
  local value="$1"
  value="${value#"${value%%[![:space:]]*}"}"
  value="${value%"${value##*[![:space:]]}"}"
  value="${value#\"}"
  value="${value%\"}"
  value="${value#\'}"
  value="${value%\'}"
  if [[ -z "${value}" || "${value}" == "base64:" ]]; then
    return 0
  fi
  secrets_set APP_KEY "${value}"
  log "Saved the application key to ${INSTALLER_SECRETS}."
}

secrets_save_app_key_file() {
  local envfile="$1" line value
  [[ -f "${envfile}" ]] || return 0
  line="$(grep '^APP_KEY=' "${envfile}" | tail -n 1 || true)"
  [[ -n "${line}" ]] || return 0
  value="${line#APP_KEY=}"
  secrets_save_app_key "${value}"
}

show_install_status() {
  printf 'Stage status:\n' >&2
  if [[ -f "${INSTALLER_STATE}" ]]; then
    grep '^stage_' "${INSTALLER_STATE}" >&2 || true
  fi
  if [[ -f "${INSTALLER_LOG}" ]]; then
    printf 'Last lines of %s:\n' "${INSTALLER_LOG}" >&2
    tail -n 40 "${INSTALLER_LOG}" >&2 || true
  fi
}

# 0 means resume with the saved choices. 1 means ask the questions again.
offer_resume() {
  local choice value
  [[ -f "${INSTALLER_STATE}" ]] || return 1
  grep -q '^stage_' "${INSTALLER_STATE}" || return 1
  warn_installer_version
  while true; do
    choice="$(ui_menu "Previous Pelican installation detected" resume \
      "resume|Resume installation" \
      "details|View failure details" \
      "restart|Start again" \
      "exit|Exit")"
    case "${choice}" in
      resume) return 0 ;;
      details) show_install_status ;;
      restart)
        state_load_choices
        if value="$(secrets_get PANEL_DB_PASSWORD)"; then
          PANEL_DB_PASSWORD="${value}"
          export PANEL_DB_PASSWORD
        fi
        log_new_run
        state_clear_stages
        return 1
        ;;
      exit) exit 0 ;;
    esac
  done
}
