#!/usr/bin/env bash
# qwb-run.sh —— 派发 + 记账：在指定 worktree/窗口里派活，把窗口、派发时间、state: running 写进任务书
set -euo pipefail
export LC_ALL=C  # 场景、疑点与状态行按原始字节解析；损坏 UTF-8 不得绕过派发门。

usage() {
  cat <<'EOF'
用法: qwb-run.sh --task <任务id或任务书路径> --worker <工人名> [选项]

必选:
  --task <id|路径>      任务书 id（如 qwbuddy-mvp）或文件路径
  --worker <名>         工人名（须在 config.sh 的 QWB_WORKERS 里整词精确匹配，如 codex/pi/claude）
                        auto=JEV 自动派工（qwb-dispatch.sh 按 qwbuddy/dispatch-rules.json 选工人；
                        off/error/ambiguous 落默认工人不阻塞派发；规则文件坏则拒绝派发）

选项:
  --project <根>        项目根（默认：当前目录）
  --worktree <路径>     在既有 worktree 目录里派活（新窗口的 cwd）
  --create-worktree     先开 <根>/.worktrees/<任务id> 并在 Herdr Spaces 登记（与默认行为同义）
                        隔离副本的创建是幂等的：已是本任务的有效 worktree 则复用，不重建
  --here                显式声明就在项目根派发（非隔离目录，须使用者有意选择）
  --pane <pane_id>      复用既有 pane（须为交互 shell），否则新开 herdr tab
  --name <agent名>      工人 agent 名（默认：qwb-<任务id>；任务 id 净化后只剩短残渣
                         ——如中文 id 被剔成 qwb--01——则兑底为 qwb-<sha1(任务id)前8位>，
                         显式给 --name 时不兑底）
  --accept-new-scenarios  主控显式确认：曾派发但丢 scenarios-fp 基线的任务书，允许重建冻结基线（留一行说明）
  --revise-scenarios=<原因>  主控显式修订验收场景：票内已有基线且场景块被有意改动时，
                         更新 scenarios-fp 并追加 working: scenarios-revised: 留痕记录（原因非空，须写明条款依据）
  -h, --help            显示本帮助

默认：不给 --worktree/--create-worktree/--here 时自动开隔离副本 .worktrees/<任务id>。
启动方式与 argv：qwbuddy/workers.sh 每工人一条 qwb_worker 声明；herdr 和 pane-run
    参数均逐项保真。旧配置须先运行母本仓 qwb-init.sh
    --migrate-worker-config <项目根>；检查在锁/worktree/tab/账本写之前完成。
新建隔离副本后、开 tab / 记账之前，config.sh 的 QWB_WORKTREE_SETUP 非空时会在副本目录里
bash -c 执行一次（如 pnpm install --offline --frozen-lockfile && cp ../../.env .env），供
monorepo 副本自装依赖/环境；stdout/stderr 透传，非 0 → 拒绝派发、副本保留供排查
（任务书无 dispatch 行、无 tab 创建）。只对新建副本执行：复用既有副本 / --here /
--worktree <既有路径> 均不跑。
项目根派发时，工人 tab 落在 config.sh 的 QWB_WORKSPACE、匹配项目根的非 linked workspace，
或带警告回退到调用者 workspace；任务 Git worktree 派发时，tab 落在其独立 Herdr Space。
--pane 仍须在目标目录的对应 Space 中，不会隐式搬动已有 pane。
派发前有验收场景门：任务书必须含「验收场景」块（Given/When/Then 或 ≥2 个 user_ 场景标题）
且至少一条失败路径场景，否则拒绝派发；通过则把场景块指纹写成 scenarios-fp: 供 lint 冻结比对。
派发前有疑点门：最后一个 spec-defect:/spec-resolved: 相关事件是 blocked: spec-defect:（未决规格疑点）
→ 拒绝派发，须由主控追加 working: spec-resolved: 处置后才放行；普通状态行不能解除疑点。
EOF
}

PROJECT_ROOT="$(pwd)"; TASK=""; WORKER=""; WORKTREE=""; CREATE_WT=0; HERE=0; PANE=""; NAME=""; ACCEPT_NEW=0
REVISE=""; REVISE_GIVEN=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    -h|--help) usage; exit 0 ;;
    --task) TASK="$2"; shift 2 ;;
    --worker) WORKER="$2"; shift 2 ;;
    --project) PROJECT_ROOT="$2"; shift 2 ;;
    --worktree) WORKTREE="$2"; shift 2 ;;
    --create-worktree) CREATE_WT=1; shift ;;
    --here) HERE=1; shift ;;
    --pane) PANE="$2"; shift 2 ;;
    --name) NAME="$2"; shift 2 ;;
    --accept-new-scenarios) ACCEPT_NEW=1; shift ;;
    --revise-scenarios=*) REVISE="${1#*=}"; REVISE_GIVEN=1; shift ;;
    *) echo "错误：未知参数 $1" >&2; usage >&2; exit 2 ;;
  esac
done
[[ -n "$TASK" && -n "$WORKER" ]] || { echo "错误：--task 与 --worker 必选" >&2; usage >&2; exit 2; }
if [[ "$HERE" -eq 1 && ( -n "$WORKTREE" || "$CREATE_WT" -eq 1 ) ]]; then
  echo "错误：--here 与 --worktree/--create-worktree 互斥" >&2; exit 2
fi
command -v herdr >/dev/null 2>&1 || { echo "错误：找不到 herdr 命令" >&2; exit 1; }
[[ -d "$PROJECT_ROOT" ]] || { echo "错误：项目根不存在：${PROJECT_ROOT}" >&2; exit 1; }
PROJECT_ROOT="$(cd "$PROJECT_ROOT" && pwd)"
LEDGER="$PROJECT_ROOT/tasks"
CONF="$PROJECT_ROOT/qwbuddy/config.sh"
# 共享库（resolve_workspace 等；qwb-wake.sh 用同一份，两处不各写一份）
LIB="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/qwb-lib.sh"
[[ -f "$LIB" ]] || { echo "错误：找不到共享库 ${LIB}——安装副本不完整（旧版安装缺此文件），请用母本仓重跑 bin/qwb-init.sh 更新（幂等）" >&2; exit 1; }
# shellcheck source=/dev/null
. "$LIB"

# 定位任务书：路径直接用；id 先找「文件名去日期前缀与 .md 后 == 给定 id」的精确命中，
# 恰好一份就用它；没有精确命中才退回子串匹配（多份仍报错——子串 glob 会把
# watch-invisible 与 watch-invisible-pi 同时命中，精确 id 必须优先）
if [[ -f "$TASK" ]]; then
  TASK_FILE="$(cd "$(dirname "$TASK")" && pwd)/$(basename "$TASK")"
