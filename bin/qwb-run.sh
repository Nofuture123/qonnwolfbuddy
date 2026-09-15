#!/usr/bin/env bash
# qwb-run.sh —— 派发 + 记账：在指定 worktree/窗口里派活，把窗口、派发时间、state: running 写进任务书
set -euo pipefail

usage() {
  cat <<'EOF'
用法: qwb-run.sh --task <任务id或任务书路径> --worker <工人名> [选项]

必选:
  --task <id|路径>      任务书 id（如 qwbuddy-mvp）或文件路径
  --worker <名>         工人名（须在 config.sh 的 QWB_WORKERS 里整词精确匹配，如 codex/pi/claude）

选项:
  --project <根>        项目根（默认：当前目录）
  --worktree <路径>     在既有 worktree 目录里派活（新窗口的 cwd）
  --create-worktree     先开 <根>/.worktrees/<任务id>（git worktree add；与默认行为同义）
  --here                显式声明就在项目根派发（非隔离目录，须使用者有意选择）
  --pane <pane_id>      复用既有 pane（须为交互 shell），否则新开 herdr tab
  --name <agent名>      工人 agent 名（默认：qwb-<任务id>）
  -h, --help            显示本帮助

默认：不给 --worktree/--create-worktree/--here 时自动开隔离副本 .worktrees/<任务id>。
派发前有验收场景门：任务书必须含「验收场景」块（Given/When/Then 或 ≥2 个 user_ 场景标题）
且至少一条失败路径场景，否则拒绝派发；通过则把场景块指纹写成 scenarios-fp: 供 lint 冻结比对。
EOF
}

PROJECT_ROOT="$(pwd)"; TASK=""; WORKER=""; WORKTREE=""; CREATE_WT=0; HERE=0; PANE=""; NAME=""
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

# 定位任务书：路径直接用；id 在 tasks/ 里唯一匹配
if [[ -f "$TASK" ]]; then
  TASK_FILE="$(cd "$(dirname "$TASK")" && pwd)/$(basename "$TASK")"
