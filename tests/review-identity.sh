#!/usr/bin/env bash
# tests/review-identity.sh —— 审核身份可核验（scenario-03）定向测试
# 覆盖任务书四个 user 场景的正反例：
#   user_不同模型家族审核有效         → 不同 family + 各自原生 session + 证据齐 → 通过
#   user_换CLI不等于独立审核          → 不同 CLI 同 family → 拒绝并点名家族
#   user_身份未知不伪装通过           → unknown/缺字段/缺证据 → 报缺证据不通过
#   user_无审核要求的普通票不额外烧token → 无 review-required 标记 → 不启用检查
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
FAILS=0
ok()  { echo "PASS  $1"; }
bad() { echo "FAIL  $1"; FAILS=$((FAILS+1)); }

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# 健康项目骨架：真安装（与 smoke 同法），让 lint 其余各节全绿，专测「审核身份」一节
P="$TMP/proj"; mkdir -p "$P"
bash "$ROOT/bin/qwb-init.sh" "$P" >/dev/null
printf 'QWB_GATE_FAST="true"\nQWB_GATE_FULL="true"\n' >> "$P/qwbuddy/config.sh"
mkdir -p "$P/docs/reviews"
printf 'impl 原生会话转储\n' > "$P/docs/reviews/impl-session.md"
printf 'rev 原生会话转储\n'  > "$P/docs/reviews/rev-session.md"
T="$P/tasks/2099-01-01-rt.md"

mk() { # $1=review-impl 行  $2=review-rev 行（空串=不写该行）
  {
    printf '# 审核身份测试票\nstate: running\nreview-required: yes\n'
    [[ -n "${1:-}" ]] && printf '%s\n' "$1"
    [[ -n "${2:-}" ]] && printf '%s\n' "$2"
  } > "$T"
}

OUT=""; RC=0
runlint() { OUT="$(bash "$ROOT/bin/qwb-lint.sh" --project "$P" 2>&1)"; RC=$?; }

IMPL='review-impl: model=gpt-5.2-codex family=gpt cli=codex session=codex-s-001 evidence=docs/reviews/impl-session.md'
REV='review-rev: model=claude-opus-4.6 family=claude cli=claude session=claude-s-009 evidence=docs/reviews/rev-session.md'

echo "== 1. user_不同模型家族审核有效（正例）=="
mk "$IMPL" "$REV"
runlint
{ [[ "$RC" -eq 0 ]] && printf '%s' "$OUT" | grep -q '审核身份'; } \
  && ok "不同家族+各自原生session+证据齐 → LINT PASS" \
  || { bad "合法审核身份未通过（rc=${RC}）:"; printf '%s\n' "$OUT"; }

echo "== 2. 同 CLI 不同家族合法（正例）=="
mk 'review-impl: model=gpt-5.2 family=gpt cli=codex session=s-impl-1 evidence=docs/reviews/impl-session.md' \
   'review-rev: model=qwen3-max family=qwen cli=codex session=s-rev-2 evidence=docs/reviews/rev-session.md'
runlint
[[ "$RC" -eq 0 ]] && ok "同 codex CLI 不同 family → 仍 PASS" \
  || { bad "同CLI不同family被误拒（rc=${RC}）:"; printf '%s\n' "$OUT"; }

echo "== 3. user_无审核要求的普通票零负担（正例）=="
printf '# 普通票\nstate: running\n' > "$T"
runlint
[[ "$RC" -eq 0 ]] && ok "无 review-required 标记 → lint 不启用身份检查" \
  || { bad "普通票被误查（rc=${RC}）:"; printf '%s\n' "$OUT"; }
printf '%s' "$OUT" | grep -q '无 review-required' \
  && ok "lint 输出明示检查范围（跳过普通票）" || bad "lint 未明示检查范围"
printf '# 普通票2\nstate: running\nreview-required: no\n' > "$T"
runlint
[[ "$RC" -eq 0 ]] && ok "review-required: no → 不启用" || bad "review-required: no 被误查"

echo "== 4. user_换CLI不等于独立审核（反例：不同 CLI 同 family）=="
mk 'review-impl: model=gpt-5.2 family=gpt cli=codex session=s-impl-1 evidence=docs/reviews/impl-session.md' \
   'review-rev: model=gpt-4.1-mini family=gpt cli=pi session=s-rev-9 evidence=docs/reviews/rev-session.md'
runlint
[[ "$RC" -eq 1 ]] && ok "不同 CLI 同 family → lint 拒绝" || bad "同 family 竟通过（rc=${RC}）"
printf '%s' "$OUT" | grep -q '同家族' && printf '%s' "$OUT" | grep -q 'gpt' \
  && ok "报错点名同家族（gpt）" || bad "报错未点名同家族"

echo "== 5. user_身份未知不伪装通过（反例：unknown / cli 不充当 family / 缺行）=="
mk "$IMPL" \
   'review-rev: model=mystery-box family=unknown session=s-rev-9 evidence=docs/reviews/rev-session.md'
runlint
{ [[ "$RC" -eq 1 ]] && printf '%s' "$OUT" | grep -q 'unknown'; } \
  && ok "family=unknown → 报缺证据不通过" || bad "unknown family 竟通过（rc=${RC}）"

mk "$IMPL" \
   'review-rev: model=claude-opus-4.6 cli=claude session=s-rev-9 evidence=docs/reviews/rev-session.md'
runlint
[[ "$RC" -eq 1 ]] && ok "只有 cli 无 family → 拒绝（cli 不充当 family）" || bad "cli 冒充 family 竟通过"

mk "$IMPL" ''
runlint
[[ "$RC" -eq 1 ]] && ok "缺 review-rev 行 → 拒绝" || bad "缺身份行竟通过"

echo "== 6. 同一原生 session = 同一会话换角色（反例）=="
mk 'review-impl: model=gpt-5.2 family=gpt session=SAME-SESS evidence=docs/reviews/impl-session.md' \
   'review-rev: model=claude-opus-4.6 family=claude session=SAME-SESS evidence=docs/reviews/rev-session.md'
runlint
[[ "$RC" -eq 1 ]] && ok "同一原生 session 实例 → 拒绝" || bad "同 session 竟通过（rc=${RC}）"

echo "== 7. 缺字段 / 缺证据（反例）=="
mk 'review-impl: model=gpt-5.2 family=gpt evidence=docs/reviews/impl-session.md' "$REV"
runlint
[[ "$RC" -eq 1 ]] && ok "缺 session 字段 → 拒绝" || bad "缺 session 竟通过"
mk 'review-impl: family=gpt session=s-impl-1 evidence=docs/reviews/impl-session.md' "$REV"
runlint
[[ "$RC" -eq 1 ]] && ok "缺 model 字段 → 拒绝" || bad "缺 model 竟通过"
mk 'review-impl: model=gpt-5.2 family=gpt session=s-impl-1' "$REV"
runlint
[[ "$RC" -eq 1 ]] && ok "缺 evidence 字段 → 拒绝" || bad "缺 evidence 竟通过"
mk 'review-impl: model=gpt-5.2 family=gpt session=s-impl-1 evidence=docs/reviews/不存在.md' "$REV"
runlint
[[ "$RC" -eq 1 ]] && ok "evidence 路径不存在 → 拒绝" || bad "不存在的证据位置竟通过"

echo
if [[ "$FAILS" -eq 0 ]]; then echo "REVIEW-IDENTITY PASS"; exit 0; else echo "REVIEW-IDENTITY FAIL（${FAILS} 项）"; exit 1; fi