else
  exact=()
  for f in "$LEDGER"/*.md; do
    [[ -e "$f" ]] || continue
    [[ "$(basename "$f" .md | sed 's/^[0-9][0-9-]*-//')" == "$TASK" ]] && exact+=("$f")
  done
  if [[ ${#exact[@]} -eq 1 ]]; then
    TASK_FILE="${exact[0]}"
  else
    hits=()
    for f in "$LEDGER"/*"$TASK"*.md; do [[ -e "$f" ]] && hits+=("$f"); done
    [[ ${#hits[@]} -eq 1 ]] || { echo "错误：任务 '${TASK}' 在 ${LEDGER} 匹配到 ${#hits[@]} 份（要唯一）" >&2; exit 1; }
    TASK_FILE="${hits[0]}"
  fi
fi
# 任务 id = 文件名去日期前缀与扩展名
TASK_ID="$(basename "$TASK_FILE" .md | sed 's/^[0-9][0-9-]*-//')"
[[ -n "$TASK_ID" ]] || TASK_ID="$(basename "$TASK_FILE" .md)"
if grep -q '^state:' "$TASK_FILE"; then
  task_state="$(qwb_task_state "$TASK_FILE")"
  case "$task_state" in
    running|blocked|needs-decision|done|verified) ;;
    *) echo "错误：任务书 state 非法（${task_state}），须主控查看，拒绝派发" >&2; exit 1 ;;
  esac
fi

# 工人须在 config.sh 的 QWB_WORKERS 里；启动定义另见 workers.sh。
[[ -f "$CONF" ]] || { echo "错误：找不到 ${CONF}（先跑 qwb-init.sh）" >&2; exit 1; }
unset QWB_WORKER_LAUNCH QWB_WORKER_ARGS
QWB_WORKERS=""; QWB_AGENT_START_MS=""; QWB_WORKTREE_SETUP=""
# shellcheck source=/dev/null
. "$CONF"
if [[ ${QWB_WORKER_LAUNCH+x} || ${QWB_WORKER_ARGS+x} ]]; then
  echo "错误：检测到旧 QWB_WORKER_LAUNCH / QWB_WORKER_ARGS；先运行母本仓 bin/qwb-init.sh --migrate-worker-config '$PROJECT_ROOT'，不可直接派发" >&2
  exit 1
fi
WORKERS_CONF="$PROJECT_ROOT/qwbuddy/workers.sh"
[[ -f "$WORKERS_CONF" ]] || { echo "错误：缺少 ${WORKERS_CONF}；若 QWB_WORKERS 是定制表，请按 templates/workers.sh 手动创建逐工人声明；旧长串配置须显式迁移，默认配置可重跑母本仓 bin/qwb-init.sh" >&2; exit 1; }
QWB_CONFIG_NAMES=(); QWB_CONFIG_MODES=(); QWB_CONFIG_OFFSETS=(); QWB_CONFIG_COUNTS=(); QWB_CONFIG_ARGV=()
has_headless_arg() { [[ "$1" == -p || "$1" == --print || "$1" == --exec || "$1" == exec || "$1" == -p=* || "$1" == --print=* || "$1" == --exec=* || "$1" == exec=* ]]; }
qwb_worker() {
  local name="${1:-}" mode="${2:-}" known seen
  shift 2 || { echo "错误：workers.sh 声明缺少工人名或启动方式" >&2; return 1; }
  known=0
  for seen in $QWB_WORKERS; do [[ "$seen" == "$name" ]] && known=1; done
  [[ "$known" -eq 1 ]] || { echo "错误：workers.sh 有未知工人 '${name}'（不在 QWB_WORKERS）" >&2; return 1; }
  for seen in "${QWB_CONFIG_NAMES[@]+"${QWB_CONFIG_NAMES[@]}"}"; do
    [[ "$seen" == "$name" ]] && { echo "错误：workers.sh 工人 '${name}' 重复启动定义" >&2; return 1; }
  done
  case "$mode" in
    herdr) ;;
    pane-run) [[ $# -ge 1 && -n "$1" ]] || { echo "错误：工人 '${name}' 的 pane-run 须有非空可执行文件" >&2; return 1; } ;;
    *) echo "错误：工人 '${name}' 启动方式 '${mode}' 非法（herdr / pane-run）" >&2; return 1 ;;
  esac
  QWB_CONFIG_NAMES+=("$name"); QWB_CONFIG_MODES+=("$mode")
  QWB_CONFIG_OFFSETS+=("${#QWB_CONFIG_ARGV[@]}"); QWB_CONFIG_COUNTS+=("$#")
  QWB_CONFIG_ARGV+=("$@")
}
# shellcheck source=/dev/null
. "$WORKERS_CONF"
listed=()
for w in $QWB_WORKERS; do
  for seen in "${listed[@]+"${listed[@]}"}"; do
    [[ "$seen" == "$w" ]] && { echo "错误：QWB_WORKERS 中工人 '${w}' 重复" >&2; exit 1; }
  done
  listed+=("$w")
  count=0
  for seen in "${QWB_CONFIG_NAMES[@]+"${QWB_CONFIG_NAMES[@]}"}"; do [[ "$seen" == "$w" ]] && count=$((count+1)); done
  [[ "$count" -eq 1 ]] || { echo "错误：工人 '${w}' 在 workers.sh 缺少唯一启动定义" >&2; exit 1; }
done
# —— auto 派工：先解析成具体工人再走下面的整词校验（opt-in；本块在任何副作用之前）——
# clear → 解析出的工人；off/error/ambiguous → 默认工人（规则文件的 default.worker，无规则文件则 pi），
# stderr 一行说明，不阻塞派发；qwb-dispatch 非零退出（规则文件坏等配置错误）→ 拒绝派发，不许绕过。
if [[ "$WORKER" == "auto" ]]; then
  DISPATCH_BIN="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/qwb-dispatch.sh"
  [[ -f "$DISPATCH_BIN" ]] || { echo "错误：找不到 ${DISPATCH_BIN}——安装副本不完整，请用母本仓重跑 bin/qwb-init.sh 更新" >&2; exit 1; }
  DP_ERR="$(mktemp)"
  DP_RC=0
  DP_OUT="$(bash "$DISPATCH_BIN" "$TASK_FILE" --project "$PROJECT_ROOT" --json 2>"$DP_ERR")" || DP_RC=$?
  if [[ "$DP_RC" -ne 0 ]]; then
    cat "$DP_ERR" >&2; rm -f "$DP_ERR"
    echo "错误：auto 派工配置错误（qwb-dispatch 退出码 ${DP_RC}）——修好 qwbuddy/dispatch-rules.json 后重派；本次派发未发生、无副作用。" >&2
    exit "$DP_RC"
  fi
  # JSON 是唯一机器契约。必须是单个对象，字段与状态匹配；诊断文字不参与选择。
  if ! printf '%s\n' "$DP_OUT" | jq -s -e '
    length == 1 and (.[0] |
    type == "object" and
    (.status == "clear" or .status == "off" or .status == "error" or .status == "ambiguous") and
    (.default_worker | type == "string" and test("^[^[:space:][:cntrl:]]+$")) and
    ((has("reason") | not) or (.reason | type == "string")) and
    (if .status == "clear" then
      (.worker | type == "string" and test("^[^[:space:][:cntrl:]]+$"))
     else (has("worker") | not) end))
  ' >/dev/null 2>&1; then
    cat "$DP_ERR" >&2; rm -f "$DP_ERR"
    echo "错误：auto 派工结构化结果非法，拒绝派发（无副作用）" >&2
    exit 2
  fi
  DP_STATUS="$(jq -r '.status' <<<"$DP_OUT")"
  if [[ "$DP_STATUS" == "clear" ]]; then
    WORKER="$(jq -r '.worker' <<<"$DP_OUT")"
    echo "qwb-run: auto 派工命中 → ${WORKER}" >&2
  else
    WORKER="$(jq -r '.default_worker' <<<"$DP_OUT")"
    DP_REASON="$(jq -r '.reason // empty' <<<"$DP_OUT")"
    { cat "$DP_ERR"; echo "qwb-run: auto 派工未命中（status=${DP_STATUS}${DP_REASON:+，${DP_REASON}}），按默认工人 ${WORKER} 继续派发"; } >&2
  fi
  rm -f "$DP_ERR"
fi

# 整词精确匹配：空格分隔逐词比对，不做子串/正则匹配（'workers'、'(codex)' 这类都混不过）
wfound=0
for w in $QWB_WORKERS; do
  [[ "$w" == "$WORKER" ]] && wfound=1 && break
done
if [[ "$wfound" -eq 0 ]]; then
  echo "错误：工人 '${WORKER}' 不在 config.sh 的 QWB_WORKERS 里（合法工人：${QWB_WORKERS}）" >&2
  exit 1
fi
START_MS="${QWB_AGENT_START_MS:-30000}"
WORKER_ARGV=(); PANE_COMMAND=""
for i in "${!QWB_CONFIG_NAMES[@]}"; do
  [[ "${QWB_CONFIG_NAMES[i]}" == "$WORKER" ]] || continue
  LAUNCH_MODE="${QWB_CONFIG_MODES[i]}"
  offset="${QWB_CONFIG_OFFSETS[i]}"; count="${QWB_CONFIG_COUNTS[i]}"
  for ((j=0; j<count; j++)); do WORKER_ARGV+=("${QWB_CONFIG_ARGV[offset+j]}"); done
  break
done
for arg in "${WORKER_ARGV[@]+"${WORKER_ARGV[@]}"}"; do
  has_headless_arg "$arg" && { echo "错误：工人 '${WORKER}' 参数含 headless 形式：${arg}" >&2; exit 1; }
done
if [[ "$LAUNCH_MODE" == pane-run ]]; then
  quote_shell_arg() {
    local rest="$1" quoted="'"
    while [[ "$rest" == *"'"* ]]; do
      quoted="${quoted}${rest%%\'*}'\\''"
      rest="${rest#*\'}"
    done
    printf "%s%s'" "$quoted" "$rest"
  }
  PANE_COMMAND=""
  for arg in "${WORKER_ARGV[@]}"; do
    quoted="$(quote_shell_arg "$arg")"
    PANE_COMMAND="${PANE_COMMAND:+${PANE_COMMAND} }${quoted}"
  done
fi
NAME_GIVEN=0
[[ -n "$NAME" ]] && NAME_GIVEN=1
NAME="${NAME:-qwb-$TASK_ID}"
NAME="$(printf '%s' "$NAME" | cut -c1-32 | tr '[:upper:]' '[:lower:]' | tr -cd 'a-z0-9_-')"
# agent 名塔缩兑底：中文任务 id 经 tr 净化后可能只剩短残渣（如 场景完善-01真实闭环 →
# qwb--01），两票同名。仅在未显式给 --name 时兑底为 qwb-<sha1(任务id) 前 8 位>；
# 有效名（剩余字母数字 ≥ 3 个）保持原样，ASCII id 名与现状字节一致。
if [[ "$NAME_GIVEN" -eq 0 ]] && [[ "$(printf '%s' "${NAME#qwb-}" | tr -cd 'a-z0-9' | wc -c | tr -d ' ')" -lt 3 ]]; then
  NAME="qwb-$(printf '%s' "$TASK_ID" | shasum | cut -c1-8)"
fi

# —— 常驻规则附页（brief-include）：读与校验在任何派发副作用之前 ——
# <项目根>/qwbuddy/brief-include.md 存在时，其内容原样追加为任务书最后一节「常驻附页」，
# 供项目写一次常驻规则、不必每张票重抄。路径存在但不是可读的常规文件（目录/断链/不可读）
# → 拒绝派发：配置错误不许静默跳过，也不许留下半截写入；全空白视为无附页；无附页零改动零输出。
BRIEF_INC_FILE="$PROJECT_ROOT/qwbuddy/brief-include.md"
BRIEF_INC_BODY=""
if [[ -e "$BRIEF_INC_FILE" || -L "$BRIEF_INC_FILE" ]]; then
  if [[ -f "$BRIEF_INC_FILE" ]] && BRIEF_INC_BODY="$(cat "$BRIEF_INC_FILE" 2>/dev/null)"; then
    [[ -n "$(printf '%s' "$BRIEF_INC_BODY" | tr -d '[:space:]')" ]] || BRIEF_INC_BODY=""
  else
    echo "错误：${BRIEF_INC_FILE} 必须是可读的常规文件（目录/断链/不可读均拒绝派发）" >&2
    exit 1
  fi
fi

# —— 疑点门：票上有未决「规格疑点」→ 拒绝派发，先处置后派 ——
# 相关事件 = 两类精确前缀（blocked:…spec-defect: / working:…spec-resolved:）按出现顺序取最后一个：
# 是 spec-defect: → 未决。普通 working:/done:/dispatch: 行不参与判定、不能解除疑点；
# spec-resolved: 只认主控写的处置结论，覆盖其之前全部未决疑点，之后新提的疑点重新拦截。
# 本检查在任何派发副作用（worktree/窗口/tab/state:/dispatch:）之前完成。
last_spec_ev="$(qwb_last_spec_event "$TASK_FILE")"
if printf '%s' "$last_spec_ev" | grep -qE '^blocked:[[:space:]]*spec-defect:'; then
  {
    echo "错误：任务书上有未决规格疑点，拒绝派发——疑点原文："
    printf '  %s\n' "$last_spec_ev"
    echo "处置：由主控逐项核对疑点（不能只回应最后一条），往任务书追加一行："
    echo "  working: spec-resolved: <impl|spec>；<逐项回应与证据；改票位置，或保留原票的理由>"
    echo "之后再重新派发。不要求必须开审核窗口（实质分歧/缺反例/疑点带新证据复发时才按需审票，见 roles/审核者.md）。"
    echo "改验收场景须用 --revise-scenarios=<原因> 显式修订留痕；spec-resolved: 本身不授权改场景。"
  } >&2
  exit 1
fi

# —— M1 派发门：任务书必须有「验收场景」块（先场景后代码），且至少一条失败路径场景 ——
# 验收场景块 = 首个含「验收场景」的标题行起，到下一个一/二级标题、或首条账本状态/运行时行为止
# （working:/done:/dispatch:/wake: 等行永远追加在文件尾，不得计入场景指纹）
scen_refuse() { echo "错误：$1——请按 qwbuddy/TASK.md 补验收场景（至少一条失败路径）" >&2; exit 1; }
SCEN_BLK="$(qwb_scenario_block "$TASK_FILE")"
[[ -n "$SCEN_BLK" ]] || scen_refuse "任务书没有「验收场景」块"
if ! { printf '%s\n' "$SCEN_BLK" | grep -q 'Given' \
    && printf '%s\n' "$SCEN_BLK" | grep -q 'When' \
    && printf '%s\n' "$SCEN_BLK" | grep -q 'Then'; }; then
  nuser="$(printf '%s\n' "$SCEN_BLK" | grep -cE '^#{1,6}[[:space:]]+user_' || true)"
  [[ "$nuser" -ge 2 ]] || scen_refuse "验收场景块里没有可识别场景（缺 Given/When/Then，且 user_ 场景标题不足 2 个）"
fi
printf '%s\n' "$SCEN_BLK" | grep -E '^#{1,6}|^[[:space:]]*Then' \
  | grep -qiE '失败|拒绝|报错|异常|负例|非法|fail|error' \
  || scen_refuse "验收场景里没有失败路径场景"
# 场景冻结指纹：派发时的场景块 sha1，稍后写进 state: 附近（lint 重算比对，改动即 FAIL）
SCEN_FP="$(printf '%s' "$SCEN_BLK" | shasum | cut -d' ' -f1)"

# —— 冻结基线核对（R2-M1）：再次派发不得覆盖/丢失基线 ——
# 已有 scenarios-fp: → 与当前场景块指纹比对：一致→正常派发且基线原样保留；不一致→拒绝（自家派发入口不得洗白改动）。
# 无基线但有 dispatch: → 曾派发的新制任务丢了基线，默认拒绝；主控显式 --accept-new-scenarios 才允许重建并留说明行。
# --revise-scenarios= → 显式修订通道：只处理「已有基线、场景被主控有意改动」这一种情况，指纹不比对（改动正是待留痕对象）。
DECLARED_FP="$(sed -n 's/^scenarios-fp:[[:space:]]*//p' "$TASK_FILE" | head -1 | tr -d '[:space:]')"
REBUILD_FP=0
if [[ "$REVISE_GIVEN" -eq 1 ]]; then
  # 前置校验（全过才动手；场景块结构合法性已由上面的场景门校验）：
  # 不与 --accept-new-scenarios 混用（后者只管「缺基线」）、原因非空、票内存旧指纹
  [[ "$ACCEPT_NEW" -eq 0 ]] \
    || { echo "错误：--revise-scenarios 与 --accept-new-scenarios 互斥（前者显式改基线留痕，后者只管重建缺失基线）" >&2; exit 1; }
  [[ -n "$REVISE" ]] \
    || { echo "错误：--revise-scenarios= 的原因不能为空（须写明改了哪条场景、依据哪条条款）" >&2; exit 1; }
  [[ -n "$DECLARED_FP" ]] \
    || { echo "错误：票内没有旧指纹（scenarios-fp 缺失），无从修订——缺基线的情况用 --accept-new-scenarios，不要用修订" >&2; exit 1; }
