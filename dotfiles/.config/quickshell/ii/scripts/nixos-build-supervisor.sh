#!/usr/bin/env bash
# Runs as root from NixosConfigBuild. Keeps the build in its own process group
# so the GUI can cancel the whole rebuild, not just the pkexec wrapper.
set -u

mode="${1:-quick}"
log="/var/log/nixos-build.log"
cancel="${QS_CANCEL_FILE:-}"

session_user="${QS_USER:-}"
session_xdg="${XDG_RUNTIME_DIR:-}"
session_sig="${HYPRLAND_INSTANCE_SIGNATURE:-}"
session_home=""
session_state_home=""
reopen="${QS_REOPEN_EDITOR:-1}"
marker="${QS_REOPEN_MARKER:-}"

discover_session() {
  local pid="${PPID:-}"
  local depth=0
  local key value sig xdg user home state_home
  while [ -n "$pid" ] && [ "$pid" -gt 1 ] && [ "$depth" -lt 12 ]; do
    if [ -r "/proc/$pid/environ" ]; then
      sig=""
      xdg=""
      user=""
      home=""
      state_home=""
      while IFS='=' read -r key value; do
        case "$key" in
          HYPRLAND_INSTANCE_SIGNATURE) sig="$value" ;;
          XDG_RUNTIME_DIR) xdg="$value" ;;
          USER) user="$value" ;;
          HOME) home="$value" ;;
          XDG_STATE_HOME) state_home="$value" ;;
        esac
      done < <(tr '\0' '\n' < "/proc/$pid/environ" 2>/dev/null)
      if [ -n "$sig" ] && [ -n "$user" ]; then
        session_user="$user"
        session_xdg="$xdg"
        session_sig="$sig"
        session_home="$home"
        session_state_home="$state_home"
        return 0
      fi
    fi
    pid="$(ps -o ppid= -p "$pid" 2>/dev/null | tr -d ' ')"
    depth=$((depth + 1))
  done
  return 1
}

write_reopen_marker() {
  [ "$reopen" = "1" ] || return 0
  [ -n "$marker" ] && [ -n "$session_user" ] || return 0
  local dir
  dir="$(dirname -- "$marker")"
  if [ "$(id -u)" -eq 0 ] && command -v runuser >/dev/null 2>&1; then
    runuser -u "$session_user" -- sh -c 'mkdir -p -- "$1" && rm -f -- "$2" && : > "$2"' sh "$dir" "$marker" 2>/dev/null || true
  else
    mkdir -p -- "$dir" 2>/dev/null || true
    : > "$marker" 2>/dev/null || true
  fi
}

# Выполняет hyprctl от имени владельца графической сессии.
run_hyprctl() {
  [ -n "$session_user" ] && [ -n "$session_sig" ] && [ -n "$session_xdg" ] || return 0
  local hyprctl_bin
  hyprctl_bin="$(command -v hyprctl 2>/dev/null)" || return 0
  [ -S "$session_xdg/hypr/$session_sig/.socket.sock" ] || return 0
  if [ "$(id -u)" -eq 0 ] && command -v runuser >/dev/null 2>&1; then
    runuser -u "$session_user" -- env \
      XDG_RUNTIME_DIR="$session_xdg" \
      HYPRLAND_INSTANCE_SIGNATURE="$session_sig" \
      "$hyprctl_bin" "$@"
    return $?
  fi
  env \
    XDG_RUNTIME_DIR="$session_xdg" \
    HYPRLAND_INSTANCE_SIGNATURE="$session_sig" \
    "$hyprctl_bin" "$@"
}

reload_hyprland() {
  run_hyprctl reload >/dev/null 2>&1 || true
}

restart_hyprland() {
  # Hyprland 0.56+ с Lua-конфигом принимает только Lua-диспетчеры
  # (hyprctl dispatch 'hl.dsp.exit()'). Старый синтаксис — fallback.
  run_hyprctl dispatch 'hl.dsp.exit()' >/dev/null 2>&1 && return 0
  run_hyprctl dispatch exit >/dev/null 2>&1 || true
}

resolve_session() {
  if [ -z "$session_user" ] || [ -z "$session_sig" ] || [ -z "$session_xdg" ] || [ -z "$marker" ]; then
    discover_session || true
  fi
  if [ -z "$session_home" ] && [ -n "$session_user" ]; then
    session_home="$(getent passwd "$session_user" 2>/dev/null | cut -d: -f6)"
  fi
  if [ -z "$session_xdg" ] && [ -n "$session_user" ]; then
    session_xdg="/run/user/$(id -u "$session_user" 2>/dev/null || true)"
  fi
  if [ -z "$session_state_home" ] && [ -n "$session_home" ]; then
    session_state_home="$session_home/.local/state"
  fi
  if [ -z "$marker" ] && [ -n "$session_state_home" ]; then
    marker="$session_state_home/nixos-config-reopen"
  fi
}

case "$mode" in
  full) task="./update.sh" ;;
  quick) task="./update.sh --quick" ;;
  *) printf 'nixos-build-supervisor: unknown mode: %s\n' "$mode" >&2; exit 2 ;;
esac

cd /etc/nixos || exit 1
umask 022

# /var/log belongs to root, so a user cannot pre-create a symlink here and
# make the root build truncate an arbitrary file.
rm -f -- "$log"
: > "$log"

setsid script -qefc "$task" /dev/null > "$log" 2>&1 &
child=$!

watcher=""
if [ -n "$cancel" ]; then
  # The marker only needs to be checked; root must not write to it.
  (
    while kill -0 "$child" 2>/dev/null; do
      if [ -e "$cancel" ]; then
        kill -TERM -- "-$child" 2>/dev/null || true
        sleep 2
        kill -KILL -- "-$child" 2>/dev/null || true
        exit 0
      fi
      sleep 1
    done
  ) &
  watcher=$!
fi

wait "$child"
status=$?

if [ -n "$watcher" ]; then
  kill "$watcher" 2>/dev/null || true
  wait "$watcher" 2>/dev/null || true
fi

sed -i 's/\^@//g' "$log" 2>/dev/null || true

# script sometimes exits successfully after its child was killed; report a
# cancellation as a non-zero status so the UI does not say "finished".
if [ -n "$cancel" ] && [ -e "$cancel" ] && [ "$status" -eq 0 ]; then
  status=130
fi

if [ "$status" -eq 0 ]; then
  resolve_session
  if [ -n "$session_user" ] && [ -n "$session_sig" ] && [ -n "$session_xdg" ]; then
    if [ "$mode" = "quick" ]; then
      printf '==> Перезагружаю конфиг Hyprland...\n' >> "$log" 2>/dev/null || true
      reload_hyprland
    else
      write_reopen_marker
      printf '==> Перезапускаю Hyprland...\n' >> "$log" 2>/dev/null || true
      restart_hyprland
    fi
  else
    printf '==> Hyprland reload/restart skipped: session not found\n' >> "$log" 2>/dev/null || true
  fi
fi

exit "$status"
