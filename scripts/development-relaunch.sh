#!/bin/zsh
# Install only after the old app exits normally. Never signal or kill the app.
set -eu
old_pid=${1:?Usage: development-relaunch.sh OLD_PID ROOT}
root=${2:?Missing project root}
[[ "$old_pid" == <-> && "$old_pid" -gt 1 ]] || exit 1
staged="$root/.local/development/Diorama.app"
target="$root/dist/Diorama.app"
previous="$root/.local/development/Previous-Diorama.app"
for attempt in {1..120}; do
  if ! /bin/kill -0 "$old_pid" 2>/dev/null; then
    /usr/bin/codesign --verify --deep --strict "$staged"
    # The backup is a generated build, retained until the next successful update.
    if [[ -d "$previous" ]]; then /bin/rm -rf "$previous"; fi
    if [[ -d "$target" ]]; then /bin/mv "$target" "$previous"; fi
    if ! /bin/mv "$staged" "$target"; then
      [[ ! -d "$previous" ]] || /bin/mv "$previous" "$target"
      exit 1
    fi
    /usr/bin/open "$target"
    echo "Installed and launched updated Diorama"
    exit 0
  fi
  /bin/sleep 1
done
echo "App did not exit; leaving the current app untouched" >&2
exit 1