elif [[ -n "$DECLARED_FP" ]]; then
  [[ "$DECLARED_FP" == "$SCEN_FP" ]] \
    || { echo "错误：验收场景在派发后被改动：请恢复场景，或由主控用 --revise-scenarios=<原因> 显式修订留痕，或核实后删除 scenarios-fp: 行并以 --accept-new-scenarios 再派发" >&2; exit 1; }
elif grep -q '^dispatch:' "$TASK_FILE"; then
  if [[ "$ACCEPT_NEW" -eq 1 ]]; then
    REBUILD_FP=1
  else
    echo "错误：任务书有 dispatch: 但无 scenarios-fp: 冻结基线（新制任务丢基线）——由主控核实后加 --accept-new-scenarios 重建" >&2
    exit 1
  fi
fi

# —— --pane 复用预检（在任何副作用之前：锁目录、修订写、worktree/分支创建、账本写、agent 启动）——
# 目标目录先推导不创建：--here=项目根；--worktree=给定路径；其余=默认 .worktrees/<任务id>。
# pane 存在、无 agent、前台空闲 shell、cwd 与目标目录物理一致，缺一即拒并给修复步骤；
# 不往未知 TUI/异地目录发命令。目标目录不存在时也能比对（向已存在的祖先目录归一化）。
if [[ -n "$PANE" ]]; then
  if [[ "$HERE" -eq 1 ]]; then EDIR="$PROJECT_ROOT"
  elif [[ -n "$WORKTREE" ]]; then EDIR="$WORKTREE"
  else EDIR="$PROJECT_ROOT/.worktrees/$TASK_ID"; fi
  if [[ "$EDIR" != /* ]]; then EDIR="$(pwd)/$EDIR"; fi
  if [[ -d "$EDIR" ]]; then
    ecd="$(cd "$EDIR" && pwd -P)"
  else
    base="$EDIR"; tail_=""
    while [[ ! -d "$base" && "$base" != "/" && -n "$base" ]]; do
      tail_="/$(basename "$base")${tail_}"; base="$(dirname "$base")"
    done
    ecd=""; [[ -d "$base" ]] && ecd="$(cd "$base" && pwd -P)${tail_}"
  fi
  pinfo="$(herdr pane get "$PANE" 2>&1)" \
    || { echo "错误：--pane ${PANE} 无法确认（pane 不存在或查询失败）：${pinfo}" >&2; exit 1; }
  pmeta="$(printf '%s' "$pinfo" | perl -MJSON::PP=decode_json -e '
      my $j = eval { decode_json(join "", <STDIN>) } or exit 1;
      my $p = $j->{result}{pane} or exit 1;
      printf "%s\t%s", ($p->{foreground_cwd} // $p->{cwd} // ""), ($p->{agent} // "");' || true)"
  [[ -n "$pmeta" ]] \
    || { echo "错误：--pane ${PANE} 的 pane get 响应无法解析，无法确认状态" >&2; exit 1; }
  pagent="$(printf '%s' "$pmeta" | cut -f2)"
  [[ -z "$pagent" ]] \
    || { echo "错误：--pane ${PANE} 里跑着 agent（${pagent}），不是交互 shell——换个空闲 shell pane 或不带 --pane 新开 tab" >&2; exit 1; }
  pproc="$(herdr pane process-info --pane "$PANE" 2>&1)" \
    || { echo "错误：--pane ${PANE} 进程查询失败，无法确认前台空闲：${pproc}" >&2; exit 1; }
  printf '%s' "$pproc" | perl -MJSON::PP=decode_json -e '
      my $j = eval { decode_json(join "", <STDIN>) } or exit 1;
      my $pi = $j->{result}{process_info} or exit 1;
      exit((defined $pi->{foreground_process_group_id} && defined $pi->{shell_pid}
            && $pi->{foreground_process_group_id} == $pi->{shell_pid}) ? 0 : 1);' \
    || { echo "错误：--pane ${PANE} 前台被进程占用（非空闲 shell）——等它跑完或换个 pane" >&2; exit 1; }
  pcwd="$(printf '%s' "$pmeta" | cut -f1)"
  pcd="$(cd "$pcwd" 2>/dev/null && pwd -P || true)"
  [[ -n "$ecd" ]] \
    || { echo "错误：目标目录 ${EDIR} 尚不存在（默认 worktree 是派发时才建的），pane cwd 不可能已相符——修复：不带 --pane 先派发一次建出副本，或改用 --here / --worktree <已存在目录> 并先把 pane cd 到那里" >&2; exit 1; }
  [[ -n "$pcd" && "$pcd" == "$ecd" ]] \
    || { echo "错误：--pane ${PANE} 的 cwd（${pcwd:-未知}）与目标目录（${EDIR}）不符——修复：在该 pane 里先执行 cd ${EDIR} 再重跑，或不带 --pane 新开 tab" >&2; exit 1; }
  wt_kind_rc=0
  qwb_is_project_worktree "$PROJECT_ROOT" "$ecd" || wt_kind_rc=$?
  [[ "$wt_kind_rc" -ne 2 ]] || { echo "错误：无法确认 --pane 目标的 Git worktree 身份，拒绝派发" >&2; exit 1; }
  if [[ "$wt_kind_rc" -eq 0 ]]; then
    pane_space="$(qwb_worktree_space "$PROJECT_ROOT" "$ecd")" || exit 1
    [[ -n "$pane_space" ]] \
      || { echo "错误：目标 worktree 尚未在 Herdr Spaces 登记；先不带 --pane 派发，或先 herdr worktree open 后在该 Space 准备空闲 pane" >&2; exit 1; }
    actual_space="$(printf '%s' "$pinfo" | perl -MJSON::PP=decode_json -0777 -e '
      my $j=eval{decode_json(<STDIN>)}; my $v=$j->{result}{pane}{workspace_id};
      print $v if defined $v && !ref $v;' || true)"
    [[ "$actual_space" == "$pane_space" ]] \
      || { echo "错误：--pane ${PANE} 不属于目标 worktree Space ${pane_space}，拒绝投递" >&2; exit 1; }
  fi
fi

# —— 返工/续派复用既有工人（只对 herdr 模式新开 tab 的路径；--pane 与 pane-run 不参与）——
# 同名 agent 存在（按名字查询）且状态 idle/done → 复用：不建 tab、不 agent start，
# dispatch: 行的 pane 写它现有的 pane，直接 agent prompt 续派（提示词前加返工/续派说明）；
# working/blocked → 拒绝派发（工人还在干，别打断）；查询失败（非 not_found）→ fail-closed 拒绝。
# 应答里 agent 名与本任务名不同或缺身份字段 → 拒绝，不猜接收者。
REUSE_PANE=""
TAB_ID=""
validate_reuse() {
  local expected_dir actual_dir expected_ws caller_info pane_out pane_meta
  local pane_id pane_kind pane_cwd pane_ws pane_dir last_dispatch hist_dir
  if [[ "$HERE" -eq 1 ]]; then expected_dir="$PROJECT_ROOT"
  elif [[ -n "$WORKTREE" ]]; then expected_dir="$WORKTREE"
  else expected_dir="$PROJECT_ROOT/.worktrees/$TASK_ID"; fi
  expected_dir="$(cd "$expected_dir" 2>/dev/null && pwd -P)" \
    || { echo "错误：复用目标目录不存在，拒绝投递" >&2; return 1; }
  actual_dir="$(cd "$ag_cwd" 2>/dev/null && pwd -P)" \
    || { echo "错误：复用工人 cwd 无法确认：$ag_cwd" >&2; return 1; }
  local wt_kind_rc=0
  qwb_is_project_worktree "$PROJECT_ROOT" "$expected_dir" || wt_kind_rc=$?
  [[ "$wt_kind_rc" -ne 2 ]] || { echo "错误：无法确认复用目标的 Git worktree 身份，拒绝派发" >&2; return 1; }
  if [[ "$wt_kind_rc" -eq 0 ]]; then
    expected_ws="$(qwb_worktree_space "$PROJECT_ROOT" "$expected_dir")" || return 1
    [[ -n "$expected_ws" ]] \
      || { echo "错误：目标 worktree 尚未在 Herdr Spaces 登记，拒绝复用历史工人" >&2; return 1; }
  else
    expected_ws="$(resolve_workspace "$PROJECT_ROOT")" || return 1
  fi
  if [[ -z "$expected_ws" ]]; then
    expected_ws="${HERDR_WORKSPACE_ID:-}"
    if [[ -z "$expected_ws" && -n "${HERDR_PANE_ID:-}" ]]; then
      caller_info="$(herdr pane get "$HERDR_PANE_ID" 2>&1)" \
        || { echo "错误：无法查询调用者 workspace：$caller_info" >&2; return 1; }
      expected_ws="$(printf '%s' "$caller_info" | perl -MJSON::PP=decode_json -0777 -e '
        my $j=eval{decode_json(<STDIN>)}; my $w=$j->{result}{pane}{workspace_id};
        print $w if defined $w && !ref $w;' || true)"
    fi
  fi
  [[ -n "$expected_ws" ]] \
    || { echo "错误：无法确认复用目标 workspace，拒绝投递" >&2; return 1; }
  pane_out="$(herdr pane get "$ag_pane" 2>&1)" \
    || { echo "错误：复用 pane $ag_pane 查询失败：$pane_out" >&2; return 1; }
  pane_meta="$(printf '%s' "$pane_out" | perl -MJSON::PP=decode_json -0777 -e '
    my $j=eval{decode_json(<STDIN>)}; my $p=$j->{result}{pane};
    exit 1 unless ref $p eq "HASH";
    my $cwd=$p->{foreground_cwd}//$p->{cwd};
    for my $v ($p->{pane_id},$p->{agent},$cwd,$p->{workspace_id}) {
      exit 1 unless defined $v && !ref $v && $v ne "";
    }
    printf "%s\t%s\t%s\t%s",$p->{pane_id},$p->{agent},$cwd,$p->{workspace_id};' || true)"
  [[ -n "$pane_meta" ]] \
    || { echo "错误：复用 pane $ag_pane 身份无法解析，拒绝投递" >&2; return 1; }
  pane_id="$(printf '%s' "$pane_meta" | cut -f1)"
  pane_kind="$(printf '%s' "$pane_meta" | cut -f2)"
  pane_cwd="$(printf '%s' "$pane_meta" | cut -f3)"
  pane_ws="$(printf '%s' "$pane_meta" | cut -f4)"
  pane_dir="$(cd "$pane_cwd" 2>/dev/null && pwd -P)" \
    || { echo "错误：复用 pane cwd 无法确认：$pane_cwd" >&2; return 1; }
  [[ "$ag_kind" == "$WORKER" && "$pane_kind" == "$WORKER" \
     && "$ag_pane" == "$pane_id" && "$actual_dir" == "$expected_dir" \
     && "$pane_dir" == "$expected_dir" && "$ag_ws" == "$expected_ws" \
     && "$pane_ws" == "$expected_ws" ]] \
    || { echo "错误：同名工人 $NAME 的 worker/cwd/workspace 与本次目标不符，拒绝复用；旧工人若仍在主 workspace，请换 --name 重派" >&2; return 1; }
  last_dispatch="$(grep '^dispatch:' "$TASK_FILE" | tail -1 || true)"
  hist_dir="${last_dispatch##* dir=}"
  hist_dir="$(cd "$hist_dir" 2>/dev/null && pwd -P || true)"
  [[ -n "$last_dispatch" && "$last_dispatch" == *" worker=$WORKER agent=$NAME pane=$ag_pane dir="* \
     && "$hist_dir" == "$expected_dir" ]] \
    || { echo "错误：同名工人 $NAME 没有匹配本票的既有 dispatch 身份，拒绝认领" >&2; return 1; }
}
if [[ -z "$PANE" && "$LAUNCH_MODE" == "herdr" ]]; then
  ag_out="$(herdr agent get "$NAME" 2>&1)" && ag_rc=0 || ag_rc=$?
  if [[ "$ag_rc" -eq 0 ]]; then
    ag_meta="$(printf '%s' "$ag_out" | perl -MJSON::PP=decode_json -0777 -e '
      my $j = eval { decode_json(<STDIN>) };
      my $a = ($j && ref $j eq "HASH" && ref $j->{result} eq "HASH" && ref $j->{result}{agent} eq "HASH")
        ? $j->{result}{agent} : undef;
      exit 1 unless $a;
      for my $k ($a->{name}, $a->{agent_status}, $a->{pane_id}, $a->{agent},
                 $a->{workspace_id}) { exit 1 unless defined $k && !ref $k && $k ne ""; }
      my $cwd = $a->{foreground_cwd} // $a->{cwd};
      exit 1 unless defined $cwd && !ref $cwd && $cwd ne "";
      printf "%s\t%s\t%s\t%s\t%s\t%s", $a->{name}, $a->{agent_status},
        $a->{pane_id}, $a->{agent}, $cwd, $a->{workspace_id};' || true)"
    if [[ -n "$ag_meta" ]]; then
      ag_name="$(printf '%s' "$ag_meta" | cut -f1)"
      ag_stat="$(printf '%s' "$ag_meta" | cut -f2)"
      ag_pane="$(printf '%s' "$ag_meta" | cut -f3)"
      ag_kind="$(printf '%s' "$ag_meta" | cut -f4)"
      ag_cwd="$(printf '%s' "$ag_meta" | cut -f5)"
      ag_ws="$(printf '%s' "$ag_meta" | cut -f6)"
      [[ "$ag_name" == "$NAME" ]] \
        || { echo "错误：查询同名工人 ${NAME} 却得到 ${ag_name}，拒绝复用" >&2; exit 1; }
      if [[ "$ag_name" == "$NAME" ]]; then
        case "$ag_stat" in
          idle|done)
            [[ -n "$ag_pane" ]] || { echo "错误：同名工人 ${NAME} 状态 ${ag_stat} 但缺 pane_id，无法复用（fail-closed）：${ag_out}" >&2; exit 1; }
            validate_reuse || exit 1
            REUSE_PANE="$ag_pane"
            ;;
          working|blocked)
            echo "错误：同名工人 ${NAME} 还在 ${ag_stat}（pane ${ag_pane}）——它还在干，别打断；确要重派先确认它已停，或换 --name 新开。" >&2
            exit 1
            ;;
          *)
            echo "错误：同名工人 ${NAME} 状态为 ${ag_stat}（非 idle/done/working/blocked），无法安全处置（fail-closed）：${ag_out}" >&2
            exit 1
            ;;
        esac
      fi
    else
      echo "错误：查询同名工人 ${NAME} 的应答无法解析（fail-closed，不猜）：${ag_out}" >&2
      exit 1
    fi
  else
    printf '%s' "$ag_out" | grep -q 'agent_not_found' \
      || { echo "错误：查询同名工人 ${NAME} 失败（fail-closed，不猜）：${ag_out}" >&2; exit 1; }
  fi
fi

# —— 工人 tab 的 workspace（F：跨项目派活时工人窗口必须开在项目自己的 workspace）——
# 解析失败（声明了但 herdr 查不到 / workspace list 查询失败 / 响应不合契约）→ 在这里就拒绝，
# 早于锁、worktree、tab、账本写等一切副作用。--pane 复用路径与复用既有工人路径不建 tab，不解析。
TAB_WS=""
if [[ -z "$PANE" && -z "$REUSE_PANE" ]]; then
  quiet_fallback=""
  if [[ "$HERE" -eq 0 ]] && { [[ -z "$WORKTREE" ]] || qwb_is_project_worktree "$PROJECT_ROOT" "$WORKTREE"; }; then
    quiet_fallback=task-worktree
  fi
  TAB_WS="$(resolve_workspace "$PROJECT_ROOT" "$quiet_fallback")" || exit 1
fi

# Herdr 的 repo_root 指向主工作树根；子目录安装或 linked worktree 根无法安全登记任务 Space。
require_main_worktree_root() {
  local top git_dir git_common root_phys
  top="$(git -C "$PROJECT_ROOT" rev-parse --show-toplevel 2>/dev/null)" \
    || { echo "错误：无法核对项目 Git 工作树根，拒绝登记 worktree Space" >&2; return 1; }
  root_phys="$(cd "$PROJECT_ROOT" && pwd -P)"
  [[ "$(cd "$top" && pwd -P)" == "$root_phys" ]] \
    || { echo "错误：项目根不是 Git 工作树根（${top}），拒绝登记 worktree Space；请在仓库根安装 QWB" >&2; return 1; }
  git_dir="$(git -C "$PROJECT_ROOT" rev-parse --absolute-git-dir 2>/dev/null)" \
    || { echo "错误：无法核对当前 Git 目录，拒绝登记 worktree Space" >&2; return 1; }
  git_common="$(git -C "$PROJECT_ROOT" rev-parse --path-format=absolute --git-common-dir 2>/dev/null)" \
    || { echo "错误：无法核对 Git 公共目录，拒绝登记 worktree Space" >&2; return 1; }
  [[ "$(cd "$git_dir" && pwd -P)" == "$(cd "$git_common" && pwd -P)" ]] \
    || { echo "错误：项目根是 linked worktree，拒绝登记新 worktree Space；请在主工作树根安装 QWB" >&2; return 1; }
}
if [[ "$HERE" -eq 0 && -z "$WORKTREE" ]]; then
  require_main_worktree_root || exit 1
fi

# 主控锁：防两个主控同时动手。无锁→获取；他人持锁→拒绝派发；自己持有的锁可重复派发。
LOCK_BIN="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/qwb-lock.sh"
SELF="${HERDR_PANE_ID:-pid:$$}"
[[ -f "$LOCK_BIN" ]] || { echo "错误：找不到 ${LOCK_BIN}" >&2; exit 1; }
lock_out="$(bash "$LOCK_BIN" acquire --project "$PROJECT_ROOT" --owner "$SELF" 2>&1)" \
  || { printf '错误：主控锁获取失败，拒绝派发：\n%s\n' "$lock_out" >&2; exit 1; }

# —— 显式修订（--revise-scenarios）：锁内、任何派发副作用之前重新核对并更新指纹 ——
# 先在临时文件写「新指纹 + 修订记录」再原子 mv 回任务书：写与换任何一步失败即退出，不留半更新状态。
if [[ "$REVISE_GIVEN" -eq 1 ]]; then
  recheck_fp="$(sed -n 's/^scenarios-fp:[[:space:]]*//p' "$TASK_FILE" | head -1 | tr -d '[:space:]')"
  [[ "$recheck_fp" == "$DECLARED_FP" ]] \
    || { echo "错误：取得锁后票内旧指纹已变（${DECLARED_FP} → ${recheck_fp}），放弃本次修订，请重新核对后再派" >&2; exit 1; }
  recheck_scen_fp="$(printf '%s' "$(qwb_scenario_block "$TASK_FILE")" | shasum | cut -d' ' -f1)"
  [[ "$recheck_scen_fp" == "$SCEN_FP" ]] \
    || { echo "错误：取得锁后场景块已变，放弃本次修订，请重新核对后再派" >&2; exit 1; }
  REV_OLD="$DECLARED_FP"; REV_NEW="$SCEN_FP"
  REV_REC="working: scenarios-revised: old=${REV_OLD} new=${REV_NEW} reason=${REVISE}"
  rev_tmp="${TASK_FILE}.revise.$$"
  if ! perl -e '
      my ($new, $rec, $src, $dst) = @ARGV;
      open my $in, "<", $src or die "读任务书失败: $!\n";
      my @lines = <$in>; close $in;
      my $done = 0;
      for my $l (@lines) {
        if (!$done && $l =~ /^scenarios-fp:/) { $l = "scenarios-fp: $new\n"; $done = 1 }
      }
      die "任务书里没有 scenarios-fp 行\n" unless $done;
      my $tail = @lines && $lines[-1] !~ /\n\z/ ? "\n" : "";
      open my $out, ">", $dst or die "写修订临时文件失败: $!\n";
      print $out @lines, $tail, "$rec\n";
      close $out or die "写修订临时文件失败: $!\n";
    ' "$REV_NEW" "$REV_REC" "$TASK_FILE" "$rev_tmp"; then
    rm -f "$rev_tmp"
    echo "错误：修订写入失败（新指纹与修订记录均未落盘），不派发" >&2; exit 1
  fi
  if ! mv "$rev_tmp" "$TASK_FILE"; then
    rm -f "$rev_tmp"
    echo "错误：修订落盘失败（新指纹与修订记录均未生效），不派发" >&2; exit 1
  fi
  # 修订自检：新指纹与修订记录必须都已写入，缺一即败（不继续派发）
  { grep -q "^scenarios-fp: ${REV_NEW}" "$TASK_FILE" && grep -qF "$REV_REC" "$TASK_FILE"; } \
    || { echo "错误：修订自检失败（新指纹/修订记录未同时写入），不派发——请人工核对任务书" >&2; exit 1; }
  echo "已显式修订验收场景：old=${REV_OLD:0:8}… new=${REV_NEW:0:8}…（原因已留痕）"
fi

# worktree（M6：默认隔离）：--worktree 复用既有副本；--here 显式用项目根；
# 其余情况（含 --create-worktree 与默认不给参数）一律开 <根>/.worktrees/<id> 隔离副本
WT_CREATED=0
if [[ "$HERE" -eq 0 && -z "$WORKTREE" ]]; then
  WT_CREATED=0
  # 开之前先清点：有残留 worktree 打警告但不阻塞（使用者可能有意保留）
  WT_BIN="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/qwb-worktree.sh"
  if [[ -f "$WT_BIN" ]]; then
    residue="$(bash "$WT_BIN" list --project "$PROJECT_ROOT" 2>/dev/null | grep '残留' || true)"
    if [[ -n "$residue" ]]; then
      echo "警告：.worktrees 下有残留目录，建议先用 qwb-worktree.sh finish 收尾：" >&2
      printf '%s\n' "$residue" >&2
    fi
  fi
  WORKTREE="$PROJECT_ROOT/.worktrees/$TASK_ID"
  mkdir -p "$PROJECT_ROOT/.worktrees"
  # 物理目录和本项目 Git 登记均须吻合；坏残留拒绝复用。
  # 幂等（返工 / 修订后继续派发走的就是这条路）：目标路径已存在且是本任务的有效 worktree → 复用，不重建；
  # 存在但不是有效 worktree（脏残留 / 普通目录）→ 拒绝，不盲目复用也不删别人的东西。
  if [[ -e "$WORKTREE" ]]; then
    wt_kind_rc=0
    qwb_is_project_worktree "$PROJECT_ROOT" "$WORKTREE" || wt_kind_rc=$?
    [[ "$wt_kind_rc" -ne 2 ]] || { echo "错误：无法查询 Git worktree 登记，拒绝复用副本" >&2; exit 1; }
    if [[ "$wt_kind_rc" -eq 0 ]]; then
      echo "复用既有隔离副本（幂等，不重建）：${WORKTREE}"
    else
      {
        echo "错误：${WORKTREE} 已存在但不是 ${TASK_ID} 的有效 git worktree（脏残留/普通目录）——不盲目复用，请先清理："
        echo "  1) 只是目录残留：rm -rf ${WORKTREE}"
        echo "  2) 曾在 git 里登记过（或上面已删除）：git -C ${PROJECT_ROOT} worktree prune"
        echo "  3) 按 worktree 规范收尾（须先确认工人已停止写入）：bash ${WT_BIN} finish ${TASK_ID} --archive|--merged"
      } >&2
      exit 1
    fi
  elif git -C "$PROJECT_ROOT" show-ref --verify --quiet "refs/heads/$TASK_ID"; then
    git -C "$PROJECT_ROOT" worktree add "$WORKTREE" "$TASK_ID" \
      || { echo "错误：创建 worktree 失败（确要在项目根派发请显式用 --here）" >&2; exit 1; }
    WT_CREATED=1
  else
    git -C "$PROJECT_ROOT" worktree add -b "$TASK_ID" "$WORKTREE" \
      || { echo "错误：创建 worktree 失败（项目须为 git 仓库；确要在项目根派发请显式用 --here）" >&2; exit 1; }
    WT_CREATED=1
  fi
fi
DIR="$PROJECT_ROOT"
if [[ -n "$WORKTREE" ]]; then
  [[ -d "$WORKTREE" ]] || { echo "错误：worktree 不存在：$WORKTREE" >&2; exit 1; }
  DIR="$(cd "$WORKTREE" && pwd)"
fi

# —— QWB_WORKTREE_SETUP：新建隔离副本后、开 tab / 记账之前，在副本目录里 bash -c 执行一次 ——
# 只对本次新建的副本执行（复用既有副本 / --here / --worktree <既有路径> 均不跑）；
# stdout/stderr 透传；非 0 → 拒绝派发，副本保留供排查（任务书无 dispatch 行、无 tab 创建）。
if [[ "$WT_CREATED" -eq 1 && -n "${QWB_WORKTREE_SETUP:-}" ]]; then
  init_rc=0
  ( cd "$DIR" && bash -c "$QWB_WORKTREE_SETUP" ) || init_rc=$?
  if [[ "$init_rc" -ne 0 ]]; then
    echo "错误：worktree 初始化失败（退出码 ${init_rc}），副本保留在 ${DIR} 供排查，未派发" >&2
    exit 1
  fi
fi

# 任务副本必须作为独立 worktree 显示在 Herdr Spaces；登记早于信任预置和账本写入。
TASK_SPACE=""
wt_kind_rc=0
qwb_is_project_worktree "$PROJECT_ROOT" "$DIR" || wt_kind_rc=$?
[[ "$wt_kind_rc" -ne 2 ]] || { echo "错误：无法确认目标的 Git worktree 身份，拒绝派发" >&2; exit 1; }
if [[ "$wt_kind_rc" -eq 0 ]]; then
  require_main_worktree_root || exit 1
  TASK_SPACE="$(qwb_worktree_space "$PROJECT_ROOT" "$DIR")" || exit 1
  if [[ -z "$TASK_SPACE" ]]; then
    space_out="$(herdr worktree open --cwd "$PROJECT_ROOT" --path "$DIR" --label "$TASK_ID" --no-focus 2>&1)" \
      || { echo "错误：worktree 已保留但 Herdr Space 登记失败，未派发：$space_out" >&2; exit 1; }
    opened_id=""; opened_tab=""; already_open=""
    abort_opened_space() {
      echo "错误：$1；副本保留，未派发" >&2
      if [[ "$already_open" == 0 && -n "$opened_id" ]]; then
        if ! herdr workspace close "$opened_id" >/dev/null 2>&1; then
          echo "警告：新建 Space ${opened_id} 未能关闭；请执行 herdr workspace close ${opened_id} 后重试" >&2
        fi
      else
        echo "提示：请用 herdr workspace list 核对 ${DIR} 的 Space 并手工关闭本次新建的 Space" >&2
      fi
      exit 1
    }
    space_meta="$(printf '%s' "$space_out" | perl -MJSON::PP=decode_json -0777 -e '
      my $j=eval{decode_json(<STDIN>)}; my $r=$j->{result};
      exit 1 unless ref $r eq "HASH" && ref $r->{workspace} eq "HASH" && exists $r->{already_open};
      my $id=$r->{workspace}{workspace_id};
      exit 1 unless defined $id && !ref $id && $id ne "";
      my $tab=(ref $r->{root_pane} eq "HASH") ? ($r->{root_pane}{tab_id}//"") : "";
      printf "%s\t%s\t%s", $id,$tab,($r->{already_open} ? 1 : 0);' || true)"
    [[ -n "$space_meta" ]] \
      || abort_opened_space "herdr worktree open 响应无 Space 身份：$space_out"
    opened_id="$(printf '%s' "$space_meta" | cut -f1)"
    opened_tab="$(printf '%s' "$space_meta" | cut -f2)"
    already_open="$(printf '%s' "$space_meta" | cut -f3)"
    [[ -n "$opened_tab" ]] || abort_opened_space "herdr worktree open 响应无 root tab 身份：$space_out"
    TASK_SPACE="$(qwb_worktree_space "$PROJECT_ROOT" "$DIR")" \
      || abort_opened_space "herdr worktree open 后 Space 查询失败"
    [[ -n "$TASK_SPACE" && "$TASK_SPACE" == "$opened_id" ]] \
      || abort_opened_space "worktree Space 登记后路径/身份无法唯一核对"
    if [[ "$already_open" == 0 ]]; then
      space_line="worktree-space: id=${TASK_SPACE} root-tab=${opened_tab} path=${DIR}"
      printf '%s\n' "$space_line" >> "$TASK_FILE" || {
        abort_opened_space "worktree Space 所有权未能记入任务书"
      }
    fi
  fi
  recorded_space="$(sed -n 's/^worktree-space: id=\([^ ]*\).*/\1/p' "$TASK_FILE" | tail -1)"
  [[ -z "$recorded_space" || "$recorded_space" == "$TASK_SPACE" ]] \
    || { echo "错误：任务书登记的 Space ${recorded_space} 与当前 ${TASK_SPACE} 不符，拒绝派发" >&2; exit 1; }
  TAB_WS="$TASK_SPACE"
elif [[ "$HERE" -eq 0 && -n "$WORKTREE" ]]; then
  echo "提示：--worktree 路径不是本项目的 linked Git worktree，沿用既有目录派发，不登记 worktree Space" >&2
fi

# —— 派发前预置目录信任：claude/codex 对新目录弹信任框且不被权限参数跳过，起工人前把 $DIR
# 预先标成受信任。只对实际派的这一个工人做；文件缺失/非法 → stderr 一行警告并跳过，
# 信任框照弹、人来按，不阻塞派发。devin 的信任走 workers.sh 启动参数。
# 已受信任则完全不动文件（幂等：再派一次字节一致）。
case "$WORKER" in
  claude)
    cj="${HOME:-}/.claude.json"
    if [[ ! -f "$cj" ]]; then
      echo "警告：$cj 不存在，跳过 claude 信任预置（信任框将照常弹出）" >&2
    elif out="$(perl -MJSON::PP -e '
        my ($f, $dir) = @ARGV;
        open my $in, "<", $f or exit 2;
        local $/; my $txt = <$in>; close $in;
        my $j = eval { decode_json($txt) } or exit 1;
        ref($j) eq "HASH" or exit 1;
        my $p = $j->{projects} //= {};
        ref($p) eq "HASH" or exit 1;
        my $cur = $p->{$dir};
        exit 0 if ref($cur) eq "HASH" && $cur->{hasTrustDialogAccepted};
        $p->{$dir} = {} unless ref($cur) eq "HASH";
        $p->{$dir}{hasTrustDialogAccepted} = JSON::PP::true;
        my $tmp = "$f.qwb.$$";
        open my $out, ">", $tmp or exit 3;
        print {$out} encode_json($j), "\n" or exit 3;
        close $out or exit 3;
        rename $tmp, $f or exit 3;
      ' "$cj" "$DIR" 2>&1)"; then
      :
    else
      echo "警告：$cj 非法或不可写，跳过 claude 信任预置（信任框将照常弹出）：${out}" >&2
    fi
    ;;
  codex)
    ct="${HOME:-}/.codex/config.toml"
    if [[ ! -f "$ct" ]]; then
      echo "警告：$ct 不存在，跳过 codex 信任预置（信任框将照常弹出）" >&2
    elif ! grep -qF "[projects.\"$DIR\"]" "$ct"; then
      { [[ -s "$ct" && -n "$(tail -c1 "$ct")" ]] && printf '\n' >> "$ct"; } || true
      printf '[projects."%s"]\ntrust_level = "trusted"\n' "$DIR" >> "$ct" \
        || echo "警告：$ct 追加失败，跳过 codex 信任预置（信任框将照常弹出）" >&2
    fi
    ;;
esac

# —— 记账（F2）：state/场景基线在起任何工人前写；dispatch 在最终 pane 已知后、提示词发出前写 ——
# 只改 state: 那一行（原地逐行替换），其余行原样保留——禁止"先读整份快照、过一会儿再覆盖"。
lines_before="$(wc -l < "$TASK_FILE" | tr -d ' ')"
if grep -q '^state:' "$TASK_FILE"; then
  perl -i -pe 'if (!$done && /^state:/) { $_ = "state: running\n"; $done = 1 }' "$TASK_FILE"
else
  perl -i -pe 'if ($. == 1 && !$done) { $_ = "state: running\n\n$_"; $done = 1 }' "$TASK_FILE"
fi
# 首次派发或 --accept-new-scenarios 重建才写 scenarios-fp:；已有基线原样保留（不重写、不改值，R2-M1）
grep -q '^scenarios-fp:' "$TASK_FILE" \
  || perl -i -pe 'if (!$ins && /^state:/) { $_ .= "scenarios-fp: '"$SCEN_FP"'\n"; $ins = 1 }' "$TASK_FILE"
{ grep -q '^state: running' "$TASK_FILE" && grep -q "^scenarios-fp: ${SCEN_FP}" "$TASK_FILE"; } \
  || { echo "错误：state/scenarios-fp 未正确写入 ${TASK_FILE}" >&2; exit 1; }
[[ "$REBUILD_FP" -eq 1 ]] \
  && printf 'working: %s 主控以 --accept-new-scenarios 确认重建冻结基线（原 scenarios-fp 缺失）\n' \
       "$(date -u +%Y-%m-%dT%H:%M:%SZ)" >> "$TASK_FILE"

# 提示词：任务书绝对路径 + 主账本绝对路径 + 状态行规矩；--here 时写明这是显式选择的非隔离目录
DIR_NOTE=""
[[ "$HERE" -eq 1 ]] && DIR_NOTE="（你用 --here 显式指定的非隔离目录，代码改动将落在主项目根）"
PROMPT="你是本任务的执行者。唯一规格来源：${TASK_FILE}（先完整读它，再读它点名的文档）。工作目录=${DIR}${DIR_NOTE}，代码改动只留在本目录。每完成一个阶段往主账本追加状态行（working:/done:/blocked:/needs-decision:），主账本=${TASK_FILE}——只追加，不改别人的行，不改 state: 字段。done: 必须附跑了什么检查与原始结果。写完状态行再收工。"

# —— 常驻附页追加：任务书最后一节（账本状态行不算节）——
# 幂等查重按附页内容指纹（brief-include-fp: 行）取最后一份比对：同一内容重复派发不叠加，
# 内容改了能追加新版（不因「已有附页节」就永远跳过）。指纹行非状态行前缀，附页节在
# dispatch 行之前追加，场景块指纹语义不变（smoke 有对照用例钉住）；放在开 tab / 写 dispatch
# 之前，是为了让 dispatch 行始终是启动工人前追加的最后一行——启动失败时能安全回滚它。
if [[ -n "$BRIEF_INC_BODY" ]]; then
  BRIEF_INC_FP="$(printf '%s' "$BRIEF_INC_BODY" | shasum | cut -d' ' -f1)"
  last_inc_fp="$(sed -n 's/^brief-include-fp:[[:space:]]*//p' "$TASK_FILE" | tail -1)"
  if [[ "$last_inc_fp" != "$BRIEF_INC_FP" ]]; then
    [[ -s "$TASK_FILE" && -n "$(tail -c1 "$TASK_FILE")" ]] && printf '\n' >> "$TASK_FILE"
    {
      printf '## 常驻附页\n\n'
      printf '以下是本项目常驻规则附页（qwbuddy/brief-include.md）原样收录；本附页与其余各节冲突时，以其余各节为准。\n\n'
      printf '%s\n' "$BRIEF_INC_BODY"
      printf 'brief-include-fp: %s\n' "$BRIEF_INC_FP"
    } >> "$TASK_FILE" || { echo "错误：常驻附页写入失败：${TASK_FILE}" >&2; exit 1; }
  fi
  grep -q "^brief-include-fp: ${BRIEF_INC_FP}" "$TASK_FILE" \
    || { echo "错误：常驻附页自检失败（指纹未落盘），不派发——请人工核对任务书" >&2; exit 1; }
fi

# 窗口：复用既有工人 pane / 复用 --pane / 新开 tab。新开时 tab 落 TAB_WS（空 = 不带 --workspace，即调用者 workspace）。
if [[ -n "$REUSE_PANE" ]]; then
  PANE="$REUSE_PANE"
elif [[ -z "$PANE" ]]; then
  if [[ -n "$TAB_WS" ]]; then
    out="$(herdr tab create --workspace "$TAB_WS" --cwd "$DIR" --label "$TASK_ID" --no-focus)"
  else
    out="$(herdr tab create --cwd "$DIR" --label "$TASK_ID" --no-focus)"
  fi
  # pane_id 必须是 JSON 字符串（encode_json 回带引号）：HASH/ARRAY/数字/布尔/null 一律拒收（R2-M2）
  PANE="$(printf '%s' "$out" | perl -MJSON::PP=decode_json,encode_json -0777 -e '
    my $j = eval { decode_json(<STDIN>) };
    my $v = ($j && ref $j eq "HASH" && ref $j->{result} eq "HASH"
      && ref $j->{result}{root_pane} eq "HASH")
      ? $j->{result}{root_pane}{pane_id} : undef;
    print((defined $v && !ref $v && $v ne "" && encode_json($v) =~ /^"/) ? $v : "");
  ')"
  [[ -n "$PANE" ]] || { echo "错误：herdr tab create 的 .result.root_pane.pane_id 缺失、为空或类型不是字符串：$out" >&2; exit 1; }
  # tab id 供启动失败时回滚关 tab（缺失只警告不拒绝——关不掉大不了留个空 tab）
  TAB_ID="$(printf '%s' "$out" | perl -MJSON::PP=decode_json -0777 -e '
    my $j = eval { decode_json(<STDIN>) };
    my $v = ($j && ref $j eq "HASH" && ref $j->{result} eq "HASH"
      && ref $j->{result}{root_pane} eq "HASH")
      ? $j->{result}{root_pane}{tab_id} : undef;
    print((defined $v && !ref $v && $v ne "") ? $v : "");
  ')"
fi

# 最终 pane 已知后追加完整 dispatch，随后才启动工人并发送提示词。
# 记下本次 append 的真实偏移（同一 fd 的写后位置），供失败时只改本行前缀。
DISPATCH_LINE="$(printf 'dispatch: %s worker=%s agent=%s pane=%s dir=%s' \
  "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$WORKER" "$NAME" "$PANE" "$DIR")"
DISPATCH_OFFSET="$(perl -MFcntl=O_WRONLY,O_APPEND -e '
  my ($f, $line) = @ARGV;
  open my $r, "<", $f or die "读任务书失败: $!\n";
  binmode $r;
  my $prefix = "";
  if (-s $r) {
    seek($r, -1, 2) or die "读取尾字节失败: $!\n";
    read($r, my $last, 1) == 1 or die "读取尾字节失败: $!\n";
    $prefix = "\n" if $last ne "\n";
  }
  close $r;
  sysopen my $w, $f, O_WRONLY|O_APPEND or die "打开任务书失败: $!\n";
  binmode $w;
  my $record = $prefix . $line . "\n";
  my $n = syswrite($w, $record);
  die "dispatch 追加失败: $!\n" unless defined $n && $n == length $record;
  my $end = sysseek($w, 0, 1);
  die "获取 dispatch 偏移失败: $!\n" unless defined $end;
  print $end - length($line) - 1;
  close $w or die "关闭任务书失败: $!\n";
' "$TASK_FILE" "$DISPATCH_LINE")" \
  || { echo "错误：dispatch 写入失败：${TASK_FILE}" >&2; exit 1; }
# 自检：任务书原有行不得丢失（行数只增不减）
lines_after="$(wc -l < "$TASK_FILE" | tr -d ' ')"
(( lines_after >= lines_before )) \
  || { echo "错误：记账后任务书行数减少（${lines_before}→${lines_after}），疑似覆盖丢失，中止派发" >&2; exit 1; }

# 只把本次 dispatch: 的 9 字节前缀原位改成 not-sent:（同长度）。
# 不截断、不 rename 整份账本；其他工人即使在其后并发追加，也不会被覆盖。
undo_dispatch_line() {
  perl -e '
    my ($f, $line, $off) = @ARGV;
    open my $fh, "+<", $f or die "打开任务书失败: $!\n";
    binmode $fh;
    seek($fh, $off, 0) or die "定位本次 dispatch 失败: $!\n";
    my $actual = <$fh>;
    die "本次 dispatch 已变动，不敢改写\n" unless defined $actual && $actual eq "$line\n";
    seek($fh, $off, 0) or die "重新定位失败: $!\n";
    my $n = syswrite($fh, "not-sent:");
    die "原位标记失败: $!\n" unless defined $n && $n == 9;
    close $fh or die "关闭任务书失败: $!\n";
  ' "$TASK_FILE" "$DISPATCH_LINE" "$DISPATCH_OFFSET"
}
delivery_failed() {
  local step="$1" rc="$2" detail="$3"
  # 只关闭本次创建的 tab；已有 --pane 或复用工人的 pane 永不关闭。
  if [[ -n "$TAB_ID" ]]; then
    herdr tab close "$TAB_ID" >/dev/null 2>&1 \
      || echo "警告：本次 tab ${TAB_ID} 关闭失败，请手工核对" >&2
  fi
  undo_dispatch_line \
    || echo "警告：本次 dispatch 原位撤销失败，需人工核对 $TASK_FILE" >&2
  printf 'blocked: %s 派发投递失败 step=%s rc=%s pane=%s\n' \
    "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$step" "$rc" "$PANE" >> "$TASK_FILE"
  printf '错误：%s 失败（退出码 %s）：\n%s\n' "$step" "$rc" "$detail" >&2
  exit 1
}

now_ms() {
  if [[ -n "${QWB_NOW_MS_CMD:-}" ]]; then "$QWB_NOW_MS_CMD"; return; fi
  perl -MTime::HiRes=time -e 'printf "%d", time()*1000'
}
sleep_ms() {
  local ms="$1"
  (( ms > 0 )) || ms=1
  if [[ -n "${QWB_SLEEP_CMD:-}" ]]; then "$QWB_SLEEP_CMD" "$ms"; return; fi
  sleep "$(printf '%d.%03d' "$(( ms / 1000 ))" "$(( ms % 1000 ))")"
}

case "$LAUNCH_MODE" in
  herdr)
    if [[ -n "$REUSE_PANE" ]]; then
      echo "复用既有工人 ${NAME}（pane ${PANE}）"
      prompt_rc=0
      prompt_out="$(herdr agent prompt "$NAME" "这是返工/续派，读主账本末尾主控最新一条 working: 行。${PROMPT}" 2>&1)" || prompt_rc=$?
      [[ "$prompt_rc" -eq 0 ]] || delivery_failed "herdr agent prompt" "$prompt_rc" "$prompt_out"
      printf '%s\n' "$prompt_out"
    else
      start_argv=(agent start "$NAME" --kind "$WORKER" --pane "$PANE" --timeout "$START_MS")
      if [[ ${#WORKER_ARGV[@]} -gt 0 ]]; then
        start_argv+=(--)
        start_argv+=("${WORKER_ARGV[@]}")
      fi
      start_rc=0
      start_out="$(herdr "${start_argv[@]}" 2>&1)" || start_rc=$?
      [[ "$start_rc" -eq 0 ]] || delivery_failed "herdr agent start" "$start_rc" "$start_out"
      printf '%s\n' "$start_out"
      prompt_rc=0
      prompt_out="$(herdr agent prompt "$NAME" "$PROMPT" 2>&1)" || prompt_rc=$?
      [[ "$prompt_rc" -eq 0 ]] || delivery_failed "herdr agent prompt" "$prompt_rc" "$prompt_out"
      printf '%s\n' "$prompt_out"
    fi
    ;;
  pane-run)
    run_rc=0
    run_out="$(herdr pane run "$PANE" "$PANE_COMMAND" 2>&1)" || run_rc=$?
    [[ "$run_rc" -eq 0 ]] || delivery_failed "herdr pane run（启动）" "$run_rc" "$run_out"
    detect_started="$(now_ms)"
    while ! herdr agent get "$PANE" >/dev/null 2>&1; do
      detect_elapsed=$(( $(now_ms) - detect_started ))
      if (( detect_elapsed >= START_MS )); then
        delivery_failed "pane-run 工人检测" 1 "超时（${START_MS}ms），pane=${PANE}；查 herdr pane read / process-info / agent get"
      fi
      detect_left=$(( START_MS - detect_elapsed ))
      (( detect_left > 100 )) && detect_left=100
      sleep_ms "$detect_left"
    done
    rename_rc=0
    rename_out="$(herdr agent rename "$PANE" "$NAME" 2>&1)" || rename_rc=$?
    [[ "$rename_rc" -eq 0 ]] || delivery_failed "herdr agent rename" "$rename_rc" "$rename_out"
    prompt_rc=0
    prompt_out="$(herdr pane run "$PANE" "$PROMPT" 2>&1)" || prompt_rc=$?
    [[ "$prompt_rc" -eq 0 ]] || delivery_failed "herdr pane run（提示词）" "$prompt_rc" "$prompt_out"
    printf '%s\n' "$prompt_out"
    if ! herdr agent wait "$PANE" --until working --until "done" --until blocked --timeout 300 >/dev/null 2>&1; then
      enter_rc=0
      enter_out="$(herdr pane send-keys "$PANE" enter 2>&1)" || enter_rc=$?
      [[ "$enter_rc" -eq 0 ]] || delivery_failed "herdr pane send-keys" "$enter_rc" "$enter_out"
    fi
    ;;
esac

echo "已派发：${TASK_ID} → ${WORKER}（agent=${NAME} pane=${PANE} dir=${DIR}）"
