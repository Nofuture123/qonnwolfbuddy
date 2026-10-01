#!/usr/bin/env bash
# One control owner; delegate to the same role registry/launch path, never spawn a second runtime.
set -euo pipefail
case "${1:-}" in
  interrupt|exit|relaunch) ;;
  -h|--help) echo "用法: qwb-control.sh interrupt|exit|relaunch --project <根> --actor <id> --expect-gen <代次>"; exit 0 ;;
  *) echo "错误：需要interrupt|exit|relaunch" >&2; exit 2 ;;
esac
exec bash "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)/qwb-role.sh" "$@"
