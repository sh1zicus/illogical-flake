#!/usr/bin/env bash
# Runs as root from NixosConfigBuild. Keeps the build in its own process group
# so the GUI can cancel the whole rebuild, not just the pkexec wrapper.
set -u

mode="${1:-quick}"
log="/var/log/nixos-build.log"
cancel="${QS_CANCEL_FILE:-}"

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

# script sometimes exits successfully after its child was killed; report a
# cancellation as a non-zero status so the UI does not say "finished".
if [ -n "$cancel" ] && [ -e "$cancel" ] && [ "$status" -eq 0 ]; then
  status=130
fi

exit "$status"
