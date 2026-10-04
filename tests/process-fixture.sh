# Source before starting fixture processes. The supervisor owns this exact test.
export PYTHONDONTWRITEBYTECODE=1
QWB_TEST_PROCESS_HELPER="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)/process_fixture.py"
qwb_test_scope() {
  export QWB_TEST_SHELL="$BASH"
  if [[ "${QWB_TEST_SCOPE_SCRIPT:-}" != "$0" || "${QWB_TEST_SUPERVISOR_PID:-}" != "$PPID" ]]; then
    exec python3 "$QWB_TEST_PROCESS_HELPER" "$0" "$@"
  fi
  export QWB_TEST_GROUP="$$"
  trap 'exit 130' INT
  trap 'exit 143' TERM
}
qwb_test_drain() {
  python3 "$QWB_TEST_PROCESS_HELPER" drain
}
qwb_test_register() { python3 "$QWB_TEST_PROCESS_HELPER" register "$1"; }
qwb_test_release() { python3 "$QWB_TEST_PROCESS_HELPER" release "$1"; }