else
  hits=()
  for f in "$LEDGER"/*"$TASK"*.md; do [[ -e "$f" ]] && hits+=("$f"); done
  [[ ${#hits[@]} -eq 1 ]] || { echo "错误：任务 '${TASK}' 在 ${LEDGER} 匹配到 ${#hits[@]} 份（要唯一）" >&2; exit 1; }
  TASK_FILE="${hits[0]}"
fi
# 任务 id = 文件名去日期前缀与扩展名
TASK_ID="$(basename "$TASK_FILE" .md | sed 's/^[0-9][0-9-]*-//')"
[[ -n "$TASK_ID" ]] || TASK_ID="$(basename "$TASK_FILE" .md)"

# 工人须在 config.sh 的 QWB_WORKERS 里（herdr kind 与工人同名）。
# 配置唯一来源是 bash 文件：直接 source，不再解析 JSON。
[[ -f "$CONF" ]] || { echo "错误：找不到 ${CONF}（先跑 qwb-init.sh）" >&2; exit 1; }
QWB_WORKERS=""; QWB_AGENT_START_MS=""
# shellcheck source=/dev/null
. "$CONF"
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

# —— M1 派发门：任务书必须有「验收场景」块（先场景后代码），且至少一条失败路径场景 ——
# 验收场景块 = 首个含「验收场景」的标题行起，到下一个一/二级标题、或首条账本状态/运行时行为止
# （working:/done:/dispatch:/wake: 等行永远追加在文件尾，不得计入场景指纹）
scenario_block() {
  awk '
    inblk==0 && /^#{1,6}[^#]*验收场景/ { inblk=1; print; next }
    inblk==1 && (/^#{1,2}[^#]/ || /^(working|done|blocked|needs-decision|dispatch|wake|worktree|scenarios-fp):/) { inblk=0 }
    inblk==1 { print }
  ' "$1"
}
scen_refuse() { echo "错误：$1——请按 qwbuddy/TASK.md 补验收场景（至少一条失败路径）" >&2; exit 1; }
SCEN_BLK="$(scenario_block "$TASK_FILE")"
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

# 主控锁：防两个主控同时动手。无锁→获取；他人持锁→拒绝派发；自己持有的锁可重复派发。
LOCK_BIN="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/qwb-lock.sh"
LOCK_DIR="$PROJECT_ROOT/qwbuddy/.controller.lock"
SELF="${HERDR_PANE_ID:-pid:$$}"
[[ -f "$LOCK_BIN" ]] || { echo "错误：找不到 ${LOCK_BIN}" >&2; exit 1; }
if ! bash "$LOCK_BIN" acquire --project "$PROJECT_ROOT" --owner "$SELF" >/dev/null 2>&1; then
  holder_id="$(sed -n 's/^[^ ]* //p' "$LOCK_DIR/owner" 2>/dev/null | head -1)"
  if [[ "$holder_id" != "$SELF" ]]; then
    echo "错误：主控锁被占用，锁主：$(cat "$LOCK_DIR/owner" 2>/dev/null || echo '（锁目录存在但无 owner 文件）')" >&2
    echo "确认是残留锁后手动释放：bash ${LOCK_BIN} release --project ${PROJECT_ROOT}" >&2
    exit 1
  fi
fi

# worktree（M6：默认隔离）：--worktree 复用既有副本；--here 显式用项目根；
# 其余情况（含 --create-worktree 与默认不给参数）一律开 <根>/.worktrees/<id> 隔离副本
if [[ "$HERE" -eq 0 && -z "$WORKTREE" ]]; then
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
  if git -C "$PROJECT_ROOT" show-ref --verify --quiet "refs/heads/$TASK_ID"; then
    git -C "$PROJECT_ROOT" worktree add "$WORKTREE" "$TASK_ID" \
      || { echo "错误：创建 worktree 失败（确要在项目根派发请显式用 --here）" >&2; exit 1; }
  else
    git -C "$PROJECT_ROOT" worktree add -b "$TASK_ID" "$WORKTREE" \
      || { echo "错误：创建 worktree 失败（项目须为 git 仓库；确要在项目根派发请显式用 --here）" >&2; exit 1; }
  fi
fi
DIR="$PROJECT_ROOT"
if [[ -n "$WORKTREE" ]]; then
  [[ -d "$WORKTREE" ]] || { echo "错误：worktree 不存在：$WORKTREE" >&2; exit 1; }
  DIR="$(cd "$WORKTREE" && pwd)"
fi

# 窗口：复用 --pane 或新开 tab（tab create 返回 JSON，pane id 按契约取 .result.root_pane.pane_id）
if [[ -z "$PANE" ]]; then
  out="$(herdr tab create --cwd "$DIR" --label "$TASK_ID" --no-focus)"
  PANE="$(printf '%s' "$out" | perl -MJSON::PP=decode_json -0777 -e '
    my $j = eval { decode_json(<STDIN>) };
    print(($j && ref $j eq "HASH" && ref $j->{result} eq "HASH" && ref $j->{result}{root_pane} eq "HASH")
      ? ($j->{result}{root_pane}{pane_id} // "") : "");
  ')"
  [[ -n "$PANE" ]] || { echo "错误：herdr tab create 的 .result.root_pane.pane_id 缺失或为空：$out" >&2; exit 1; }
fi

NAME="${NAME:-qwb-$TASK_ID}"
NAME="$(printf '%s' "$NAME" | cut -c1-32 | tr '[:upper:]' '[:lower:]' | tr -cd 'a-z0-9_-')"

# —— 记账（F2）：工人一启动就被允许往任务书追加，所以所有账本写入必须在 agent start 之前完成 ——
# 只改 state: 那一行（原地逐行替换），其余行原样保留——禁止"先读整份快照、过一会儿再覆盖"。
lines_before="$(wc -l < "$TASK_FILE" | tr -d ' ')"
if grep -q '^state:' "$TASK_FILE"; then
  perl -i -pe 'if (!$done && /^state:/) { $_ = "state: running\n"; $done = 1 }
               if (/^scenarios-fp:/) { $_ = "scenarios-fp: '"$SCEN_FP"'\n" }' "$TASK_FILE"
else
  perl -i -pe 'if ($. == 1 && !$done) { $_ = "state: running\nscenarios-fp: '"$SCEN_FP"'\n\n$_"; $done = 1 }' "$TASK_FILE"
fi
# 有 state: 行但还没有 scenarios-fp: → 插到 state: 行后（写在 state 附近）
grep -q '^scenarios-fp:' "$TASK_FILE" \
  || perl -i -pe 'if (!$ins && /^state:/) { $_ .= "scenarios-fp: '"$SCEN_FP"'\n"; $ins = 1 }' "$TASK_FILE"
{ grep -q '^state: running' "$TASK_FILE" && grep -q "^scenarios-fp: ${SCEN_FP}" "$TASK_FILE"; } \
  || { echo "错误：state/scenarios-fp 未正确写入 ${TASK_FILE}" >&2; exit 1; }
# 追加前保证文件以换行结尾，新行不粘连到原末行
[[ -s "$TASK_FILE" && -n "$(tail -c1 "$TASK_FILE")" ]] && printf '\n' >> "$TASK_FILE"
printf 'dispatch: %s worker=%s agent=%s pane=%s dir=%s\n' \
  "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$WORKER" "$NAME" "$PANE" "$DIR" >> "$TASK_FILE"
# 自检：任务书原有行不得丢失（行数只增不减）
lines_after="$(wc -l < "$TASK_FILE" | tr -d ' ')"
(( lines_after >= lines_before )) \
  || { echo "错误：记账后任务书行数减少（${lines_before}→${lines_after}），疑似覆盖丢失，中止派发" >&2; exit 1; }

herdr agent start "$NAME" --kind "$WORKER" --pane "$PANE" --timeout "$START_MS"

# 提示词：任务书绝对路径 + 主账本绝对路径 + 状态行规矩；--here 时写明这是显式选择的非隔离目录
DIR_NOTE=""
[[ "$HERE" -eq 1 ]] && DIR_NOTE="（你用 --here 显式指定的非隔离目录，代码改动将落在主项目根）"
herdr agent prompt "$NAME" "你是本任务的执行者。唯一规格来源：${TASK_FILE}（先完整读它，再读它点名的文档）。工作目录=${DIR}${DIR_NOTE}，代码改动只留在本目录。每完成一个阶段往主账本追加状态行（working:/done:/blocked:/needs-decision:），主账本=${TASK_FILE}——只追加，不改别人的行，不改 state: 字段。done: 必须附跑了什么检查与原始结果。写完状态行再收工。"

echo "已派发：${TASK_ID} → ${WORKER}（agent=${NAME} pane=${PANE} dir=${DIR}）"
