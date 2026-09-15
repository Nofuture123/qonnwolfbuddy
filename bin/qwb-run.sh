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
                        隔离副本的创建是幂等的：已是本任务的有效 worktree 则复用，不重建
  --here                显式声明就在项目根派发（非隔离目录，须使用者有意选择）
  --pane <pane_id>      复用既有 pane（须为交互 shell），否则新开 herdr tab
  --name <agent名>      工人 agent 名（默认：qwb-<任务id>）
  --accept-new-scenarios  主控显式确认：曾派发但丢 scenarios-fp 基线的任务书，允许重建冻结基线（留一行说明）
  --revise-scenarios=<原因>  主控显式修订验收场景：票内已有基线且场景块被有意改动时，
                         更新 scenarios-fp 并追加 working: scenarios-revised: 留痕记录（原因非空，须写明条款依据）
  -h, --help            显示本帮助

默认：不给 --worktree/--create-worktree/--here 时自动开隔离副本 .worktrees/<任务id>。
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

# —— 疑点门：票上有未决「规格疑点」→ 拒绝派发，先处置后派 ——
# 相关事件 = 两类精确前缀（blocked:…spec-defect: / working:…spec-resolved:）按出现顺序取最后一个：
# 是 spec-defect: → 未决。普通 working:/done:/dispatch: 行不参与判定、不能解除疑点；
# spec-resolved: 只认主控写的处置结论，覆盖其之前全部未决疑点，之后新提的疑点重新拦截。
# 本检查在任何派发副作用（worktree/窗口/tab/state:/dispatch:）之前完成。
last_spec_ev="$(grep -E '^blocked:[[:space:]]*spec-defect:|^working:[[:space:]]*spec-resolved:' "$TASK_FILE" | tail -1 || true)"
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

# —— 显式修订（--revise-scenarios）：锁内、任何派发副作用之前重新核对并更新指纹 ——
# 先在临时文件写「新指纹 + 修订记录」再原子 mv 回任务书：写与换任何一步失败即退出，不留半更新状态。
if [[ "$REVISE_GIVEN" -eq 1 ]]; then
  recheck_fp="$(sed -n 's/^scenarios-fp:[[:space:]]*//p' "$TASK_FILE" | head -1 | tr -d '[:space:]')"
  [[ "$recheck_fp" == "$DECLARED_FP" ]] \
    || { echo "错误：取得锁后票内旧指纹已变（${DECLARED_FP} → ${recheck_fp}），放弃本次修订，请重新核对后再派" >&2; exit 1; }
  recheck_scen_fp="$(printf '%s' "$(scenario_block "$TASK_FILE")" | shasum | cut -d' ' -f1)"
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
  # 有效 worktree 判定（两个条件都要满足）：① 该目录真的是一个 git 工作区且根就在这个路径——
  # prunable 残留（登记还在、目录被删/被换成普通目录）会被 git 回退解析到外层仓 → 不等，拒；
  # ② 本项目 worktree 列表能查到该路径（按物理路径比对，避开 /tmp→/private/tmp 这类符号链接差异）。
  wt_is_valid() {
    local want want_real top p p_real
    want="$1"
    want_real="$(cd "$want" 2>/dev/null && pwd -P)" || return 1
    top="$(git -C "$want" rev-parse --show-toplevel 2>/dev/null)" || return 1
    [[ -n "$top" && "$(cd "$top" 2>/dev/null && pwd -P)" == "$want_real" ]] || return 1
    while IFS= read -r p; do
      [[ -n "$p" ]] || continue
      p_real="$(cd "$p" 2>/dev/null && pwd -P)" || continue
      [[ "$p_real" == "$want_real" ]] && return 0
    done < <(git -C "$PROJECT_ROOT" worktree list --porcelain 2>/dev/null | sed -n 's/^worktree //p')
    return 1
  }
  # 幂等（返工 / 修订后继续派发走的就是这条路）：目标路径已存在且是本任务的有效 worktree → 复用，不重建；
  # 存在但不是有效 worktree（脏残留 / 普通目录）→ 拒绝，不盲目复用也不删别人的东西。
  if [[ -e "$WORKTREE" ]]; then
    if wt_is_valid "$WORKTREE"; then
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
  # pane_id 必须是 JSON 字符串（encode_json 回带引号）：HASH/ARRAY/数字/布尔/null 一律拒收（R2-M2）
  PANE="$(printf '%s' "$out" | perl -MJSON::PP=decode_json,encode_json -0777 -e '
    my $j = eval { decode_json(<STDIN>) };
    my $v = ($j && ref $j eq "HASH" && ref $j->{result} eq "HASH"
      && ref $j->{result}{root_pane} eq "HASH")
      ? $j->{result}{root_pane}{pane_id} : undef;
    print((defined $v && !ref $v && $v ne "" && encode_json($v) =~ /^"/) ? $v : "");
  ')"
  [[ -n "$PANE" ]] || { echo "错误：herdr tab create 的 .result.root_pane.pane_id 缺失、为空或类型不是字符串：$out" >&2; exit 1; }
fi

NAME="${NAME:-qwb-$TASK_ID}"
NAME="$(printf '%s' "$NAME" | cut -c1-32 | tr '[:upper:]' '[:lower:]' | tr -cd 'a-z0-9_-')"

# —— 记账（F2）：工人一启动就被允许往任务书追加，所以所有账本写入必须在 agent start 之前完成 ——
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
# 追加前保证文件以换行结尾，新行不粘连到原末行
[[ -s "$TASK_FILE" && -n "$(tail -c1 "$TASK_FILE")" ]] && printf '\n' >> "$TASK_FILE"
printf 'dispatch: %s worker=%s agent=%s pane=%s dir=%s\n' \
  "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$WORKER" "$NAME" "$PANE" "$DIR" >> "$TASK_FILE"
[[ "$REBUILD_FP" -eq 1 ]] \
  && printf 'working: %s 主控以 --accept-new-scenarios 确认重建冻结基线（原 scenarios-fp 缺失）\n' \
       "$(date -u +%Y-%m-%dT%H:%M:%SZ)" >> "$TASK_FILE"
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
