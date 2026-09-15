#!/usr/bin/env bash
# qwb-lint.sh —— QW buddy 自身规范检查：能自动检查的规范不只写在纸上
set -uo pipefail

usage() {
  cat <<'EOF'
用法: qwb-lint.sh [--project <根>]

逐项检查并输出 PASS/FAIL，任一 FAIL → 退出码 1：
  1. 文档承诺的脚本必须存在（QWBUDDY.md 与 docs/DESIGN.md 点名的 qwb-*.sh；qwb-init.sh 为母本仓专用安装器除外）
  2. tasks/*.md 的 state: 值 ∈ running|blocked|needs-decision|done|verified（有字段但值为空同样 FAIL；无字段的非任务文档跳过）
  3. config 无死键（QWB_X=… 与 export QWB_X=… 都算声明；非注释行出现 $QWB_X / ${QWB_X} 才算被读取）
  4. 无「变量后紧跟非 ASCII」写法（应写成 ${VAR} 形式；扫描 bin/*.sh 全部脚本）
  5. 质量门已声明（QWB_GATE_FAST / QWB_GATE_FULL 均非空）
  6. 已派发任务书（带 scenarios-fp:）的验收场景仍在且指纹未变（派发后改场景即 FAIL）；
     带 scenarios-revised: 修订记录的票，再核对最新一条记录的 new= 指纹 == 当前基线

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

shopt -s nullglob
binsh=( "$BINDIR"/*.sh )

echo "== 1. 文档承诺的脚本必须存在 =="
# qwb-init.sh 是母本仓专用安装器、不装进目标项目 → 从「文档点名必存在」清单剔除
names="$(grep -ohE 'qwb-[a-z0-9-]+\.sh' "${DOCS[@]}" | sort -u | grep -v '^qwb-init\.sh$')"
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
bad_states=""
for f in "$PROJECT_ROOT"/tasks/*.md; do
  grep -q '^state:' "$f" || continue   # 无 state 字段行 → 非任务书（如 lessons.md），跳过
  st="$(sed -n 's/^state:[[:space:]]*//p' "$f" | head -1 | tr -d '[:space:]')"
  if [[ -z "$st" ]]; then
    bad_states="${bad_states} $(basename "$f")=<空值>"   # 有 state: 字段但值为空 → FAIL
    continue
  fi
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
  if [[ ${#binsh[@]} -eq 0 ]]; then
    dead="（${BINDIR} 无任何脚本，所有键皆为死键）"
  else
    # 声明形式：QWB_X=… 与 export QWB_X=… 都算
    while IFS= read -r k; do
      [[ -n "$k" ]] || continue
      # 「被引用」= 非注释行里出现真实变量读取 $QWB_X / ${QWB_X}（R2-M3）；
      # 纯赋值（QWB_X=…）、不带 $ 的字面量（echo QWB_X）、整行注释都不算
      grep -hE '\$[{]?'"$k"'([^A-Za-z0-9_]|$)' "${binsh[@]}" 2>/dev/null \
        | grep -vE '^[[:space:]]*#' | grep -q . \
        || dead="${dead} ${k}"
    done < <(sed 's/^export[[:space:]][[:space:]]*//' "$CONF" | sed -n 's/^\(QWB_[A-Z_]*\)=.*/\1/p')
  fi
  if [[ -z "$dead" ]]; then
    pass "${CONF} 的 QWB_* 键全部被 ${BINDIR} 引用"
  else
    fail "死配置（bin/ 无引用）:${dead}"
  fi
else
  fail "找不到配置文件（试过 qwbuddy/config.sh 与 qwb.config.sh）"
fi

echo "== 4. 变量后紧跟非 ASCII 字符 =="
hits=""
[[ ${#binsh[@]} -gt 0 ]] \
  && hits="$(perl -ne 'print "$ARGV:$.: $&\n" while /\$[A-Za-z_][A-Za-z0-9_]*[^\x00-\x7F]/g' "${binsh[@]}" 2>/dev/null)"
if [[ -z "$hits" ]]; then
  pass "${BINDIR}/*.sh 无该写法"
else
  fail "发现该写法（应写成 \${VAR} 形式）：
${hits}"
fi

echo "== 5. 质量门已声明 =="
# 门未声明（空值）是配置缺失，不许静默当绿：新装项目一跑 lint 就会被提醒
if [[ -f "$CONF" ]] && (
  # shellcheck source=/dev/null
  . "$CONF" >/dev/null 2>&1
  [[ -n "${QWB_GATE_FAST:-}" && -n "${QWB_GATE_FULL:-}" ]]
); then
  pass "QWB_GATE_FAST / QWB_GATE_FULL 均已声明"
else
  fail "质量门未声明：${CONF} 里 QWB_GATE_FAST / QWB_GATE_FULL 须非空（按本项目布局填写，示例见该文件注释）"
fi

echo "== 6. 已派发任务书的验收场景与冻结 =="
# 验收场景块界定与 qwb-run.sh 派发门一致；带 scenarios-fp: 的任务书（经派发门写过基线的）
# 重算当前块指纹比对，不一致即 FAIL；有 dispatch: 但无 scenarios-fp: 的是旧制派发，警告不 FAIL。
# 带 scenarios-revised: 修订记录的票（经 --revise-scenarios 显式改过场景）：最新一条记录的
# new= 指纹必须等于当前基线——没有修订参数的场景差异仍然 FAIL（区分显式改票与无痕偷改）。
scenario_block() {
  awk '
    inblk==0 && /^#{1,6}[^#]*验收场景/ { inblk=1; print; next }
    inblk==1 && (/^#{1,2}[^#]/ || /^(working|done|blocked|needs-decision|dispatch|wake|worktree|scenarios-fp):/) { inblk=0 }
    inblk==1 { print }
  ' "$1"
}
scen_bad=""
for f in "$PROJECT_ROOT"/tasks/*.md; do
  grep -q '^state:' "$f" || continue
  declared_fp="$(sed -n 's/^scenarios-fp:[[:space:]]*//p' "$f" | head -1 | tr -d '[:space:]')"
  if [[ -z "$declared_fp" ]]; then
    grep -q '^dispatch:' "$f" \
      && echo "警告：$(basename "$f") 有 dispatch: 但无 scenarios-fp（旧制派发，无冻结基线）" >&2
    continue
  fi
  blk="$(scenario_block "$f")"
  if [[ -z "$blk" ]]; then
    scen_bad="${scen_bad} $(basename "$f")(验收场景块缺失)"
    continue
  fi
  # 存在性与失败路径同派发门标准
  if ! { printf '%s\n' "$blk" | grep -q 'Given' \
      && printf '%s\n' "$blk" | grep -q 'When' \
      && printf '%s\n' "$blk" | grep -q 'Then'; } \
    && [[ "$(printf '%s\n' "$blk" | grep -cE '^#{1,6}[[:space:]]+user_' || true)" -lt 2 ]]; then
    scen_bad="${scen_bad} $(basename "$f")(无可识别场景)"
    continue
  fi
  printf '%s\n' "$blk" | grep -E '^#{1,6}|^[[:space:]]*Then' \
    | grep -qiE '失败|拒绝|报错|异常|负例|非法|fail|error' \
    || { scen_bad="${scen_bad} $(basename "$f")(无失败路径场景)"; continue; }
  cur_fp="$(printf '%s' "$blk" | shasum | cut -d' ' -f1)"
  [[ "$cur_fp" == "$declared_fp" ]] \
    || scen_bad="${scen_bad} $(basename "$f")(验收场景在派发后被改动)"
  # 修订记录核对：最新一条 scenarios-revised: 的 new= 指纹 == 当前基线
  lastrev="$(grep -E '^working:[[:space:]]*scenarios-revised:' "$f" | tail -1 || true)"
  if [[ -n "$lastrev" ]]; then
    revnew="$(printf '%s' "$lastrev" | sed -n 's/^working:[[:space:]]*scenarios-revised:[[:space:]]*old=[0-9a-f]\{40\}[[:space:]]\{1,\}new=\([0-9a-f]\{40\}\).*/\1/p')"
    [[ -n "$revnew" && "$revnew" == "$declared_fp" ]] \
      || scen_bad="${scen_bad} $(basename "$f")(最新修订记录 new= 指纹与当前基线不一致)"
  fi
done
if [[ -z "$scen_bad" ]]; then
  pass "带 scenarios-fp 的任务书场景均未在派发后被改动"
else
  fail "验收场景检查失败:${scen_bad}"
fi

echo
if [[ "$FAILS" -eq 0 ]]; then echo "LINT PASS"; exit 0; else echo "LINT FAIL（${FAILS} 项）"; exit 1; fi
