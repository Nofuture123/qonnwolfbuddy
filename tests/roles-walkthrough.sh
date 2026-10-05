#!/usr/bin/env bash
# The land entry owns process registration, fail-closed Herdr isolation and socket cleanup.
set -euo pipefail
if [[ -n "${QWB_WALK_REVISION:-}" || -n "${QWB_R4_PROBE:-}" ]]; then
  exec bash "$(dirname "${BASH_SOURCE[0]}")/collab-land.sh" walkthrough
fi
for timing in before dispatched; do
  QWB_WALK_REVISION="$timing" bash "$(dirname "${BASH_SOURCE[0]}")/collab-land.sh" walkthrough
done
