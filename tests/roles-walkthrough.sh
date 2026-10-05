#!/usr/bin/env bash
# The land entry owns process registration, fail-closed Herdr isolation and socket cleanup.
set -euo pipefail
exec bash "$(dirname "${BASH_SOURCE[0]}")/collab-land.sh" walkthrough
