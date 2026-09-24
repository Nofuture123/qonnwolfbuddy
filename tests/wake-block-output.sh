#!/usr/bin/env bash
# 公开 CLI：--block 多轮等待只交最终摘要；人读模式仍显示逐票跳过。
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd -P)"
PROJECT="$(mktemp -d /tmp/qwb-wake-output.XXXXXXXX)"
trap 'rm -rf "$PROJECT"' EXIT
bash "$ROOT/bin/qwb-init.sh" "$PROJECT" >/dev/null
if [[ -n "${QWB_TEST_WAKE_SOURCE:-}" ]]; then cp "$QWB_TEST_WAKE_SOURCE" "$PROJECT/qwbuddy/bin/qwb-wake.sh"; fi
printf 'QWB_WAKE_INTERVAL_MS=10\nQWB_REWAKE_MS=60000\n' >> "$PROJECT/qwbuddy/config.sh"
TICKET="$PROJECT/tasks/2099-01-01-output.md"
FP="$(printf 'running\n' | shasum | cut -d' ' -f1)"
printf '# output\nstate: running\nwake: %s state=running fp=%s\n' \
  "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$FP" > "$TICKET"

once="$(env -u HERDR_PANE_ID bash "$PROJECT/qwbuddy/bin/qwb-wake.sh" --project "$PROJECT" --once)"
[[ "$once" == *"跳过：2099-01-01-output.md"* ]] || { echo "FAIL --once 跳过日志变化" >&2; exit 1; }
dry="$(env -u HERDR_PANE_ID bash "$PROJECT/qwbuddy/bin/qwb-wake.sh" --project "$PROJECT" --dry-run)"
[[ "$dry" == *"跳过：2099-01-01-output.md"* ]] || { echo "FAIL --dry-run 跳过日志变化" >&2; exit 1; }

cat > "$PROJECT/sleep-hook.sh" <<'EOF'
#!/usr/bin/env bash
n="$(cat "$QWB_TEST_COUNTER")"
n=$((n + 1))
printf '%s\n' "$n" > "$QWB_TEST_COUNTER"
if [[ "$n" -eq 2 ]]; then printf 'done: 多轮等待后完成\n' >> "$QWB_TEST_TICKET"; fi
EOF
chmod +x "$PROJECT/sleep-hook.sh"
printf '0\n' > "$PROJECT/sleep-count"
set +e
out="$(env -u HERDR_PANE_ID QWB_SLEEP_CMD="$PROJECT/sleep-hook.sh" \
  QWB_TEST_COUNTER="$PROJECT/sleep-count" QWB_TEST_TICKET="$TICKET" \
  bash "$PROJECT/qwbuddy/bin/qwb-wake.sh" --project "$PROJECT" --block --max-ms 5000)"
rc=$?
set -e
[[ "$rc" -eq 2 && "$(cat "$PROJECT/sleep-count")" -eq 2 \
  && "$out" == *"看账本：1 张未结项有进展"* \
  && "$out" == *"done: 多轮等待后完成"* \
  && "$out" != *"跳过："* ]] \
  || { printf 'FAIL --block rc=%s sleeps=%s stdout=%s\n' "$rc" "$(cat "$PROJECT/sleep-count")" "$out" >&2; exit 1; }

printf '# output\nstate: running\n' > "$TICKET"
set +e
out="$(env -u HERDR_PANE_ID bash "$PROJECT/qwbuddy/bin/qwb-wake.sh" --project "$PROJECT" --block --max-ms 5000)"
rc=$?
set -e
[[ "$rc" -eq 2 && "$out" == *"最近: 尚无状态行"* ]] \
  || { printf 'FAIL 空状态行 rc=%s stdout=%s\n' "$rc" "$out" >&2; exit 1; }

echo "WAKE BLOCK OUTPUT PASS: multi-round summary only; once/dry-run unchanged; empty status explicit"
