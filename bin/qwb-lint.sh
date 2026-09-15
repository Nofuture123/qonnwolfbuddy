#!/usr/bin/env bash
# qwb-lint.sh —— QW buddy 自身规范检查：能自动检查的规范不只写在纸上
set -uo pipefail

usage() {
  cat <<'EOF'
用法: qwb-lint.sh [--project <根>]

逐项检查并输出 PASS/FAIL，任一 FAIL → 退出码 1：
  1. 文档承诺的脚本必须存在（QWBUDDY.md 与 docs/DESIGN.md 点名的 qwb-*.sh）
  2. tasks/*.md 的 state: 值 ∈ running|blocked|needs-decision|done|verified
  3. config 无死键（每个 QWB_* 变量都被某个 bin/*.sh 引用）
  4. 无「变量后紧跟非 ASCII」写法（应写成 ${VAR} 形式）

布局：装了 qwbuddy/ 的项目 → qwbuddy/QWBUDDY.md + qwbuddy/bin/；
      母本仓（模板源）       → templates/QWBUDDY.md + bin/，配置回退 qwb.config.sh。

选项:
  --project <根>    项目根（默认：当前目录）
  -h, --help        显示本帮助
EOF
}

PROJECT_ROOT="$(pwd)"
while [[ $# -gt 0 ]]; do
  case "$1" in
    -h|--help) usage; exit 0 ;;
    --project) PROJECT_ROOT="$2"; shift 2 ;;
    *) echo "错误：未知参数 $1" >&2; usage >&2; exit 2 ;;
  esac
done
[[ -d "$PROJECT_ROOT" ]] || { echo "错误：项目根不存在：${PROJECT_ROOT}" >&2; exit 1; }
PROJECT_ROOT="$(cd "$PROJECT_ROOT" && pwd)"

FAILS=0
pass() { echo "PASS  $1"; }
fail() { echo "FAIL  $1"; FAILS=$((FAILS+1)); }

# 布局识别：安装版（qwbuddy/）或母本仓（templates/ + bin/）
DOCS=()
if [[ -f "$PROJECT_ROOT/qwbuddy/QWBUDDY.md" ]]; then
  BINDIR="$PROJECT_ROOT/qwbuddy/bin"; DOCS+=("$PROJECT_ROOT/qwbuddy/QWBUDDY.md")
elif [[ -f "$PROJECT_ROOT/templates/QWBUDDY.md" ]]; then
  BINDIR="$PROJECT_ROOT/bin"; DOCS+=("$PROJECT_ROOT/templates/QWBUDDY.md")
else
  echo "错误：${PROJECT_ROOT} 下找不到 QWBUDDY.md（qwbuddy/ 或 templates/）" >&2; exit 2
fi
[[ -f "$PROJECT_ROOT/docs/DESIGN.md" ]] && DOCS+=("$PROJECT_ROOT/docs/DESIGN.md")

echo "== 1. 文档承诺的脚本必须存在 =="
names="$(grep -ohE 'qwb-[a-z0-9-]+\.sh' "${DOCS[@]}" | sort -u)"
missing=""
for n in $names; do
  [[ -f "$BINDIR/$n" ]] || missing="${missing} ${n}"
done
if [[ -z "$missing" ]]; then
  pass "文档点名的 $(printf '%s' "$names" | wc -w | tr -d ' ') 个脚本在 ${BINDIR} 全部存在"
else
  fail "文档点名但 ${BINDIR} 缺失:${missing}"
fi

echo "== 2. 账本 state 合法 =="
shopt -s nullglob
bad_states=""
for f in "$PROJECT_ROOT"/tasks/*.md; do
  st="$(sed -n 's/^state:[[:space:]]*//p' "$f" | head -1 | tr -d '[:space:]')"
  [[ -z "$st" ]] && continue
  case "$st" in
    running|blocked|needs-decision|done|verified) ;;
    *) bad_states="${bad_states} $(basename "$f")=${st}" ;;
  esac
done
if [[ -z "$bad_states" ]]; then
  pass "tasks/*.md 的 state 值全部合法"
else
  fail "非法 state:${bad_states}"
fi

echo "== 3. config 无死键 =="
CONF="$PROJECT_ROOT/qwbuddy/config.sh"
[[ -f "$CONF" ]] || CONF="$PROJECT_ROOT/qwb.config.sh"
if [[ -f "$CONF" ]]; then
  dead=""
  while IFS= read -r k; do
    [[ -n "$k" ]] || continue
    grep -q "$k" "$BINDIR"/qwb-*.sh || dead="${dead} ${k}"
  done < <(sed -n 's/^\(QWB_[A-Z_]*\)=.*/\1/p' "$CONF")
  if [[ -z "$dead" ]]; then
    pass "${CONF} 的 QWB_* 键全部被 ${BINDIR} 引用"
  else
    fail "死配置（bin/ 无引用）:${dead}"
  fi
else
  fail "找不到配置文件（试过 qwbuddy/config.sh 与 qwb.config.sh）"
fi

echo "== 4. 变量后紧跟非 ASCII 字符 =="
hits="$(perl -ne 'print "$ARGV:$.: $&\n" while /\$[A-Za-z_][A-Za-z0-9_]*[^\x00-\x7F]/g' "$BINDIR"/qwb-*.sh 2>/dev/null)"
if [[ -z "$hits" ]]; then
  pass "${BINDIR}/*.sh 无该写法"
else
  fail "发现该写法（应写成 \${VAR} 形式）：
${hits}"
fi

echo
if [[ "$FAILS" -eq 0 ]]; then echo "LINT PASS"; exit 0; else echo "LINT FAIL（${FAILS} 项）"; exit 1; fi
