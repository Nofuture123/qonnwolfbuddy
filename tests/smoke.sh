#!/usr/bin/env bash
# tests/smoke.sh —— QW buddy 冒烟测试（不需要 herdr，可在干净环境跑）
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
FAILS=0

ok()   { echo "PASS  $1"; }
bad()  { echo "FAIL  $1"; FAILS=$((FAILS+1)); }
chk()  { if "$@" >/dev/null 2>&1; then ok "$*"; else bad "$*"; fi; }
assert_file() { [[ -f "$1" ]] && ok "存在 $1" || bad "缺文件 $1"; }
assert_dir()  { [[ -d "$1" ]] && ok "存在 $1" || bad "缺目录 $1"; }

echo "== 1. bash -n 语法检查 =="
for s in "$ROOT"/bin/qwb-*.sh; do chk bash -n "$s"; done

echo "== 2. shellcheck =="
if command -v shellcheck >/dev/null 2>&1; then
  for s in "$ROOT"/bin/qwb-*.sh; do chk shellcheck "$s"; done
else
  echo "SKIP  本机无 shellcheck，跳过"
fi

echo "== 3. qwb-init.sh 装进临时假项目 =="
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
# 信任预置会读写 $HOME/.claude.json 与 $HOME/.codex/config.toml：全程用假 HOME，不碰真家目录。
# seed 一份合法 codex config，让 48 节这类断言 stderr 为空的用例不被「文件不存在」预置警告污染
mkdir -p "$TMP/home/.codex"; printf '[projects."/smoke/seed"]\ntrust_level = "trusted"\n' > "$TMP/home/.codex/config.toml"
export HOME="$TMP/home"
bash "$ROOT/bin/qwb-init.sh" "$TMP" >/dev/null || bad "qwb-init.sh 运行失败"

assert_file "$TMP/qwbuddy/QWBUDDY.md"
for r in 主控 审核者 执行者 咨询师; do assert_file "$TMP/qwbuddy/roles/$r.md"; done
assert_file "$TMP/qwbuddy/config.sh"
for s in run wake status lock worktree test lint lib; do assert_file "$TMP/qwbuddy/bin/qwb-$s.sh"; done
# M5：qwb-init.sh 是母本仓专用安装器，不得复制进目标项目
[[ -f "$TMP/qwbuddy/bin/qwb-init.sh" ]] \
  && bad "qwb-init.sh 被复制进目标项目（应母本仓专用）" || ok "qwb-init.sh 不复制进目标项目"
assert_dir  "$TMP/tasks"
assert_dir  "$TMP/tasks/lessons"
grep -qF 'qwbuddy/QWBUDDY.md' "$TMP/AGENTS.md" && ok "AGENTS.md 有钩子" || bad "AGENTS.md 无钩子"
grep -qF 'qwbuddy/QWBUDDY.md' "$TMP/CLAUDE.md" && ok "CLAUDE.md 有钩子" || bad "CLAUDE.md 无钩子"

# 幂等：再跑一次，钩子不得重复
bash "$ROOT/bin/qwb-init.sh" "$TMP" >/dev/null || bad "qwb-init.sh 二次运行失败"
for f in AGENTS.md CLAUDE.md; do
  n="$(grep -cF 'qwbuddy/QWBUDDY.md' "$TMP/$f" || true)"
  [[ "$n" == "1" ]] && ok "$f 钩子未重复" || bad "$f 钩子重复（$n 处）"
done

echo "== 4. qwb-status.sh 对空账本 =="
( cd "$TMP" && bash qwbuddy/bin/qwb-status.sh ) >/dev/null && ok "status 空账本退出 0" || bad "status 空账本非 0"

echo "== 5. config.sh 可被 source 且值正确（G3）=="
if ( . "$TMP/qwbuddy/config.sh"; [[ "$QWB_WORKERS" == "codex pi claude devin omp" && -z "${QWB_WORKER_LAUNCH:-}" && -z "$QWB_WORKSPACE" && "$QWB_AGENT_START_MS" == "30000" && "$QWB_WAKE_INTERVAL_MS" == "120000" ]] ); then
  ok "config.sh source 后启动方式默认空、QWB_WORKSPACE 默认未声明且既有配置值正确"
else
  bad "config.sh source 失败或配置值不对"
fi

echo "== 6. qwb-wake.sh --dry-run 未结项判定 =="
FAKE="$TMP/tasks/2099-01-01-fake.md"
printf '# 假任务\nstate: running\n' > "$FAKE"
out="$( cd "$TMP" && bash qwbuddy/bin/qwb-wake.sh --dry-run --once )"
printf '%s' "$out" | grep -q '2099-01-01-fake' && ok "state=running 列为未结项" || bad "state=running 未列为未结项"
grep -q '^wake:' "$FAKE" && bad "dry-run 写了 wake 行" || ok "dry-run 无副作用（无 wake 行）"

printf '# 假任务\nstate: verified\n' > "$FAKE"
out="$( cd "$TMP" && bash qwbuddy/bin/qwb-wake.sh --dry-run --once )"
printf '%s' "$out" | grep -q '2099-01-01-fake' && bad "state=verified 仍列为未结项" || ok "state=verified 不再列为未结项"

echo "== 7. stub herdr：qwb-wake.sh --once 有未结项退出 0（回归 Bug 2）=="
STUB="$TMP/stubbin"; STUBLOG="$TMP/herdr-calls.log"
FIXDIR="$ROOT/tests/fixtures/herdr"
mkdir -p "$STUB"
# 契约 stub：响应全部来自 tests/fixtures/herdr/ 真录样本（剔 # 注释行），不再硬编码 JSON。
# 可选行为：HERDR_FAIL=run|wait|list|prompt 让对应调用按真实错误形状失败；
#          HERDR_WAIT_BUMP_MS + QWB_FAKE_NOW_FILE 让 agent wait 把假时钟往前推（模拟等待耗时）；
#          HERDR_DYN_DIR 下放逐 pane 应答片场（pane-list.json / get-<san>.json|.err / proc-<san>.json|.err /
#          read-<san>.txt / tab-create.json），san=pane id 剔除非字母数字；HERDR_READ_TRUST=1 让 pane read 回真录信任框。
cat > "$STUB/herdr" <<EOF
#!/usr/bin/env bash
echo "herdr \$*" >> "$STUBLOG"
fix() { sed '/^#/d' "\${HERDR_FIXDIR:-$FIXDIR}/\$1"; }
# 动态片场：pane 级应答按 pane id 逐测试布置（HERDR_DYN_DIR，默认 \$TMP/herdr-dyn）
DYNH="\${HERDR_DYN_DIR:-$TMP/herdr-dyn}"; mkdir -p "\$DYNH" 2>/dev/null
san() { printf '%s' "\$1" | tr -cd 'a-zA-Z0-9'; }
failjson() { printf '{"error":{"code":"%s","message":"%s"},"id":"cli:test"}\n' "\$1" "\$2" >&2; exit 1; }
case "\${1:-} \${2:-}" in
  "pane run")   if [[ "\${HERDR_FAIL:-}" == *run* ]]; then fix pane-run-error.json >&2; exit 1; fi
                # 模拟真实效果：往 shell pane 跑 qwb-wake.sh → 之后 process-info 呈现值守进程
                # （含 --pane 目标实参；QWB_STUB_NOPROC=1 抑制写入，模拟投递后进程始终起不来）
                if [[ "\${4:-}" == *qwb-wake.sh* && "\${QWB_STUB_NOPROC:-}" != "1" ]]; then
                  proj="\$(printf '%s' "\${4:-}" | sed -n "s/.*--project[[:space:]]*['\\"]*\\([^ '\\"]*\\).*/\\1/p")"
                  tgt="\$(printf '%s' "\${4:-}" | sed -n "s/.*--pane[[:space:]]*['\\"]*\\([^ '\\"]*\\).*/\\1/p")"
                  sed "s|/tmp/qwb02probe|\$proj|g; s|/private/tmp/qwb02probe|\$proj|g" \
                    "\${HERDR_FIXDIR:-$FIXDIR}/proc-wake.json" \
                    | { [[ -n "\$tgt" ]] && sed -e "s|--interval 5000|--pane \$tgt --interval 5000|g" \
                          -e "s|\\"--interval\\"|\\"--pane\\",\\"\$tgt\\",\\"--interval\\"|g" || cat; } \
                    | sed '/^#/d' > "\$DYNH/proc-\$(san "\$3").json" 2>/dev/null || true
                fi
                fix pane-run.json ;;
  "pane send-keys") fix pane-run.json ;;
  "pane list")  if [[ "\${QWB_STUB_SLOW_LIST:-}" == "1" ]]; then sleep 8; fi
                if [[ "\${HERDR_FAIL:-}" == *list* ]]; then failjson io_error "mocked pane list failure"; fi
                if [[ -f "\$DYNH/pane-list.json" ]]; then sed '/^#/d' "\$DYNH/pane-list.json"; else fix pane-list.json; fi ;;
  "workspace list") if [[ "\${HERDR_FAIL:-}" == *wslist* ]]; then failjson io_error "mocked workspace list failure"; fi
                if [[ -f "\$DYNH/workspace-list.json" ]]; then base="\$(sed '/^#/d' "\$DYNH/workspace-list.json")"; else base="\$(fix workspace-list.json)"; fi
                if [[ -f "\$DYNH/spaces.tsv" ]]; then
                  printf '%s' "\$base" | perl -MJSON::PP=decode_json,encode_json -e '
                    my \$raw=do { local \$/; <STDIN> }; my \$j=decode_json(\$raw);
                    open my \$fh,"<",\$ARGV[0] or die \$!;
                    while (<\$fh>) { chomp; my (\$id,\$root,\$path)=split /\\t/,\$_,3;
                      push @{ \$j->{result}{workspaces} }, {workspace_id=>\$id,focused=>JSON::PP::false,
                        worktree=>{repo_root=>\$root,checkout_path=>\$path,is_linked_worktree=>JSON::PP::true}} }
                    print encode_json(\$j),"\n";' "\$DYNH/spaces.tsv"
                else printf '%s\n' "\$base"; fi ;;
  "worktree open") shift 2; root=""; path=""
                while [[ \$# -gt 0 ]]; do
                  case "\$1" in --cwd) root="\$2"; shift 2;; --path) path="\$2"; shift 2;; *) shift;; esac
                done
                [[ -n "\$root" && -n "\$path" ]] || failjson invalid_args "missing worktree path"
                mkdir -p "\$DYNH"
                id="wQ\$(printf '%s' "\$path" | shasum | cut -c1-8)"; already=false
                if [[ -f "\$DYNH/spaces.tsv" ]] && cut -f3 "\$DYNH/spaces.tsv" | grep -Fxq "\$path"; then
                  already=true
                else printf '%s\t%s\t%s\n' "\$id" "\$root" "\$path" >> "\$DYNH/spaces.tsv"; fi
                perl -MJSON::PP=encode_json -e 'my (\$id,\$already)=@ARGV;
                  print encode_json({result=>{already_open=>(\$already eq "true" ? JSON::PP::true : JSON::PP::false),
                    workspace=>{workspace_id=>\$id},root_pane=>{tab_id=>"\$id:t1"}}}),"\n";' "\$id" "\$already" ;;
  "pane get")   if [[ -f "\$DYNH/get-\$(san "\${3:-}").json" ]]; then sed '/^#/d' "\$DYNH/get-\$(san "\${3:-}").json";
                elif [[ -f "\$DYNH/get-\$(san "\${3:-}").err" ]]; then cat "\$DYNH/get-\$(san "\${3:-}").err" >&2; exit 1;
                else failjson pane_not_found "pane \${3:-} not found"; fi ;;
  "pane process-info") pp="\${4:-\${3:-}}"
                if [[ -f "\$DYNH/proc-\$(san "\$pp").json" ]]; then sed '/^#/d' "\$DYNH/proc-\$(san "\$pp").json";
                elif [[ -f "\$DYNH/proc-\$(san "\$pp").err" ]]; then cat "\$DYNH/proc-\$(san "\$pp").err" >&2; exit 1;
                else failjson pane_not_found "pane \$pp not found"; fi ;;
  "pane read")  if [[ "\${HERDR_READ_TRUST:-}" == "1" ]]; then cat "\${HERDR_FIXDIR:-$FIXDIR}/pane-read-trust.txt";
                elif [[ -f "\$DYNH/read-\$(san "\${3:-}").txt" ]]; then cat "\$DYNH/read-\$(san "\${3:-}").txt";
                else cat "\${HERDR_FIXDIR:-$FIXDIR}/pane-read-shell.txt" 2>/dev/null || fix agent-wait.json; fi ;;
  "agent wait") if [[ "\${HERDR_FAIL:-}" == *wait* ]]; then fix agent-wait-timeout.json >&2; exit 1; fi
                if [[ -n "\${QWB_FAKE_NOW_FILE:-}" && "\${HERDR_WAIT_BUMP_MS:-0}" -gt 0 ]]; then
                  echo \$(( \$(cat "\$QWB_FAKE_NOW_FILE") + \${HERDR_WAIT_BUMP_MS} )) > "\$QWB_FAKE_NOW_FILE"
                fi
                fix agent-wait.json ;;
  "agent get")  nfile="\${HERDR_AGENT_GET_COUNT_FILE:-$TMP/herdr-agent-get.count}"
                n=\$(( \$(cat "\$nfile" 2>/dev/null || echo 0) + 1 )); echo "\$n" > "\$nfile"
                if [[ "\$n" -le "\${HERDR_AGENT_GET_FAILS:-0}" ]]; then fix agent-get-error.json >&2; exit 1; fi
                if [[ -f "\$DYNH/agent-get-\$(san "\${3:-}").json" ]]; then sed '/^#/d' "\$DYNH/agent-get-\$(san "\${3:-}").json";
                elif [[ -f "\$DYNH/agent-get-\$(san "\${3:-}").err" ]]; then cat "\$DYNH/agent-get-\$(san "\${3:-}").err" >&2; exit 1;
                elif [[ "\${3:-}" == *:* ]]; then fix agent-get-cmd.json;
                else fix agent-get-error.json >&2; exit 1; fi ;;
  "agent rename") fix agent-get-cmd.json ;;
  "tab create") if [[ -f "\$DYNH/tab-create.json" ]]; then cat "\$DYNH/tab-create.json"; else fix tab-create.json; fi ;;
  "tab close")  if [[ "\${HERDR_FAIL:-}" == *tabclose* ]]; then failjson io_error "mocked tab close failure"; fi
                printf '{"id":"cli:tab:close","result":{"type":"ok"}}\n' ;;
  "agent start") if [[ "\${HERDR_FAIL:-}" == *start* ]]; then fix agent-start-name-taken.json >&2; exit 1; fi
                fix agent-start.json ;;
  "agent prompt") if [[ "\${HERDR_FAIL:-}" == *prompt* ]]; then failjson inject_failed "mocked prompt failure"; fi
                fix agent-prompt.json ;;
  "agent list") fix agent-list.json ;;
  *) fix agent-wait.json ;;
esac
exit 0
EOF
chmod +x "$STUB/herdr"

printf '# 假任务\nstate: running\n' > "$FAKE"
( cd "$TMP" && PATH="$STUB:$PATH" bash qwbuddy/bin/qwb-wake.sh --once --pane wtest:p9 ) >/dev/null \
  && ok "wake --once 有未结项退出 0" || bad "wake --once 有未结项非 0"
grep -q '^wake:' "$FAKE" && ok "已写 wake: 去重行" || bad "未写 wake: 去重行"
grep -q 'pane run' "$STUBLOG" && ok "stub 日志有 pane run 叫醒" || bad "stub 日志无 pane run"

echo "== 8. 变量后紧跟非 ASCII 字符扫描（回归 Bug 1）=="
if command -v python3 >/dev/null 2>&1; then
  if python3 - "$ROOT"/bin/*.sh <<'PYEOF'
import re, sys
pat = re.compile(r'\$[A-Za-z_][A-Za-z0-9_]*[^\x00-\x7F]')
bad = 0
for path in sys.argv[1:]:
    for i, line in enumerate(open(path, encoding='utf-8'), 1):
        for m in pat.finditer(line):
            print(f'{path}:{i}: {m.group(0)}')
            bad += 1
sys.exit(1 if bad else 0)
PYEOF
  then ok "bin/*.sh 无 \$VAR+非ASCII 写法"; else bad "bin/*.sh 存在 \$VAR+非ASCII 写法"; fi
else
  echo "SKIP  无 python3，跳过扫描"
fi

echo "== 9. qwb-run.sh 真实派发（stub herdr）=="
DISP="$TMP/tasks/2099-01-02-disp.md"
cat > "$DISP" <<'EOF'
# 派发测试
state: blocked

## 1. 验收场景

### user_正常路径
Given 任务书已写好
When  主控派发
Then  账本追加 dispatch 行

### user_失败路径
Given 工人名非法
When  主控派发
Then  拒绝派发并报错
EOF
( cd "$TMP" && PATH="$STUB:$PATH" HERDR_PANE_ID=wtest:ctl bash qwbuddy/bin/qwb-run.sh --task disp --worker codex --here ) >/dev/null \
  && ok "qwb-run.sh 派发退出 0" || bad "qwb-run.sh 派发非 0"
grep -q '^state: running' "$DISP" && ok "任务书 state 变为 running" || bad "任务书 state 未变 running"
grep -q '^dispatch:' "$DISP" && ok "任务书末尾有 dispatch: 行" || bad "任务书无 dispatch: 行"
grep -q '^scenarios-fp:' "$DISP" && ok "任务书写入 scenarios-fp 冻结指纹" || bad "任务书无 scenarios-fp"
ddir="$(grep '^dispatch:' "$DISP" | tail -1 | sed -n 's/.*dir=\([^[:space:]]*\).*/\1/p')"
[[ "$ddir" == "$(cd "$TMP" && pwd)" ]] \
  && ok "--here 派发 dir= 项目根本身" || bad "--here dir 不对（${ddir}）"
grep -q '非隔离' "$STUBLOG" && ok "--here 提示词写明非隔离目录" || bad "--here 提示词未写非隔离"
grep -q 'agent start' "$STUBLOG" && ok "stub 日志有 agent start" || bad "stub 日志无 agent start"
grep -q 'agent prompt' "$STUBLOG" && ok "stub 日志有 agent prompt" || bad "stub 日志无 agent prompt"
grep -qF "$DISP" "$STUBLOG" && ok "prompt 参数含任务书绝对路径" || bad "prompt 参数缺任务书绝对路径"

echo "== 10. F3 回归：工人追加 done: → 进展指纹变 → 再次叫醒 =="
F3F="$TMP/tasks/2099-01-03-f3.md"
printf '# F3\nstate: running\nwake: 2026-01-01T00:00:00Z state=running fp=0000oldfp\n' > "$F3F"
printf 'done: 工人完成，附检查证据\n' >> "$F3F"
out="$( cd "$TMP" && bash qwbuddy/bin/qwb-wake.sh --dry-run --once )"
printf '%s' "$out" | grep -q '未结项（将叫醒）: 2099-01-03-f3' \
  && ok "追加 done: 后再次列为未结项" || bad "追加 done: 后仍未列为未结项"
# 真跑一轮写下新指纹；之后账本不再变 → 不再叫
( cd "$TMP" && PATH="$STUB:$PATH" bash qwbuddy/bin/qwb-wake.sh --once --pane wtest:p9 ) >/dev/null
out="$( cd "$TMP" && bash qwbuddy/bin/qwb-wake.sh --dry-run --once )"
printf '%s' "$out" | grep -q '未结项（将叫醒）: 2099-01-03-f3' \
  && bad "进展未变仍重复叫" || ok "写下新指纹后进展未变→不再叫"
# 兼容旧格式：无 fp= 的 wake 行视为指纹不同 → 允许再叫
F3O="$TMP/tasks/2099-01-05-f3old.md"
printf '# 旧格式\nstate: running\nwake: 2026-01-01T00:00:00Z state=running\n' > "$F3O"
out="$( cd "$TMP" && bash qwbuddy/bin/qwb-wake.sh --dry-run --once )"
printf '%s' "$out" | grep -q '未结项（将叫醒）: 2099-01-05-f3old' \
  && ok "无 fp= 的旧 wake 行→仍列为未结项" || bad "无 fp= 的旧 wake 行被误跳过"

echo "== 11. F4 回归：投递失败不终止值守、不写 wake 行 =="
F4F="$TMP/tasks/2099-01-04-f4.md"
printf '# F4\nstate: running\n' > "$F4F"
( cd "$TMP" && PATH="$STUB:$PATH" HERDR_FAIL=run bash qwbuddy/bin/qwb-wake.sh --once --pane wtest:p9 ) >/dev/null 2>&1 \
  && ok "投递失败时 --once 退出码 0" || bad "投递失败时 --once 非 0"
grep -q '^wake:' "$F4F" && bad "投递失败仍写了 wake 行" || ok "投递失败未写 wake 行"

# —— 假时钟装置（QWB_NOW_MS_CMD / QWB_SLEEP_CMD 注入）：预算断言不再真 sleep ——
# now.sh 每次调用 +STEP；sleep.sh 记参数不真睡，满 N 次杀掉 wake.sh 截断循环；看门狗防死循环。
FKN="$TMP/fake-now"; FKS="$TMP/fake-sleep.log"
mk_fakeclock() { # $1=STEP $2=截断次数
  echo 0 > "$FKN"; : > "$FKS"
  cat > "$TMP/now.sh" <<EOF
#!/usr/bin/env bash
cur="\$(( \$(cat "$FKN") + $1 ))"; echo "\$cur" > "$FKN"; echo "\$cur"
EOF
  cat > "$TMP/sleep.sh" <<EOF
#!/usr/bin/env bash
echo "\$1" >> "$FKS"
[[ "\$(wc -l < "$FKS" | tr -d ' ')" -ge $2 ]] && kill "\$PPID" 2>/dev/null
exit 0
EOF
  chmod +x "$TMP/now.sh" "$TMP/sleep.sh"
}
run_wake_fakeclock() { # 调用方以 `VAR=x run_wake_fakeclock` 形式传额外环境变量
  ( cd "$TMP" && PATH="$STUB:$PATH" QWB_NOW_MS_CMD="$TMP/now.sh" QWB_SLEEP_CMD="$TMP/sleep.sh" \
      QWB_FAKE_NOW_FILE="$FKN" HERDR_FAIL="${HERDR_FAIL:-}" HERDR_WAIT_BUMP_MS="${HERDR_WAIT_BUMP_MS:-0}" \
      exec bash qwbuddy/bin/qwb-wake.sh --pane wtest:p9 --interval 1000 ) >/dev/null 2>&1 &
  WPID=$!
  ( sleep 15; kill "$WPID" 2>/dev/null ) & WD=$!
  wait "$WPID" 2>/dev/null || true
  kill "$WD" 2>/dev/null; wait "$WD" 2>/dev/null || true
}
# 等待预算需要一个带 dispatch: pane 的未结项
FCF="$TMP/tasks/2099-01-20-fakeclock.md"
printf '# fc\nstate: running\ndispatch: 2026-01-01T00:00:00Z worker=codex agent=qwb-fc pane=wtest:p9 dir=/tmp\n' > "$FCF"
all_eq() { # 全部行 == $1 且非空
  local want="$1" l
  [[ -s "$FKS" ]] || return 1
  while IFS= read -r l; do [[ "$l" == "$want" ]] || return 1; done < "$FKS"; return 0
}

echo "== 12. F2 回归（假时钟）：agent wait 失败 → 每轮恰 1 次 wait + 补睡满 1×interval，无忙循环 =="
mk_fakeclock 250 3
: > "$STUBLOG"
HERDR_FAIL=wait run_wake_fakeclock
nsl="$(wc -l < "$FKS" | tr -d ' ')"; nwt="$(grep -c 'agent wait' "$STUBLOG" || true)"
[[ "$nsl" == "3" && "$nwt" == "3" ]] \
  && ok "3 轮 = 3 次 agent wait + 3 次补睡（每轮恰一次）" || bad "轮次不符：wait=${nwt} sleep=${nsl}"
all_eq 750 && ok "每轮补睡 750ms（interval 1000 − wait 已耗 250 = 恰 1×interval）" \
  || { bad "补睡值不对（应全 750）:"; cat "$FKS"; }

echo "== 12b. G2 回归（假时钟）：agent wait 耗时计入预算，超时路径不重复 sleep =="
mk_fakeclock 50 3
: > "$STUBLOG"
HERDR_WAIT_BUMP_MS=600 run_wake_fakeclock   # wait 烧掉 600ms → dt=650 → 应补睡 350，旧实现会再睡 1000
nsl="$(wc -l < "$FKS" | tr -d ' ')"; nwt="$(grep -c 'agent wait' "$STUBLOG" || true)"
[[ "$nsl" == "3" && "$nwt" == "3" ]] \
  && ok "3 轮 = 3 次 wait + 3 次补睡" || bad "轮次不符：wait=${nwt} sleep=${nsl}"
all_eq 350 && ok "wait 耗 650ms 后只补睡 350ms（已耗计入预算；旧实现会睡满 1000）" \
  || { bad "补睡值不对（应全 350）:"; cat "$FKS"; }
grep -qx '1000' "$FKS" && bad "出现整睡 1000——超时路径仍重复 sleep（G2 未修）" \
  || ok "无整睡 1000：超时路径未重复 sleep"

echo "== 12c. H2 回归（假时钟）：agent wait 立即成功也计入预算，无忙循环 =="
mk_fakeclock 1 3                          # 每次读钟仅 +1ms → wait 视为瞬时 → 应补睡 999
: > "$STUBLOG"
run_wake_fakeclock
nsl="$(wc -l < "$FKS" | tr -d ' ')"; nwt="$(grep -c 'agent wait' "$STUBLOG" || true)"
[[ "$nsl" == "3" && "$nwt" == "3" ]] \
  && ok "3 轮 = 3 次 wait + 3 次补睡（不真睡也不忙循环）" || bad "轮次不符：wait=${nwt} sleep=${nsl}"
all_eq 999 && ok "瞬时 wait 每轮补睡 999ms ≈1×interval（修复前实测 4.9 秒 91 轮）" \
  || { bad "补睡值不对（应全 999）:"; cat "$FKS"; }

echo "== 12d. 无 dispatch pane 路径：整睡一个 interval =="
NP="$TMP/nopane"; mkdir -p "$NP/tasks" "$NP/qwbuddy"
printf '# np\nstate: running\n' > "$NP/tasks/2099-01-21-np.md"
cp "$TMP/qwbuddy/config.sh" "$NP/qwbuddy/config.sh"
mk_fakeclock 100 2
( cd "$NP" && PATH="$STUB:$PATH" QWB_NOW_MS_CMD="$TMP/now.sh" QWB_SLEEP_CMD="$TMP/sleep.sh" \
    exec bash "$TMP/qwbuddy/bin/qwb-wake.sh" --pane wtest:p9 --interval 1000 ) >/dev/null 2>&1 &
WPID=$!
( sleep 15; kill "$WPID" 2>/dev/null ) & WD=$!
wait "$WPID" 2>/dev/null || true
kill "$WD" 2>/dev/null; wait "$WD" 2>/dev/null || true
all_eq 1000 && ok "无可用 pane 时每轮整睡 1000ms（=1×interval 退化等待）" \
  || { bad "整睡值不对（应全 1000）:"; cat "$FKS"; }

echo "== 12e. 真时钟轻量冒烟：真跑一轮 =="
: > "$STUBLOG"
( cd "$TMP" && PATH="$STUB:$PATH" exec bash qwbuddy/bin/qwb-wake.sh --pane wtest:p9 --interval 600 ) >/dev/null 2>&1 &
WPID=$!
sleep 1.3
kill "$WPID" 2>/dev/null; wait "$WPID" 2>/dev/null || true
n="$(grep -c 'agent wait' "$STUBLOG" || true)"
[[ "$n" -ge 1 && "$n" -le 4 ]] \
  && ok "1.3 秒内 ${n} 次 agent wait（真时钟真跑，节奏正常）" || bad "1.3 秒内 ${n} 次 agent wait（异常）"

echo "== 13. F1 回归：主控锁 =="
# 残留锁自动回收落地后，「锁被占用而拒绝」必须用活锁主构造：stub + dyn 片场让锁主 pane 真实存在；
# 死 pid / pane_not_found 的锁主会被 acquire 自动回收再获锁（回收专项见 §59）
LOCKD="$TMP/qwbuddy/.controller.lock"
LK13="$TMP/herdr-dyn13"; rm -rf "$LK13"; mkdir -p "$LK13"
sed "s|w8Z:pY|wtest:p9|g" "$FIXDIR/pane-get-shell.json" > "$LK13/get-wtestp9.json"
rm -rf "$LOCKD"
( cd "$TMP" && bash qwbuddy/bin/qwb-lock.sh acquire --owner wtest:p9 ) >/dev/null \
  && ok "acquire 成功" || bad "acquire 失败"
( cd "$TMP" && PATH="$STUB:$PATH" HERDR_DYN_DIR="$LK13" bash qwbuddy/bin/qwb-lock.sh acquire --owner wtest:p8 ) >/dev/null 2>&1 \
  && bad "第二次 acquire 竟成功" || ok "活锁主在时第二次 acquire 被拒"
( cd "$TMP" && bash qwbuddy/bin/qwb-lock.sh status ) | grep -q 'wtest:p9' \
  && ok "status 显示锁主" || bad "status 未显示锁主"
( cd "$TMP" && bash qwbuddy/bin/qwb-lock.sh release ) >/dev/null \
  && ok "release 成功" || bad "release 失败"
( cd "$TMP" && bash qwbuddy/bin/qwb-lock.sh acquire --owner wtest:p9 ) >/dev/null \
  && ok "release 后可再 acquire" || bad "release 后 acquire 失败"
( cd "$TMP" && PATH="$STUB:$PATH" HERDR_DYN_DIR="$LK13" HERDR_PANE_ID=wtest:p7 bash qwbuddy/bin/qwb-run.sh --task disp --worker codex --worktree "$TMP" ) >/dev/null 2>&1 \
  && bad "他人（锁主 pane 存活）持锁时 qwb-run.sh 仍派发" || ok "他人持锁时 qwb-run.sh 拒绝派发"
( cd "$TMP" && PATH="$STUB:$PATH" HERDR_DYN_DIR="$LK13" HERDR_PANE_ID=wtest:p9 bash qwbuddy/bin/qwb-run.sh --task disp --worker codex --worktree "$TMP" ) >/dev/null \
  && ok "自持锁时可派发" || bad "自持锁时派发被拒"
rm -rf "$LOCKD"

echo "== 14. R2：config.sh 无死配置 =="
ckeys="$(sed -n 's/^\(QWB_[A-Z_]*\)=.*/\1/p' "$TMP/qwbuddy/config.sh")"
[[ -n "$ckeys" ]] || bad "config.sh 未提取到 QWB_* 键"
for k in $ckeys; do
  if grep -q "$k" "$ROOT"/bin/qwb-*.sh; then ok "$k 有脚本读取"; else bad "$k 是死配置（bin/ 无引用）"; fi
done

echo "== 15. R3+G3：--worker 非法名被拒（整词精确匹配）=="
r3out=""
for wname in workers '(codex)' note; do
  : > "$STUBLOG"
  if r3out="$( cd "$TMP" && PATH="$STUB:$PATH" bash qwbuddy/bin/qwb-run.sh --task disp --worker "$wname" 2>&1 )"; then
    bad "--worker ${wname} 竟被接受"
  else
    ok "--worker ${wname} 被拒绝（退出码非 0）"
  fi
  grep -q 'agent start' "$STUBLOG" && bad "--worker ${wname} 仍调用了 herdr agent start" || ok "--worker ${wname} 未调用 agent start"
done
printf '%s' "$r3out" | grep -qF 'codex pi claude devin omp' && ok "报错列出全部合法工人名" || bad "报错未列出合法工人名"

echo "== 16. R4：非法 state 变可见 =="
ILF="$TMP/tasks/2099-01-06-illegal.md"
printf '# 非法状态\nstate: pending\n' > "$ILF"
out="$( cd "$TMP" && bash qwbuddy/bin/qwb-status.sh 2>&1 )"
printf '%s' "$out" | grep -q '非法' && ok "status 对 state=pending 显示非法标记" || bad "status 未标非法 state"
out="$( cd "$TMP" && bash qwbuddy/bin/qwb-wake.sh --dry-run --once 2>&1 )"
printf '%s' "$out" | grep -q 'state=pending 非法' && ok "wake 对 state=pending 发 stderr 警告" || bad "wake 未警告非法 state"
printf '%s' "$out" | grep -q '未结项（将叫醒）: 2099-01-06-illegal' \
  && bad "非法 state 被列为未结项" || ok "非法 state 不算未结项"
# 对照：无 state: 字段行的说明文档（如 lessons.md）不算任务书，status 跳过不标 [非法]
DOCF="$TMP/tasks/lessons.md"
printf '# 错题本\n只是说明文档，无 state 字段\n' > "$DOCF"
out="$( cd "$TMP" && bash qwbuddy/bin/qwb-status.sh 2>&1 )"
printf '%s' "$out" | grep '非法' | grep -q 'lessons\.md' \
  && bad "无 state 字段文档被误标 [非法]" || ok "无 state 字段文档 status 不标 [非法]"
printf '%s' "$out" | grep -q '非法' \
  && ok "有非法值任务书仍报 [非法]" || bad "有非法值任务书未报 [非法]"

echo "== 17. R1：qwb-worktree.sh 端到端（临时 git 项目）=="
GP="$TMP/gitp"
mkdir -p "$GP/tasks" "$GP/.worktrees" "$GP/qwbuddy"
cp "$TMP/qwbuddy/config.sh" "$GP/qwbuddy/config.sh"
cp "$ROOT/templates/workers.sh" "$GP/qwbuddy/workers.sh"
git -C "$GP" init -q
git -C "$GP" -c user.email=t@t.t -c user.name=t commit -qm init --allow-empty
WTB="$TMP/qwbuddy/bin/qwb-worktree.sh"
qwb_finish() { PATH="$STUB:$PATH" bash "$WTB" finish "$@"; }

WTID="wtdemo"; WTF="$GP/tasks/2099-01-07-${WTID}.md"
printf '# demo\nstate: running\n' > "$WTF"
git -C "$GP" worktree add -q -b "$WTID" "$GP/.worktrees/$WTID"
out="$(bash "$WTB" list --project "$GP")"
printf '%s' "$out" | grep -q "未结项.*${WTID}" && ok "list 标出未结项 worktree" || bad "list 未标出未结项"
mkdir -p "$GP/.worktrees/orphan"
out="$(bash "$WTB" list --project "$GP")"
printf '%s' "$out" | grep -q '残留.*orphan' && ok "list 标出残留目录" || bad "list 未标出残留"

# --merged 对未合并分支拒绝（先在分支上做个 commit 让它领先 HEAD）
git -C "$GP/.worktrees/$WTID" -c user.email=t@t.t -c user.name=t commit -qm wip --allow-empty
if qwb_finish "$WTID" --merged --project "$GP" >/dev/null 2>&1; then
  bad "--merged 对未合并分支竟放行"
else
  ok "--merged 对未合并分支拒绝"
fi
[[ -d "$GP/.worktrees/$WTID" ]] && ok "拒绝后 worktree 未动" || bad "拒绝后 worktree 被删"

# --keep：不动 git，只记账
qwb_finish "$WTID" --keep=等使用者裁决 --project "$GP" >/dev/null \
  && ok "finish --keep 退出 0" || bad "finish --keep 失败"
grep -q '^worktree: keep' "$WTF" && ok "任务书追加了 worktree: keep 行" || bad "任务书无 worktree: 行"
[[ -d "$GP/.worktrees/$WTID" ]] && ok "--keep 未删 worktree" || bad "--keep 删了 worktree"

# --archive：打 tag → 删 worktree → branch -D → 记账
qwb_finish "$WTID" --archive --project "$GP" >/dev/null \
  && ok "finish --archive 退出 0" || bad "finish --archive 失败"
git -C "$GP" rev-parse --verify --quiet "refs/tags/archive/$WTID" >/dev/null \
  && ok "产生 archive/$WTID 标签" || bad "无 archive 标签"
[[ -d "$GP/.worktrees/$WTID" ]] && bad "archive 后 worktree 仍在" || ok "archive 后 worktree 已删"
git -C "$GP" show-ref --verify --quiet "refs/heads/$WTID" && bad "archive 后分支仍在" || ok "archive 后分支已删"
grep -q 'tag=archive/' "$WTF" && ok "worktree: 行含 tag" || bad "worktree: 行缺 tag"

# 脏 worktree：--archive 拒绝，不动
WTD="wtdirty"; WTDF="$GP/tasks/2099-01-08-${WTD}.md"
printf '# dirty\nstate: running\n' > "$WTDF"
git -C "$GP" worktree add -q -b "$WTD" "$GP/.worktrees/$WTD"
echo x > "$GP/.worktrees/$WTD/dirty.txt"
if qwb_finish "$WTD" --archive --project "$GP" >/dev/null 2>&1; then
  bad "脏 worktree --archive 竟放行"
else
  ok "脏 worktree --archive 拒绝"
fi
[[ -d "$GP/.worktrees/$WTD" ]] && ok "拒绝后脏 worktree 未动" || bad "脏 worktree 被删"

# G4：--keep 不做脏检查——同一脏 worktree 上 --keep 退出 0 且记账
qwb_finish "$WTD" --keep=有冲突待解 --project "$GP" >/dev/null \
  && ok "脏 worktree --keep 退出 0（G4）" || bad "脏 worktree --keep 被拒（G4 未修）"
grep -q '^worktree: keep' "$WTDF" && ok "--keep 记账成功" || bad "--keep 未记账"
[[ -d "$GP/.worktrees/$WTD" ]] && ok "--keep 后脏 worktree 未动" || bad "--keep 动了 worktree"

# --merged 放行路径：分支合并进 HEAD 后正常收尾
WTM="wtmerged"; WTMF="$GP/tasks/2099-01-09-${WTM}.md"
printf '# merged\nstate: running\n' > "$WTMF"
git -C "$GP" worktree add -q -b "$WTM" "$GP/.worktrees/$WTM"
git -C "$GP/.worktrees/$WTM" -c user.email=t@t.t -c user.name=t commit -qm wip --allow-empty
git -C "$GP" -c user.email=t@t.t -c user.name=t merge -qm m "$WTM"
qwb_finish "$WTM" --merged --project "$GP" >/dev/null \
  && ok "已合并分支 --merged 放行" || bad "已合并分支 --merged 被拒"
[[ -d "$GP/.worktrees/$WTM" ]] && bad "merged 后 worktree 仍在" || ok "merged 后 worktree 已删"
git -C "$GP" show-ref --verify --quiet "refs/heads/$WTM" && bad "merged 后分支仍在" || ok "merged 后分支已删"

# qwb-run.sh --create-worktree：有残留 → 警告但不阻塞
cat > "$GP/tasks/2099-01-10-wtnew.md" <<'EOF'
# new
state: running

## 1. 验收场景

### user_正常
Given 任务书写好
When  主控派发
Then  worktree 建立并派发
### user_失败
Given 工人名非法
When  主控派发
Then  拒绝派发
EOF
r1out="$( cd "$GP" && PATH="$STUB:$PATH" bash "$TMP/qwbuddy/bin/qwb-run.sh" --task wtnew --worker codex --create-worktree 2>&1 )"
printf '%s' "$r1out" | grep -q '残留' && ok "--create-worktree 对残留打警告" || bad "--create-worktree 无残留警告"
[[ -d "$GP/.worktrees/wtnew" ]] && ok "警告不阻塞：worktree 已建" || bad "--create-worktree 被阻塞"

echo "== 18. G1：detached HEAD 下归档/落地以实际 HEAD OID 为准 =="
# 场景：分支 wtdet 在 A；checkout --detach 后提交 B（分支仍指 A）
WTG="wtdet"; WTGF="$GP/tasks/2099-01-12-${WTG}.md"
printf '# det\nstate: running\n' > "$WTGF"
git -C "$GP" worktree add -q -b "$WTG" "$GP/.worktrees/$WTG"
AOID="$(git -C "$GP/.worktrees/$WTG" rev-parse HEAD)"
git -C "$GP/.worktrees/$WTG" checkout -q --detach
git -C "$GP/.worktrees/$WTG" -c user.email=t@t.t -c user.name=t commit -qm wip --allow-empty
BOID="$(git -C "$GP/.worktrees/$WTG" rev-parse HEAD)"
[[ "$AOID" != "$BOID" ]] && ok "G1 场景就绪（A=${AOID:0:7} B=${BOID:0:7}）" || bad "G1 场景构造失败（A==B）"

# --merged 对未合并的 detached B 拒绝（旧实现会拿同名分支 A 放行）
if qwb_finish "$WTG" --merged --project "$GP" >/dev/null 2>&1; then
  bad "detached 未合并 --merged 竟放行（G1 未修）"
else
  ok "detached 未合并 --merged 拒绝"
fi
[[ -d "$GP/.worktrees/$WTG" ]] && ok "拒绝后 detached worktree 未动" || bad "拒绝后 detached worktree 被删"

# --archive：tag 必须指向 B（实际 HEAD OID），且同名分支保留
qwb_finish "$WTG" --archive --project "$GP" >/dev/null \
  && ok "detached --archive 退出 0" || bad "detached --archive 失败"
tagoid="$(git -C "$GP" rev-parse "archive/$WTG" 2>/dev/null || true)"
[[ "$tagoid" == "$BOID" ]] && ok "archive/${WTG} 指向 detached 提交 B" || bad "archive tag 指向 ${tagoid} 而非 B（${BOID}）"
git -C "$GP" show-ref --verify --quiet "refs/heads/$WTG" \
  && ok "同名分支 ${WTG} 保留（它不指向本工作区）" || bad "同名分支 ${WTG} 被误删（G1 未修）"
[[ -d "$GP/.worktrees/$WTG" ]] && bad "archive 后 worktree 仍在" || ok "archive 后 worktree 已删"
grep -q 'branch=detached' "$WTGF" && ok "worktree: 行记 branch=detached" || bad "worktree: 行未标 detached"

echo "== 19. G1b：git status 失败（非 0）→ 拒绝而非放行 =="
REAL_GIT="$(command -v git)"
GSTUB="$TMP/gitstub"; mkdir -p "$GSTUB"
cat > "$GSTUB/git" <<EOF
#!/usr/bin/env bash
if [[ "\${3:-}" == "status" ]]; then echo "fatal: mocked status failure" >&2; exit 128; fi
exec "$REAL_GIT" "\$@"
EOF
chmod +x "$GSTUB/git"
WTS="wtstf"; WTSF="$GP/tasks/2099-01-13-${WTS}.md"
printf '# stf\nstate: running\n' > "$WTSF"
git -C "$GP" worktree add -q -b "$WTS" "$GP/.worktrees/$WTS"
if PATH="$GSTUB:$PATH" qwb_finish "$WTS" --archive --project "$GP" >/dev/null 2>&1; then
  bad "git status 失败时 --archive 竟放行（G1b 未修）"
else
  ok "git status 失败 → --archive 拒绝"
fi
[[ -d "$GP/.worktrees/$WTS" ]] && ok "status 失败拒绝后 worktree 未动" || bad "status 失败后 worktree 被删"
git -C "$GP" rev-parse --verify --quiet "refs/tags/archive/$WTS" >/dev/null \
  && bad "status 失败仍打了 archive tag" || ok "status 失败未打 tag"

echo "== 20. G3：init 与 config.sh =="
PRES="$TMP/presproj"; mkdir -p "$PRES/qwbuddy"
printf 'QWB_CONTROLLER_PANE="wtest:mine"\n' > "$PRES/qwbuddy/config.sh"
bash "$ROOT/bin/qwb-init.sh" "$PRES" >/dev/null
grep -q 'wtest:mine' "$PRES/qwbuddy/config.sh" \
  && ok "init 不覆盖已存在 config.sh" || bad "init 覆盖了已存在 config.sh"
MIG="$TMP/migproj"; mkdir -p "$MIG/qwbuddy"
echo '{}' > "$MIG/qwbuddy/config.json"
migout="$(bash "$ROOT/bin/qwb-init.sh" "$MIG" 2>&1)"
printf '%s' "$migout" | grep -q '旧版' && ok "init 对旧版 JSON 配置打迁移提示" || bad "init 未打迁移提示"
assert_file "$MIG/qwbuddy/config.sh"

echo "== 21. G3：旧配置文件名仅允许见于 qwb-init.sh 迁移逻辑，且为可读字面量 =="
if grep -rn 'config\.json' "$ROOT/bin" | grep -v 'qwb-init\.sh' | grep -q .; then
  bad "bin/ 中除 qwb-init.sh 外仍出现旧配置文件名："
  grep -rn 'config\.json' "$ROOT/bin" | grep -v 'qwb-init\.sh' || true
else
  ok "bin/ 中旧配置文件名仅见于 qwb-init.sh"
fi
grep -q 'config\.json' "$ROOT/bin/qwb-init.sh" \
  && ok "qwb-init.sh 迁移逻辑含旧名可读字面量" || bad "qwb-init.sh 缺旧名可读字面量"
if grep -rnE "jso(\"\"|'')n" "$ROOT/bin" "$ROOT/tests" >/dev/null 2>&1; then
  bad "bin/ tests/ 仍有拼接构造旧配置名的写法"
  grep -rnE "jso(\"\"|'')n" "$ROOT/bin" "$ROOT/tests" || true
else
  ok "bin/ tests/ 无拼接构造旧配置名"
fi

echo "== 22. H1 回归：git 替身注入并发推进/读取失败 =="
GITLOG="$TMP/git-inj.log"; : > "$GITLOG"
GSTUB2="$TMP/gitstub2"; mkdir -p "$GSTUB2"
cat > "$GSTUB2/git" <<EOF
#!/usr/bin/env bash
echo "git \$*" >> "$GITLOG"
sub="\${3:-}"; a4="\${4:-}"
if [[ "\$sub" == "rev-parse" && "\$a4" == "--abbrev-ref" && "\${INJ_MODE:-}" == "branchread" ]]; then
  echo "fatal: mocked branch read failure" >&2; exit 128
fi
if [[ "\$sub" == "tag" && "\${INJ_MODE:-}" == "posttag" ]]; then
  "$REAL_GIT" "\$@" || exit \$?
  "$REAL_GIT" -C "\$INJ_WT" -c user.email=t@t.t -c user.name=t commit -qm inject --allow-empty
  exit 0
fi
if [[ "\$sub" == "merge-base" && "\$a4" == "--is-ancestor" && "\${INJ_MODE:-}" == "postmerge" ]]; then
  "$REAL_GIT" -C "\$INJ_WT" -c user.email=t@t.t -c user.name=t commit -qm inject --allow-empty
  exit 0
fi
exec "$REAL_GIT" "\$@"
EOF
chmod +x "$GSTUB2/git"

# 22a：--archive 打标签之后、remove 之前 HEAD 被推进 → 拒绝删除，已打标签保留
WTI="wtinj"; WTIF="$GP/tasks/2099-01-14-${WTI}.md"
printf '# inj\nstate: running\n' > "$WTIF"
git -C "$GP" worktree add -q -b "$WTI" "$GP/.worktrees/$WTI"
: > "$GITLOG"
if PATH="$GSTUB2:$PATH" INJ_MODE=posttag INJ_WT="$GP/.worktrees/$WTI" qwb_finish "$WTI" --archive --project "$GP" >/dev/null 2>&1; then
  bad "打标签后 HEAD 被推进 --archive 竟放行（H1 未修）"
else
  ok "打标签后 HEAD 被推进 → --archive 拒绝删除"
fi
[[ -d "$GP/.worktrees/$WTI" ]] && ok "拒绝后 worktree 未动" || bad "拒绝后 worktree 仍被删"
grep -q 'worktree remove' "$GITLOG" && bad "仍调用了 worktree remove" || ok "未调用 worktree remove"
grep -q 'branch -D' "$GITLOG" && bad "仍调用了 branch -D" || ok "未调用 branch -D"
git -C "$GP" rev-parse --verify --quiet "refs/tags/archive/$WTI" >/dev/null \
  && ok "已打的 archive tag 保留" || bad "已打 tag 丢失"
git -C "$GP" show-ref --verify --quiet "refs/heads/$WTI" && ok "分支保留" || bad "分支被误删"

# 22b：--merged 核实通过之后、remove 之前 HEAD 被推进 → 同样拒绝
WTJ="wtinjm"; WTJF="$GP/tasks/2099-01-15-${WTJ}.md"
printf '# injm\nstate: running\n' > "$WTJF"
git -C "$GP" worktree add -q -b "$WTJ" "$GP/.worktrees/$WTJ"
: > "$GITLOG"
if PATH="$GSTUB2:$PATH" INJ_MODE=postmerge INJ_WT="$GP/.worktrees/$WTJ" qwb_finish "$WTJ" --merged --project "$GP" >/dev/null 2>&1; then
  bad "--merged 核实通过后 HEAD 被推进竟放行（H1 未修）"
else
  ok "--merged 核实通过后 HEAD 被推进 → 拒绝删除"
fi
[[ -d "$GP/.worktrees/$WTJ" ]] && ok "拒绝后 worktree 未动" || bad "拒绝后 worktree 仍被删"
grep -q 'worktree remove' "$GITLOG" && bad "仍调用了 worktree remove" || ok "未调用 worktree remove"

# 22c：分支身份读取失败 → 拒绝，不回退成任务 id 继续删
WTK="wtinjb"; WTKF="$GP/tasks/2099-01-16-${WTK}.md"
printf '# injb\nstate: running\n' > "$WTKF"
git -C "$GP" worktree add -q -b "$WTK" "$GP/.worktrees/$WTK"
: > "$GITLOG"
if PATH="$GSTUB2:$PATH" INJ_MODE=branchread qwb_finish "$WTK" --archive --project "$GP" >/dev/null 2>&1; then
  bad "分支名读取失败 --archive 竟放行（H1 未修）"
else
  ok "分支名读取失败 → 拒绝（不回退成任务 id）"
fi
[[ -d "$GP/.worktrees/$WTK" ]] && ok "拒绝后 worktree 未动" || bad "拒绝后 worktree 仍被删"
grep -qE 'worktree remove|branch -D| tag ' "$GITLOG" \
  && bad "身份未知仍执行了打标/删除" || ok "未打标未删除"
git -C "$GP" rev-parse --verify --quiet "refs/tags/archive/$WTK" >/dev/null \
  && bad "分支身份未知仍打了 tag" || ok "未打 tag"

echo "== 23. A：qwb-test.sh 快门/全门 =="
assert_file "$ROOT/qwb.config.sh"
bash "$ROOT/bin/qwb-test.sh" --help >/dev/null && ok "qwb-test.sh --help 退出 0" || bad "--help 非 0"
bash "$ROOT/bin/qwb-test.sh" fast --project "$ROOT" >/dev/null 2>&1 \
  && ok "母本仓 fast 门退出 0" || bad "母本仓 fast 门非 0"
# 门命令覆盖：往临时项目配置追加可用门
printf 'QWB_GATE_FAST="echo fastgate-ok"\nQWB_GATE_FULL="exit 7"\n' >> "$TMP/qwbuddy/config.sh"
out="$(bash "$ROOT/bin/qwb-test.sh" fast --project "$TMP" 2>&1)"; rc=$?
[[ "$rc" -eq 0 ]] && printf '%s' "$out" | grep -q 'fastgate-ok' \
  && ok "fast 门原样转发输出且退出 0" || bad "fast 门输出/退出码不对（rc=${rc}）"
out="$(bash "$ROOT/bin/qwb-test.sh" full --project "$TMP" 2>&1)"; rc=$?
[[ "$rc" -eq 7 ]] && ok "full 门失败退出码透传（7）" || bad "退出码未透传（rc=${rc}，应 7）"
printf '%s' "$out" | grep -qF '门失败（full）：exit 7 退出码=7' \
  && ok "门失败行格式正确且到 stderr/输出可见" || bad "缺「门失败（full）：…退出码=7」行"
# qwb.config.sh 回退（无 qwbuddy/ 的母本仓形态）
FB="$TMP/fallback"; mkdir -p "$FB"
printf 'QWB_GATE_FAST="echo fb-fast-ok"\n' > "$FB/qwb.config.sh"
out="$(bash "$ROOT/bin/qwb-test.sh" fast --project "$FB" 2>&1)"; rc=$?
[[ "$rc" -eq 0 ]] && printf '%s' "$out" | grep -q 'fb-fast-ok' \
  && ok "无 qwbuddy/ 时回退 qwb.config.sh" || bad "qwb.config.sh 回退失效（rc=${rc}）"
# 优先级：qwbuddy/config.sh 先于 qwb.config.sh
mkdir -p "$FB/qwbuddy"; printf 'QWB_GATE_FAST="echo qwbuddy-wins"\n' > "$FB/qwbuddy/config.sh"
out="$(bash "$ROOT/bin/qwb-test.sh" fast --project "$FB" 2>&1)"
printf '%s' "$out" | grep -q 'qwbuddy-wins' \
  && ok "qwbuddy/config.sh 优先于 qwb.config.sh" || bad "配置优先级不对"
# 未声明门：报错并给出正确写法
out="$(bash "$ROOT/bin/qwb-test.sh" full --project "$FB" 2>&1)"; rc=$?
{ [[ "$rc" -ne 0 ]] && printf '%s' "$out" | grep -q 'QWB_GATE_FULL' && printf '%s' "$out" | grep -q 'QWB_GATE_FULL="bash tests/smoke.sh'; } \
  && ok "未声明门时报错并给出声明写法" || bad "未声明门处理不对（rc=${rc}）"
# 无配置项目：报错
MT="$TMP/empty-proj"; mkdir -p "$MT"
bash "$ROOT/bin/qwb-test.sh" fast --project "$MT" >/dev/null 2>&1 \
  && bad "无配置项目 fast 竟成功" || ok "无配置项目报错非 0"

# 报告接口：通过真实 CLI 观察输出、退出码、次数及最终落盘内容。
RP="$TMP/report-project"; RD="$TMP/report-files"; mkdir -p "$RP" "$RD"
cat > "$RP/qwb.config.sh" <<'EOF'
QWB_GATE_FAST='printf "gate-stdout\n"; printf "gate-stderr\n" >&2; printf x >> count'
QWB_GATE_FULL='printf "gate-seven\n" >&2; printf x >> count; exit 7'
EOF
git -C "$RP" init -q
git -C "$RP" add qwb.config.sh
git -C "$RP" -c user.name=Smoke -c user.email=smoke@example.invalid commit -qm seed
RHEAD="$(git -C "$RP" rev-parse HEAD)"
export QWB_REPORT_SECRET_CANARY='env-secret-canary'
bash "$ROOT/bin/qwb-test.sh" fast --project "$RP" > "$RD/legacy.out" 2> "$RD/legacy.err"; rc=$?
[[ "$rc" -eq 0 && "$(cat "$RD/legacy.out")" == 'gate-stdout' && "$(cat "$RD/legacy.err")" == 'gate-stderr' && "$(wc -c < "$RP/count" | tr -d ' ')" == 1 ]] \
  && ok "旧 fast 调用 stdout/stderr 与单次执行不变" || bad "旧 fast 调用兼容失败"
rm "$RP/count"
bash "$ROOT/bin/qwb-test.sh" full --project "$RP" > "$RD/legacy-seven.out" 2> "$RD/legacy-seven.err"; rc=$?
[[ "$rc" -eq 7 && ! -s "$RD/legacy-seven.out" && "$(wc -c < "$RP/count" | tr -d ' ')" == 1 ]] \
  && grep -qF 'gate-seven' "$RD/legacy-seven.err" && grep -qF '门失败（full）' "$RD/legacy-seven.err" \
  && ok "旧 full 调用 stderr、7 与单次执行不变" || bad "旧 full 调用兼容失败"
[[ "$(find "$RD" -name '*.md' | wc -l | tr -d ' ')" == 0 ]] && ok "旧调用不生成报告" || bad "旧调用生成报告"
rm "$RP/count"
git -C "$RP" status --porcelain | grep -q . && bad "报告前项目非 clean" || ok "报告前项目 clean"
bash "$ROOT/bin/qwb-test.sh" fast --project "$RP" --report "$RD/zero.md" > "$RD/zero.out" 2> "$RD/zero.err"; rc=$?
[[ "$rc" -eq 0 && "$(cat "$RD/zero.out")" == 'gate-stdout' && "$(wc -c < "$RP/count" | tr -d ' ')" == 1 ]] \
  && grep -qF 'gate-stderr' "$RD/zero.err" && ok "报告 fast 输出透传且单次执行" || bad "报告 fast 输出或次数错误"
grep -qF "运行前提交：$RHEAD" "$RD/zero.md" && grep -qF '运行前工作区：clean' "$RD/zero.md" \
  && grep -qF '运行后工作区：dirty' "$RD/zero.md" && grep -qF '门退出码：0' "$RD/zero.md" \
  && grep -qF "项目目录：$(cd "$RP" && pwd -P)" "$RD/zero.md" && grep -qF 'QWB_GATE_FAST' "$RD/zero.md" \
  && grep -qF 'qwb-test-report-v1' "$RD/zero.md" && grep -qF '证明范围：仅证明' "$RD/zero.md" \
  && ok "成功报告绑定 HEAD、配置、前后状态与范围" || bad "成功报告内容错误"
cp "$RP/qwb.config.sh" "$RD/config.original"
printf 'QWB_GATE_FAST="printf other"\n' > "$RP/qwb.config.sh"
bash "$ROOT/bin/qwb-test.sh" fast --project "$RP" --report "$RD/other-command.md" > /dev/null 2> "$RD/other-command.err"; rc=$?
first_cmd_sha="$(sed -n 's/^- 命令 SHA-256：//p' "$RD/zero.md")"
other_cmd_sha="$(sed -n 's/^- 命令 SHA-256：//p' "$RD/other-command.md" 2>/dev/null)"
first_conf_sha="$(sed -n 's/^- 配置运行前 SHA-256：//p' "$RD/zero.md")"
other_conf_sha="$(sed -n 's/^- 配置运行前 SHA-256：//p' "$RD/other-command.md" 2>/dev/null)"
[[ "$rc" -eq 0 && -n "$first_cmd_sha" && -n "$other_cmd_sha" && "$first_cmd_sha" != "$other_cmd_sha" \
   && -n "$first_conf_sha" && -n "$other_conf_sha" && "$first_conf_sha" != "$other_conf_sha" ]] \
  && ok "同一 HEAD 的不同门命令有不同摘要且不泄露正文" || bad "报告未绑定实际命令和配置字节"
cp "$RD/config.original" "$RP/qwb.config.sh"
before="$(wc -c < "$RP/count" | tr -d ' ')"
bash "$ROOT/bin/qwb-test.sh" full --project "$RP" --report "$RD/seven.md" > "$RD/seven.out" 2> "$RD/seven.err"; rc=$?
after="$(wc -c < "$RP/count" | tr -d ' ')"
[[ "$rc" -eq 7 && "$after" -eq $((before+1)) && ! -s "$RD/seven.out" ]] \
  && grep -qF 'gate-seven' "$RD/seven.err" && grep -qF '门退出码：7' "$RD/seven.md" \
  && ok "失败门 7 保留 stderr、单次执行及报告" || bad "失败门 7 被报告掩盖或重跑"
[[ -f "$RD/zero.md" && -f "$RD/seven.md" ]] && ok "失败和成功报告分别保留" || bad "报告覆盖了历史结果"
for mode in existing symlink directory missing-parent missing-value duplicate; do
  target="$RD/rejected.md"
  case "$mode" in
    existing) printf preserved > "$target" ;;
    symlink) printf link-target > "$RD/link-target"; ln -s "$RD/link-target" "$target" ;;
    directory) mkdir "$target" ;;
    missing-parent) target="$RD/absent/rejected.md" ;;
    missing-value) target='' ;;
    duplicate) target="$RD/duplicate.md" ;;
  esac
  rm -f "$RP/count"
  if [[ "$mode" == duplicate ]]; then
    bash "$ROOT/bin/qwb-test.sh" fast --project "$RP" --report "$target" --report "$RD/other.md" > "$RD/reject.out" 2> "$RD/reject.err"; rc=$?
  else
    bash "$ROOT/bin/qwb-test.sh" fast --project "$RP" --report "$target" > "$RD/reject.out" 2> "$RD/reject.err"; rc=$?
  fi
  [[ "$rc" -eq 2 && ! -e "$RP/count" ]] && ok "报告 $mode 预检拒绝且门未执行" || bad "报告 $mode 预检错误（rc=$rc）"
  case "$mode" in
    existing) [[ "$(cat "$target")" == preserved ]] || bad "已有报告被改"; rm "$target" ;;
    symlink) [[ "$(cat "$RD/link-target")" == link-target ]] || bad "符号链接目标被改"; rm "$target" ;;
    directory) rmdir "$target" ;;
  esac
done
for token in --project --help -h --report; do
  rm -f "$RP/count"
  bash "$ROOT/bin/qwb-test.sh" fast --project "$RP" --report "$token" > "$RD/option.out" 2> "$RD/option.err"; rc=$?
  [[ "$rc" -eq 2 && ! -e "$RP/count" ]] && grep -qF -- '--report' "$RD/option.err" \
    && ok "--report 后跟 $token 返回 2 且门未执行" || bad "--report 后跟 $token 错误语义（rc=${rc}）"
done
mkdir "$RD/-relative-sub"
rm -f "$RP/count"
( cd "$RD" && bash "$ROOT/bin/qwb-test.sh" fast --project "$RP" --report -relative-sub/report.md ) > "$RD/dash-relative.out" 2> "$RD/dash-relative.err"; rc=$?
[[ "$rc" -eq 0 && -f "$RD/-relative-sub/report.md" && "$(cat "$RP/count")" == x ]] \
  && ok "合法前导横线相对路径可生成报告" || bad "合法前导横线相对路径失败（rc=${rc}）"
cat > "$RP/qwb.config.sh" <<'EOF'
QWB_GATE_FAST='printf x >> count; rmdir ../report-files/write-fail'
QWB_GATE_FULL='printf x >> count; rmdir ../report-files/write-fail; exit 7'
EOF
for gate in fast full; do
  mkdir "$RD/write-fail"; rm -f "$RP/count"
  bash "$ROOT/bin/qwb-test.sh" "$gate" --project "$RP" --report "$RD/write-fail/result.md" > "$RD/write-fail-$gate.out" 2> "$RD/write-fail-$gate.err"; rc=$?
  if [[ "$gate" == fast ]]; then expected=3; else expected=7; fi
  [[ "$rc" -eq "$expected" && "$(cat "$RP/count")" == x && ! -e "$RD/write-fail/result.md" ]] \
    && grep -qF '报告写入失败' "$RD/write-fail-$gate.err" \
    && ok "报告落盘失败时 $gate 保留单次门结果（rc=${rc}）" || bad "报告落盘失败语义错误（$gate rc=${rc}）"
done
mkdir "$RD/write-fail"
cat > "$RP/qwb.config.sh" <<'EOF'
QWB_GATE_FAST='printf x >> count; printf existing > ../report-files/write-fail/race.md'
EOF
rm -f "$RP/count"
bash "$ROOT/bin/qwb-test.sh" fast --project "$RP" --report "$RD/write-fail/race.md" > "$RD/race.out" 2> "$RD/race.err"; rc=$?
[[ "$rc" -eq 3 && "$(cat "$RD/write-fail/race.md")" == existing && "$(cat "$RP/count")" == x ]] \
  && ok "门期间新出现报告目标不被覆盖" || bad "门期间新目标被覆盖或返回码错误"
cat > "$RP/qwb.config.sh" <<'EOF'
QWB_GATE_FAST='printf "cmd-secret-canary\n"; printf x >> count; git -c user.name=Smoke -c user.email=smoke@example.invalid add qwb.config.sh && git -c user.name=Smoke -c user.email=smoke@example.invalid commit -qm gate-commit'
EOF
rm -f "$RP/count"
bash "$ROOT/bin/qwb-test.sh" fast --project "$RP" --report "$RD/change.md" > "$RD/change.out" 2> "$RD/change.err"; rc=$?
NEWHEAD="$(git -C "$RP" rev-parse HEAD)"
[[ "$rc" -eq 0 && "$NEWHEAD" != "$RHEAD" ]] && grep -qF "运行前提交：$RHEAD" "$RD/change.md" \
  && grep -qF "运行后提交：$NEWHEAD" "$RD/change.md" \
  && ! grep -Eq 'cmd-secret-canary|env-secret-canary|QWB_GATE_FAST=' "$RD/change.md" \
  && ok "版本变化如实记录且报告不复制 CMD/env/输出 canary" || bad "版本变化或秘密 canary 报告错误"
NG="$TMP/report-nongit"; mkdir "$NG"; printf 'QWB_GATE_FAST=":"\n' > "$NG/qwb.config.sh"
bash "$ROOT/bin/qwb-test.sh" fast --project "$NG" --report "$RD/nongit.md" > /dev/null 2> "$RD/nongit.err"; rc=$?
[[ "$rc" -eq 0 ]] && grep -qF '运行前提交：unknown' "$RD/nongit.md" \
  && grep -qF '运行后工作区：unknown' "$RD/nongit.md" \
  && ok "非 Git 项目仍执行门且版本 unknown" || bad "非 Git 报告错误"
printf 'QWB_GATE_FAST=":"\n' > "$RP/qwb.config.sh"
GSTUB="$TMP/report-git-fail"; mkdir "$GSTUB"; printf '#!/usr/bin/env bash\nexit 1\n' > "$GSTUB/git"; chmod +x "$GSTUB/git"
PATH="$GSTUB:$PATH" bash "$ROOT/bin/qwb-test.sh" fast --project "$RP" --report "$RD/git-fail.md" > /dev/null 2> "$RD/git-fail.err"; rc=$?
[[ "$rc" -eq 0 ]] && grep -qF '运行前提交：unknown' "$RD/git-fail.md" \
  && grep -qF '运行后工作区：unknown' "$RD/git-fail.md" \
  && ok "Git 查询失败不阻断门且如实 unknown" || bad "Git 查询失败报告错误"
ln -s "$RP" "$TMP/report-project-link"
bash "$ROOT/bin/qwb-test.sh" fast --project "$TMP/report-project-link" --report "$RD/symlink-project.md" > /dev/null 2> "$RD/symlink-project.err"; rc=$?
[[ "$rc" -eq 0 ]] && grep -qF "项目目录：$(cd "$RP" && pwd -P)" "$RD/symlink-project.md" \
  && ok "项目 symlink 入口报告物理规范目录" || bad "项目 symlink 报告目录不规范"
LP="$TMP/legacy-physical"; LA="$TMP/legacy-alias"; mkdir "$LP"; ln -s "$LP" "$LA"
printf "QWB_GATE_FAST='pwd'\n" > "$LP/qwb.config.sh"
bash "$ROOT/bin/qwb-test.sh" fast --project "$LA" > "$RD/legacy-alias.out" 2> "$RD/legacy-alias.err"; rc=$?
[[ "$rc" -eq 0 && "$(cat "$RD/legacy-alias.out")" == "$LA" && ! -s "$RD/legacy-alias.err" ]] \
  && ok "旧 symlink 项目入口保留逻辑 PWD/stdout" || bad "旧 symlink 项目入口改变 PWD/stdout"
bash "$ROOT/bin/qwb-test.sh" fast --project "$LA" --report "$RD/alias-report.md" > "$RD/alias-report.out" 2> "$RD/alias-report.err"; rc=$?
[[ "$rc" -eq 0 && "$(cat "$RD/alias-report.out")" == "$LA" ]] \
  && grep -qF "项目目录：$(cd "$LA" && pwd -P)" "$RD/alias-report.md" \
  && ok "带报告仍保留门逻辑 PWD 且字段记录物理目录" || bad "带报告 symlink PWD/报告字段错误"
( cd "$TMP" && bash "$ROOT/bin/qwb-test.sh" fast --project "$RP" --report report-files/relative.md ) > "$RD/relative.out" 2> "$RD/relative.err"; rc=$?
[[ "$rc" -eq 0 && -f "$RD/relative.md" ]] && ok "相对报告路径按调用 cwd 解析" || bad "相对报告路径解析错误"
ND="$RD/no-write"; mkdir "$ND"; chmod 500 "$ND"
rm -f "$RP/count"
bash "$ROOT/bin/qwb-test.sh" fast --project "$RP" --report "$ND/result.md" > /dev/null 2> "$RD/no-write.err"; rc=$?
[[ "$rc" -eq 2 && ! -e "$RP/count" && ! -e "$ND/result.md" ]] \
  && ok "父目录不可写预检返回 2 且门未执行" || bad "父目录不可写预检错误（rc=${rc}）"
chmod 700 "$ND"
# date 第二次调用失败：门已经返回 7，报告元信息失败不得改成其他退出码。
DSTUB="$TMP/report-date-fail"; mkdir "$DSTUB"
cat > "$DSTUB/date" <<'EOF'
#!/usr/bin/env bash
count="$(cat "$QWB_DATE_COUNT" 2>/dev/null || echo 0)"
count=$((count+1)); printf '%s' "$count" > "$QWB_DATE_COUNT"
if [[ "$count" -eq 2 ]]; then exit 1; fi
exec /bin/date "$@"
EOF
chmod +x "$DSTUB/date"
printf 'QWB_GATE_FULL="exit 7"\n' >> "$RP/qwb.config.sh"
QWB_DATE_COUNT="$TMP/report-date.count" PATH="$DSTUB:$PATH" bash "$ROOT/bin/qwb-test.sh" full --project "$RP" --report "$RD/date-fail.md" > /dev/null 2> "$RD/date-fail.err"; rc=$?
[[ "$rc" -eq 7 && ! -e "$RD/date-fail.md" ]] && grep -qF '报告写入失败' "$RD/date-fail.err" \
  && ok "门 7 后元信息失败仍返回 7 且无完整报告" || bad "门 7 后元信息失败覆盖了退出码"
CP="$TMP/report-clean-project"; mkdir "$CP"
printf 'QWB_GATE_FAST=":"\n' > "$CP/qwb.config.sh"
git -C "$CP" init -q; git -C "$CP" add qwb.config.sh
git -C "$CP" -c user.name=Smoke -c user.email=smoke@example.invalid commit -qm seed
bash "$ROOT/bin/qwb-test.sh" fast --project "$CP" --report "$CP/report.md" > /dev/null 2> "$RD/in-project.err"; rc=$?
[[ "$rc" -eq 0 ]] && grep -qF '运行前工作区：clean' "$CP/report.md" \
  && grep -qF '运行后工作区：clean' "$CP/report.md" \
  && ok "项目内报告与临时文件不污染前后工作区采样" || bad "项目内报告污染采样"

echo "== 24. B：先场景后代码（模板 + 规范）=="
assert_file "$ROOT/templates/TASK.md"
assert_file "$TMP/qwbuddy/TASK.md"
for kw in '验收场景' 'Given' 'When' 'Then' '失败路径' '验收门'; do
  grep -q "$kw" "$ROOT/templates/TASK.md" && ok "TASK.md 含「${kw}」" || bad "TASK.md 缺「${kw}」"
done
grep -q '先场景后代码' "$TMP/qwbuddy/QWBUDDY.md" && ok "QWBUDDY.md 有先场景后代码规范" || bad "QWBUDDY.md 缺规范节"
grep -q '场景冻结' "$TMP/qwbuddy/QWBUDDY.md" && ok "QWBUDDY.md 有场景冻结条款" || bad "缺场景冻结"
grep -q 'QWB_GATE_FAST' "$TMP/qwbuddy/config.sh" && grep -q 'QWB_GATE_FULL' "$TMP/qwbuddy/config.sh" \
  && ok "安装的 config.sh 含快门/全门声明" || bad "config.sh 缺门声明"
grep -q '自证' "$TMP/qwbuddy/roles/执行者.md" && grep -q '契约校验' "$TMP/qwbuddy/roles/执行者.md" \
  && ok "执行者.md 新增两条禁止事项" || bad "执行者.md 缺新禁止事项"

echo "== 25. C：qwb-lint.sh 自身 lint =="
lintout="$(bash "$ROOT/bin/qwb-lint.sh" --project "$ROOT" 2>&1)"; rc=$?
[[ "$rc" -eq 0 ]] && printf '%s' "$lintout" | grep -q 'LINT PASS' \
  && ok "母本仓 lint 全过（LINT PASS）" || { bad "母本仓 lint FAIL（rc=${rc}）:"; printf '%s\n' "$lintout"; }
printf '%s' "$lintout" | grep -c '^PASS' | grep -qE '^[4-9]' \
  && ok "lint 逐项 PASS 输出可见" || bad "lint 无逐项 PASS 输出"
HL="$TMP/healthy"; mkdir -p "$HL"; bash "$ROOT/bin/qwb-init.sh" "$HL" >/dev/null
printf 'QWB_GATE_FAST="true"\nQWB_GATE_FULL="true"\n' >> "$HL/qwbuddy/config.sh"
bash "$ROOT/bin/qwb-lint.sh" --project "$HL" >/dev/null 2>&1 \
  && ok "健康安装项目 lint 退出 0" || bad "健康项目 lint 非 0"
# 坏项目：四条检查各踩一条
BD="$TMP/badproj"; mkdir -p "$BD/qwbuddy/bin" "$BD/tasks"
printf '# doc\nqwb-ghost.sh 必须在\n' > "$BD/qwbuddy/QWBUDDY.md"
printf '# t\nstate: pending\n' > "$BD/tasks/2099-01-30-bad.md"
printf 'QWB_DEAD_KEY=1\n' > "$BD/qwbuddy/config.sh"
printf '%s\n' '#!/usr/bin/env bash' 'echo $X你好' > "$BD/qwbuddy/bin/qwb-foo.sh"
lintout="$(bash "$ROOT/bin/qwb-lint.sh" --project "$BD" 2>&1)"; rc=$?
[[ "$rc" -eq 1 ]] && ok "坏项目 lint 退出 1" || bad "坏项目 lint 未失败（rc=${rc}）"
printf '%s' "$lintout" | grep -q 'qwb-ghost.sh' && ok "检出文档承诺缺失脚本" || bad "未检出缺失脚本"
printf '%s' "$lintout" | grep -q 'pending' && ok "检出非法 state" || bad "未检出非法 state"
printf '%s' "$lintout" | grep -q 'QWB_DEAD_KEY' && ok "检出血配置死键" || bad "未检出死键"
printf '%s' "$lintout" | grep -q 'qwb-foo.sh' && ok "检出 \$VAR+非ASCII 写法" || bad "未检出变量写法"

echo "== 26. D：herdr fixture 契约基线（真实 JSON 路径检查）=="
for fx in tab-create agent-start agent-prompt agent-wait agent-wait-timeout agent-list pane-run pane-run-error \
          worktree-open worktree-open-already worktree-open-error \
          pane-get-shell pane-get-error proc-shell proc-wake proc-busy pane-list workspace-list; do
  assert_file "$FIXDIR/$fx.json"
done
for fx in pane-read-trust pane-read-shell; do assert_file "$FIXDIR/$fx.txt"; done

# 真正的 JSON 路径检查：fixture 剔 # 注释行后按点分路径解析，路径须存在、非空且类型匹配（R2-M2）
# 类型约定：string=必须是 JSON 字符串（encode_json 回带引号；对象/数组/数字/布尔/null/空串全拒）；
#           array/object=非空对应容器；any（缺省）=存在且非空
jpath() { # $1=fixture 文件  $2=点分路径  $3=期望类型 → 0=满足契约
  perl -MJSON::PP=decode_json,encode_json -e '
    my ($f, $p, $t) = @ARGV;
    open my $fh, "<", $f or exit 2;
    my $raw = do { local $/; <$fh> }; close $fh;
    $raw =~ s/^#.*\n//mg;
    my $cur = eval { decode_json($raw) } or exit 2;
    for my $k (split /\./, $p) {
      exit 1 unless ref $cur eq "HASH" && exists $cur->{$k};
      $cur = $cur->{$k};
    }
    exit 1 if !defined $cur;
    if ($t eq "string") {
      exit 1 if ref $cur || $cur eq "" || encode_json($cur) !~ /^"/;
    } elsif ($t eq "array") {
      exit 1 if ref $cur ne "ARRAY" || !@$cur;
    } elsif ($t eq "object") {
      exit 1 if ref $cur ne "HASH" || !%$cur;
    } else {
      exit 1 if (!ref $cur && $cur eq "")
        || (ref $cur eq "HASH"  && !%$cur)
        || (ref $cur eq "ARRAY" && !@$cur);
    }
    exit 0;
  ' "$1" "$2" "${3:-any}"
}
# 每个 fixture 必须满足的契约清单：路径:类型（存在、非空、类型相符才算过）
fx_paths() {
  case "$1" in
    tab-create.json)         printf 'result.root_pane.pane_id:string result.tab.tab_id:string' ;;
    agent-start.json)        printf 'result.type:string result.agent.pane_id:string' ;;
    agent-prompt.json)       printf 'result.type:string result.agent.pane_id:string' ;;
    agent-wait.json)         printf 'result.type:string result.agent.pane_id:string' ;;
    agent-wait-timeout.json) printf 'error.code:string' ;;
    agent-list.json)         printf 'result.type:string result.agents:array' ;;
    pane-run-error.json)     printf 'error.code:string' ;;
    pane-get-shell.json)     printf 'result.pane.pane_id:string result.pane.cwd:string' ;;
    pane-get-error.json)     printf 'error.code:string' ;;
    pane-list.json)          printf 'result.panes:array' ;;
    workspace-list.json)     printf 'result.type:string result.workspaces:array' ;;
    worktree-open.json|worktree-open-already.json)
                             printf 'result.workspace.workspace_id:string result.workspace.worktree.checkout_path:string result.root_pane.tab_id:string' ;;
    worktree-open-error.json) printf 'error.code:string' ;;
    proc-shell.json)         printf 'result.process_info.foreground_processes:array result.process_info.shell_pid:any' ;;
    proc-wake.json)          printf 'result.process_info.foreground_processes:array result.process_info.shell_pid:any' ;;
    proc-busy.json)          printf 'result.process_info.foreground_processes:array result.process_info.shell_pid:any' ;;
    *)                       printf '' ;;
  esac
}
for fx in tab-create agent-start agent-prompt agent-wait agent-wait-timeout agent-list pane-run-error \
          worktree-open worktree-open-already worktree-open-error \
          pane-get-shell pane-get-error pane-list proc-shell proc-wake proc-busy workspace-list; do
  for pt in $(fx_paths "$fx.json"); do
    p="${pt%%:*}"; t="${pt##*:}"
    jpath "$FIXDIR/$fx.json" "$p" "$t" \
      && ok "$fx fixture 含契约路径 .${p}（${t}，非空）" || bad "$fx fixture 缺契约路径 .${p}（或为空/错型）"
  done
done
[[ -z "$(sed '/^#/d' "$FIXDIR/pane-run.json")" ]] \
  && ok "pane-run fixture 契约=空输出（与真录一致）" || bad "pane-run fixture 非空，与真录契约不符"
# 负例：错误层级 fixture（审核同款：result 与 root_pane 平级、pane_id 在顶层）必须被拒
BADFX="$TMP/bad-tab-create.json"
printf '%s\n' '{"result":{},"root_pane":{},"pane_id":"fake:p1"}' > "$BADFX"
jpath "$BADFX" result.root_pane.pane_id \
  && bad "错误层级 fixture 竟通过契约检查（假绿）" || ok "错误层级 fixture 被契约检查拒绝"
jpath "$BADFX" result \
  && bad "空对象 result 竟算非空" || ok "空对象 result 被判不满足契约"
# R2-M2 负例：pane_id 错型（对象/数组/数字/布尔）必须各被契约拒绝——存在且非空不算过
for badval in '{"wrong":1}' '["audit:p1"]' '17' 'false'; do
  printf '{"result":{"root_pane":{"pane_id":%s},"tab":{"tab_id":"t1"}}}\n' "$badval" > "$BADFX"
  jpath "$BADFX" result.root_pane.pane_id string \
    && bad "pane_id=${badval} 错型竟过契约检查" || ok "pane_id=${badval} 错型被契约拒绝"
done
# 行为证明：stub 确实读 fixture——换掉 fixture 内容，派发结果跟着变
FIXDIR2="$TMP/fix2"; mkdir -p "$FIXDIR2"; cp "$FIXDIR"/*.json "$FIXDIR2/"
sed 's/"pane_id":"[^"]*"/"pane_id":"contract:p99"/' "$FIXDIR/tab-create.json" > "$FIXDIR2/tab-create.json"
DISP2="$TMP/tasks/2099-01-22-disp2.md"
cat > "$DISP2" <<'EOF'
# d2
state: blocked

## 1. 验收场景

### user_正常
Given 任务写好
When  派发
Then  pane 写进账本
### user_失败
Given fixture 错形
When  派发
Then  报错退出
EOF
( cd "$TMP" && PATH="$STUB:$PATH" HERDR_PANE_ID=wtest:ctl HERDR_FIXDIR="$FIXDIR2" bash qwbuddy/bin/qwb-run.sh --task disp2 --worker codex --here ) >/dev/null 2>&1
grep -qF 'pane=contract:p99' "$DISP2" \
  && ok "改 fixture 后派发 pane 跟着变（stub 真读 fixture，非硬编码）" || bad "stub 未读 fixture（pane 未变）"

echo "== 27. F1 回归：工人无新账本行时的时间兜底重叫 =="
# 场景：任务已叫醒过一次，此后工人挂起/崩溃不再追加任何行（指纹永不变）
RWF="$TMP/tasks/2099-01-23-rewake.md"
printf '# rw\nstate: running\nworking: 工人在干活\n' > "$RWF"
( cd "$TMP" && PATH="$STUB:$PATH" bash qwbuddy/bin/qwb-wake.sh --once --pane wtest:p9 ) >/dev/null
[[ "$(grep -c '^wake:' "$RWF")" == "1" ]] && ok "首轮叫醒写下 wake 行" || bad "首轮未写 wake 行"
# 指纹未变 + 默认 QWB_REWAKE_MS=1800000 未超期 → 不叫
out="$( cd "$TMP" && bash qwbuddy/bin/qwb-wake.sh --dry-run --once )"
printf '%s' "$out" | grep -q '未结项（将叫醒）: 2099-01-23-rewake' \
  && bad "未超期却将再叫（兜底误触发）" || ok "指纹未变且未超期→不再叫"
# 负例：把 wake 时间戳改到 2000 年 → 已超期 → 无任何新账本行也必须再叫（修复前永远跳过）
sed -i '' 's/^wake: [^[:space:]]*/wake: 2000-01-01T00:00:00Z/' "$RWF"
out="$( cd "$TMP" && bash qwbuddy/bin/qwb-wake.sh --dry-run --once )"
printf '%s' "$out" | grep -q '未结项（将叫醒）: 2099-01-23-rewake' \
  && ok "无新行但 wake 已超期→兜底再叫" || bad "无新行且已超期仍跳过（F1 未修）"
[[ "$(grep -c '^wake:' "$RWF")" == "1" ]] \
  && ok "dry-run 判定将叫醒但不写 wake 行" || bad "dry-run 写了 wake 行"
( cd "$TMP" && PATH="$STUB:$PATH" bash qwbuddy/bin/qwb-wake.sh --once --pane wtest:p9 ) >/dev/null
[[ "$(grep -c '^wake:' "$RWF")" == "2" ]] \
  && ok "超期后真叫并追加第二条 wake 行" || bad "超期后未追加 wake 行"
# 负例：wake 时间戳解析失败 → 保守按超期处理（宁可多叫）
rwfp="$(grep '^wake:' "$RWF" | tail -1 | sed -n 's/.*\(fp=[^[:space:]]*\).*/\1/p')"
printf 'wake: GARBAGE state=running %s\n' "$rwfp" >> "$RWF"
out="$( cd "$TMP" && bash qwbuddy/bin/qwb-wake.sh --dry-run --once )"
printf '%s' "$out" | grep -q '未结项（将叫醒）: 2099-01-23-rewake' \
  && ok "wake 时间戳解析失败→按超期叫醒" || bad "坏时间戳被当成未超期跳过"
# 负例：QWB_REWAKE_MS=0 → 关闭兜底，超期/坏时间戳都不再叫
printf 'QWB_REWAKE_MS=0\n' >> "$TMP/qwbuddy/config.sh"
out="$( cd "$TMP" && bash qwbuddy/bin/qwb-wake.sh --dry-run --once )"
printf '%s' "$out" | grep -q '未结项（将叫醒）: 2099-01-23-rewake' \
  && bad "QWB_REWAKE_MS=0 仍兜底再叫" || ok "QWB_REWAKE_MS=0 关闭兜底重叫"

echo "== 28. F2 回归：派发记账不得丢工人并发追加 =="
# 审核复现手法：awk 函数替身在「改 state 的瞬间」注入一条工人追加；herdr 替身在 agent start 时再注入一条
F2T="$TMP/tasks/2099-01-24-f2race.md"
cat > "$F2T" <<'EOF'
# f2race
state: blocked

## 1. 验收场景

### user_正常
Given 任务写好
When  派发
Then  记账成功
### user_失败
Given 并发追加被覆盖
When  派发
Then  报错不留假绿
EOF
F2N="$TMP/f2awk.count"; echo 0 > "$F2N"
F2STUB="$TMP/f2stub"; mkdir -p "$F2STUB"
cat > "$F2STUB/herdr" <<EOF
#!/usr/bin/env bash
fix() { sed '/^#/d' "$FIXDIR/\$1"; }
case "\${1:-} \${2:-}" in
  "tab create")   fix tab-create.json ;;
  "workspace list") fix workspace-list.json ;;
  "agent get")    fix agent-get-error.json >&2; exit 1 ;;   # 无同名工人：本节只走新开 tab 路径
  "agent start")  printf 'done: worker-appended-at-start\n' >> "$F2T"; fix agent-start.json ;;
  "agent prompt") fix agent-prompt.json ;;
  *)              fix pane-run.json ;;
esac
exit 0
EOF
# R2-M4：替身每次 awk 调用注入**唯一**标记（带序号）并记次数——
# 同名标记会被「场景提取先行调用」提前留下的旧标记蒙混，必须逐条核对
cat > "$F2STUB/awk" <<EOF
#!/usr/bin/env bash
n=\$(( \$(cat "$F2N") + 1 ))
echo "\$n" > "$F2N"
/usr/bin/awk "\$@"
printf 'done: awk-injected-%s\n' "\$n" >> "$F2T"
EOF
chmod +x "$F2STUB/herdr" "$F2STUB/awk"
rm -rf "$TMP/qwbuddy/.controller.lock"   # 前面段落的派发已持锁；本节统一用固定 pane id 当主控
( cd "$TMP" && PATH="$F2STUB:$STUB:$PATH" HERDR_PANE_ID=wtest:ctl bash qwbuddy/bin/qwb-run.sh --task f2race --worker codex --here ) >/dev/null \
  && ok "带并发注入的派发退出 0" || bad "带并发注入的派发非 0"
# 负例：注入次数 == 任务书里对应标记行数，且每条唯一标记都在——任何丢行/重复都会被抓（R2-M4）；
# 实现不再调 awk 时注入点不存在，由下面 agent-start 注入断言兜底
inj="$(cat "$F2N")"
if [[ "$inj" -gt 0 ]]; then
  miss=0
  for ((i=1; i<=inj; i++)); do
    grep -qxF "done: awk-injected-${i}" "$F2T" || miss=$((miss+1))
  done
  found="$(grep -cF 'done: awk-injected-' "$F2T" || true)"
  [[ "$miss" -eq 0 && "$found" -eq "$inj" ]] \
    && ok "awk 注入 ${inj} 次，任务书保留全部 ${inj} 条唯一标记" \
    || bad "awk 注入 ${inj} 次但任务书只剩 ${found} 条唯一标记（丢 ${miss} 条，F2 未修）"
else
  ok "派发全程未调 awk 处理任务书（快照覆盖注入点已消除）"
fi
# 负例：agent start 瞬间（工人已能合法追加）的追加行必须还在文件里
grep -q 'worker-appended-at-start' "$F2T" \
  && ok "agent start 时工人追加的行存活" || bad "agent start 时的追加被覆盖（F2 未修）"
grep -q '^state: running' "$F2T" && ok "并发下 state 仍正确改写" || bad "state 未改写为 running"

echo "== 29. M4 负例：tests/smoke.sh 语法错误必须被快门抓住 =="
BADT="$TMP/badgate"; mkdir -p "$BADT/bin" "$BADT/tests"
cp "$ROOT"/bin/qwb-*.sh "$BADT/bin/"
printf 'if then\n' > "$BADT/tests/smoke.sh"
cp "$ROOT/qwb.config.sh" "$BADT/qwb.config.sh"
if bash "$ROOT/bin/qwb-test.sh" fast --project "$BADT" >/dev/null 2>&1; then
  bad "smoke.sh 语法错误仍过快门（M4 未修）"
else
  ok "smoke.sh 语法错误 → fast 门非 0"
fi
# 对照：同一布局换成语法正确的 smoke，门应恢复——证明上面失败归因于语法而非环境
printf '#!/usr/bin/env bash\ntrue\n' > "$BADT/tests/smoke.sh"
bash "$ROOT/bin/qwb-test.sh" fast --project "$BADT" >/dev/null 2>&1 \
  && ok "语法修复后 fast 门恢复 0（对照）" || bad "语法正确仍失败——门本身有问题"

echo "== 30. M3 负例：lint 三处漏检 =="
# 30a：任务书有 state: 字段但值为空 → lint 必须 FAIL（修复前被跳过）
ES="$TMP/esproj"; mkdir -p "$ES"; bash "$ROOT/bin/qwb-init.sh" "$ES" >/dev/null
printf 'QWB_GATE_FAST="true"\nQWB_GATE_FULL="true"\n' >> "$ES/qwbuddy/config.sh"
printf '# t\nstate: \n' > "$ES/tasks/2099-01-26-emptystate.md"
lintout="$(bash "$ROOT/bin/qwb-lint.sh" --project "$ES" 2>&1)"; rc=$?
{ [[ "$rc" -eq 1 ]] && printf '%s' "$lintout" | grep -q '空值'; } \
  && ok "空 state 值 → lint FAIL" || bad "空 state 值 lint 未检出（rc=${rc}）"
# 对照：无 state 字段的纯文档不算任务书 → 不因它 FAIL
rm "$ES/tasks/2099-01-26-emptystate.md"; printf '# lessons\n' > "$ES/tasks/lessons.md"
bash "$ROOT/bin/qwb-lint.sh" --project "$ES" >/dev/null 2>&1 \
  && ok "无 state 字段的文档不误报" || bad "无 state 字段文档被误报"
# 30b：export 形式声明的死键 + 只在纯注释里被「引用」的键 → 都算死键
EK="$TMP/ekproj"; mkdir -p "$EK"; bash "$ROOT/bin/qwb-init.sh" "$EK" >/dev/null
printf 'QWB_GATE_FAST="true"\nQWB_GATE_FULL="true"\nexport QWB_UNUSED_KEY=1\nQWB_COMMENT_ONLY=1\n' >> "$EK/qwbuddy/config.sh"
printf '%s\n' '#!/usr/bin/env bash' '# 只在注释里提到 QWB_COMMENT_ONLY，不算读取' > "$EK/qwbuddy/bin/qwb-note.sh"
lintout="$(bash "$ROOT/bin/qwb-lint.sh" --project "$EK" 2>&1)"; rc=$?
{ [[ "$rc" -eq 1 ]] && printf '%s' "$lintout" | grep -q 'QWB_UNUSED_KEY'; } \
  && ok "export 形式死键 → lint FAIL" || bad "export 形式死键未检出（rc=${rc}）"
printf '%s' "$lintout" | grep -q 'QWB_COMMENT_ONLY' \
  && ok "仅注释引用仍算死键" || bad "仅注释引用被当成已读取"
# 30c：非 qwb- 前缀脚本里的 $VAR+非ASCII 写法 → FAIL（修复前只扫 qwb-*.sh）
HX="$TMP/hxproj"; mkdir -p "$HX"; bash "$ROOT/bin/qwb-init.sh" "$HX" >/dev/null
printf 'QWB_GATE_FAST="true"\nQWB_GATE_FULL="true"\n' >> "$HX/qwbuddy/config.sh"
printf '%s\n' '#!/usr/bin/env bash' 'echo "$X你好"' > "$HX/qwbuddy/bin/helper.sh"
lintout="$(bash "$ROOT/bin/qwb-lint.sh" --project "$HX" 2>&1)"; rc=$?
{ [[ "$rc" -eq 1 ]] && printf '%s' "$lintout" | grep -q 'helper.sh'; } \
  && ok "非 qwb- 脚本的 \$VAR+非ASCII → lint FAIL" || bad "helper.sh 非ASCII 写法未检出（rc=${rc}）"

echo "== 31. M1：验收场景门（派发前必须有场景 + 失败路径 + 冻结指纹）=="
# 31a 负例：无场景块的任务书 → 派发必须被拒且提示补场景
NSF="$TMP/tasks/2099-01-31-noscen.md"; printf '# ns\nstate: running\n' > "$NSF"
nout="$( cd "$TMP" && PATH="$STUB:$PATH" HERDR_PANE_ID=wtest:ctl bash qwbuddy/bin/qwb-run.sh --task noscen --worker codex --here 2>&1 )"; nrc=$?
{ [[ "$nrc" -ne 0 ]] && printf '%s' "$nout" | grep -q '补验收场景'; } \
  && ok "无场景任务书派发被拒（rc=${nrc}）" || bad "无场景任务书竟派发成功（M1 未修，rc=${nrc}）"
grep -q '^dispatch:' "$NSF" && bad "被拒任务书仍写了 dispatch 行" || ok "被拒任务书无 dispatch 行"
# 31b 负例：只有 happy path（无失败路径标记）→ 同样拒绝
HPF="$TMP/tasks/2099-01-31-happyonly.md"
cat > "$HPF" <<'EOF'
# happy
state: running

## 1. 验收场景

### user_正常一
Given 前置
When  动作
Then  成功
### user_正常二
Given 前置二
When  动作二
Then  也成功
EOF
nout="$( cd "$TMP" && PATH="$STUB:$PATH" HERDR_PANE_ID=wtest:ctl bash qwbuddy/bin/qwb-run.sh --task happyonly --worker codex --here 2>&1 )"; nrc=$?
{ [[ "$nrc" -ne 0 ]] && printf '%s' "$nout" | grep -q '失败路径'; } \
  && ok "无失败路径场景的任务书被拒（rc=${nrc}）" || bad "只有 happy path 竟派发成功（rc=${nrc}）"
# 31c 正例 + 冻结指纹：装好且门已声明的独立项目里派发 → scenarios-fp 写入
MP="$TMP/mproj"; mkdir -p "$MP"; bash "$ROOT/bin/qwb-init.sh" "$MP" >/dev/null
printf 'QWB_GATE_FAST="true"\nQWB_GATE_FULL="true"\n' >> "$MP/qwbuddy/config.sh"
MPT="$MP/tasks/2099-01-32-mscen.md"
cat > "$MPT" <<'EOF'
# mscen
state: running

## 1. 验收场景

### user_正常
Given 前置
When  动作
Then  成功
### user_失败路径
Given 非法输入
When  动作
Then  拒绝执行
EOF
( cd "$MP" && PATH="$STUB:$PATH" HERDR_PANE_ID=wtest:mp bash "$MP/qwbuddy/bin/qwb-run.sh" --task mscen --worker codex --here ) >/dev/null \
  && ok "含失败路径场景的任务书派发成功" || bad "合法任务书派发被拒"
mpfp="$(sed -n 's/^scenarios-fp:[[:space:]]*//p' "$MPT" | head -1)"
[[ -n "$mpfp" ]] && ok "派发写入 scenarios-fp=${mpfp:0:8}…" || bad "未写 scenarios-fp"
# 对照：未改动时 lint 冻结检查过
lintout="$(bash "$ROOT/bin/qwb-lint.sh" --project "$MP" 2>&1)"; rc=$?
[[ "$rc" -eq 0 ]] && ok "派发后未改场景 → lint 过（对照）" || { bad "未改场景 lint 竟 FAIL（rc=${rc}）:"; printf '%s\n' "$lintout"; }
# 31d 负例：派发后改场景块 → lint 必须 FAIL
sed -i '' 's/拒绝执行/放行执行/' "$MPT"
lintout="$(bash "$ROOT/bin/qwb-lint.sh" --project "$MP" 2>&1)"; rc=$?
{ [[ "$rc" -eq 1 ]] && printf '%s' "$lintout" | grep -q '派发后被改动'; } \
  && ok "派发后改场景块 → lint FAIL（冻结生效）" || bad "派发后改场景 lint 未检出（M1 未修，rc=${rc}）"

echo "== 32. M6：默认派发进隔离副本（不给参数 ≠ 落项目根）=="
rm -rf "$GP/qwbuddy/.controller.lock"   # wtnew 的派发持过锁；本节统一固定 pane id
M6T="$GP/tasks/2099-01-33-m6def.md"
cat > "$M6T" <<'EOF'
# m6def
state: running

## 1. 验收场景

### user_正常
Given git 项目
When  默认派发
Then  开隔离副本
### user_失败
Given 非 git 项目
When  默认派发
Then  报错提示 --here
EOF
( cd "$GP" && PATH="$STUB:$PATH" HERDR_PANE_ID=wtest:gp bash "$TMP/qwbuddy/bin/qwb-run.sh" --task m6def --worker codex ) >/dev/null \
  && ok "不带 worktree 参数的派发退出 0" || bad "默认派发非 0"
[[ -d "$GP/.worktrees/m6def" ]] \
  && ok "默认派发创建了 .worktrees/m6def 隔离副本" || bad "默认派发未建隔离副本（M6 未修）"
ddir="$(grep '^dispatch:' "$M6T" | tail -1 | sed -n 's/.*dir=\([^[:space:]]*\).*/\1/p')"
[[ -n "$ddir" && -d "$GP/.worktrees/m6def" && "$ddir" == "$(cd "$GP/.worktrees/m6def" && pwd)" ]] \
  && ok "dispatch 行 dir= 指向隔离副本" || bad "dir= 未指向隔离副本（${ddir}）"
[[ -n "$ddir" && -d "$GP/.worktrees/m6def" && "$ddir" != "$(cd "$GP" && pwd)" ]] \
  && ok "dir= 绝不是项目根" || bad "dir= 仍是项目根（M6 未修）"
# --worktree 复用既有副本仍可用
M6W="$GP/tasks/2099-01-33-m6reuse.md"
sed 's/m6def/m6reuse/' "$M6T" > "$M6W"
( cd "$GP" && PATH="$STUB:$PATH" HERDR_PANE_ID=wtest:gp bash "$TMP/qwbuddy/bin/qwb-run.sh" --task m6reuse --worker codex --worktree "$GP/.worktrees/m6def" ) >/dev/null \
  && ok "--worktree 复用既有副本仍可派发" || bad "--worktree 派发被拒"
ddir="$(grep '^dispatch:' "$M6W" | tail -1 | sed -n 's/.*dir=\([^[:space:]]*\).*/\1/p')"
[[ -n "$ddir" && -d "$GP/.worktrees/m6def" && "$ddir" == "$(cd "$GP/.worktrees/m6def" && pwd)" ]] \
  && ok "--worktree dir= 所给副本" || bad "--worktree dir 不对（${ddir}）"
# 负例：--here 与 --worktree 同给 → 互斥拒绝
if ( cd "$GP" && PATH="$STUB:$PATH" HERDR_PANE_ID=wtest:gp bash "$TMP/qwbuddy/bin/qwb-run.sh" --task m6reuse --worker codex --here --worktree "$GP" ) >/dev/null 2>&1; then
  bad "--here 与 --worktree 同给竟放行"
else
  ok "--here 与 --worktree 互斥拒绝"
fi

echo "== 33. M5：整装默认门与入口 =="
MI="$TMP/minst"; mkdir -p "$MI"; bash "$ROOT/bin/qwb-init.sh" "$MI" >/dev/null
# 负例：新装项目门未声明 → qwb-test.sh fast 非 0（不是 127、不是 0）且打印声明提示
mout="$(bash "$MI/qwbuddy/bin/qwb-test.sh" fast --project "$MI" 2>&1)"; mrc=$?
{ [[ "$mrc" -ne 0 && "$mrc" -ne 127 ]] && printf '%s' "$mout" | grep -q '尚未声明质量门'; } \
  && ok "新装项目 fast 门：rc=${mrc} 且提示尚未声明质量门" || bad "新装项目 fast 门行为不对（rc=${mrc}）"
mout="$(bash "$MI/qwbuddy/bin/qwb-test.sh" full --project "$MI" 2>&1)"; mrc=$?
{ [[ "$mrc" -ne 0 && "$mrc" -ne 127 ]] && printf '%s' "$mout" | grep -q '尚未声明质量门'; } \
  && ok "新装项目 full 门：rc=${mrc} 且提示尚未声明质量门" || bad "新装项目 full 门行为不对（rc=${mrc}）"
# 负例：门未声明的项目跑 lint → FAIL（提醒配门，不许静默当绿）
lintout="$(bash "$ROOT/bin/qwb-lint.sh" --project "$MI" 2>&1)"; rc=$?
{ [[ "$rc" -eq 1 ]] && printf '%s' "$lintout" | grep -q '质量门未声明'; } \
  && ok "门未声明 → lint FAIL" || bad "门未声明 lint 竟 PASS（rc=${rc}）"
# 声明后恢复 → lint 过（对照）
printf 'QWB_GATE_FAST="true"\nQWB_GATE_FULL="true"\n' >> "$MI/qwbuddy/config.sh"
bash "$ROOT/bin/qwb-lint.sh" --project "$MI" >/dev/null 2>&1 \
  && ok "补声明门后 lint 恢复 0（对照）" || bad "补声明后 lint 仍 FAIL"
# 负例：历史残留的安装副本被执行 → 清晰提示母本仓，不得假装修装
cp "$ROOT/bin/qwb-init.sh" "$MI/qwbuddy/bin/qwb-init.sh"
mout="$(bash "$MI/qwbuddy/bin/qwb-init.sh" "$MI" 2>&1)"; mrc=$?
{ [[ "$mrc" -ne 0 ]] && printf '%s' "$mout" | grep -q '母本仓'; } \
  && ok "安装副本里的 qwb-init.sh 被执行 → 拒绝并提示母本仓" || bad "安装副本 init 行为不对（rc=${mrc}）"

echo "== 34. R2-M2：坏 fixture 必须喂给真实运行路径（不只测测试内 jpath）=="
FIXDIR3="$TMP/fix3"; mkdir -p "$FIXDIR3"; cp "$FIXDIR"/*.json "$FIXDIR3/"
# 错误层级：result 与 root_pane 平级、pane_id 在顶层（审核 R3 反转变体的同款输入）
printf '%s\n' '{"result":{},"root_pane":{},"pane_id":"audit:p1"}' > "$FIXDIR3/tab-create.json"
DISP3="$TMP/tasks/2099-01-40-disp3.md"
cat > "$DISP3" <<'EOF'
# d3
state: blocked

## 1. 验收场景

### user_正常
Given 任务写好
When  派发
Then  pane 写进账本
### user_失败
Given fixture 错形
When  派发
Then  报错退出
EOF
: > "$STUBLOG"
if ( cd "$TMP" && PATH="$STUB:$PATH" HERDR_PANE_ID=wtest:ctl HERDR_FIXDIR="$FIXDIR3" bash qwbuddy/bin/qwb-run.sh --task disp3 --worker codex --here ) >/dev/null 2>&1; then
  bad "错误层级 fixture 驱动真实 run 竟派发成功（运行时解析退化未被抓）"
else
  ok "错误层级 fixture → 真实 run 拒绝派发"
fi
grep -q 'agent start' "$STUBLOG" && bad "被拒后仍调用了 agent start" || ok "被拒后未调用 agent start"
grep -q '^dispatch:' "$DISP3" && bad "被拒仍写了 dispatch 行" || ok "被拒任务书无 dispatch 行"
# 错型也拦在运行时边界：pane_id 为对象 → 拒绝（旧实现会传出 HASH(0x…) 继续派发）
FIXDIR4="$TMP/fix4"; mkdir -p "$FIXDIR4"; cp "$FIXDIR"/*.json "$FIXDIR4/"
printf '%s\n' '{"result":{"root_pane":{"pane_id":{"wrong":1}},"tab":{"tab_id":"t1"}},"id":"x"}' > "$FIXDIR4/tab-create.json"
DISP4="$TMP/tasks/2099-01-41-disp4.md"
cat > "$DISP4" <<'EOF'
# d4
state: blocked

## 1. 验收场景

### user_正常
Given 任务写好
When  派发
Then  pane 写进账本
### user_失败
Given fixture 错形
When  派发
Then  报错退出
EOF
: > "$STUBLOG"
if ( cd "$TMP" && PATH="$STUB:$PATH" HERDR_PANE_ID=wtest:ctl HERDR_FIXDIR="$FIXDIR4" bash qwbuddy/bin/qwb-run.sh --task disp4 --worker codex --here ) >/dev/null 2>&1; then
  bad "pane_id 为对象的响应竟派发成功（运行时无类型约束）"
else
  ok "pane_id 为对象 → 真实 run 拒绝派发"
fi
grep -q 'agent start' "$STUBLOG" && bad "错型被拒后仍调用了 agent start" || ok "错型被拒后未调用 agent start"
grep -q '^dispatch:' "$DISP4" && bad "错型仍写了 dispatch 行" || ok "错型任务书无 dispatch 行"

echo "== 35. R2-M1：再次派发不得覆盖/丢失冻结基线 =="
# 正例：场景改回原文（指纹恢复一致）→ 再派发成功、基线值不变、追加第二条 dispatch
sed -i '' 's/放行执行/拒绝执行/' "$MPT"
( cd "$MP" && PATH="$STUB:$PATH" HERDR_PANE_ID=wtest:mp bash "$MP/qwbuddy/bin/qwb-run.sh" --task mscen --worker codex --here ) >/dev/null \
  && ok "未改场景再次派发成功（返工合法）" || bad "未改场景再次派发被拒"
fp2="$(sed -n 's/^scenarios-fp:[[:space:]]*//p' "$MPT" | head -1 | tr -d '[:space:]')"
[[ "$fp2" == "$mpfp" ]] && ok "再次派发后基线值不变" || bad "再次派发基线被改写"
[[ "$(grep -c '^dispatch:' "$MPT")" == "2" ]] \
  && ok "再次派发正常追加第二条 dispatch 行" || bad "dispatch 行数异常（应为 2）"
# 负例：改场景 → 再派发必须被拒；不触达 herdr、不动账本、不覆盖基线
sed -i '' 's/拒绝执行/放行执行/' "$MPT"
: > "$STUBLOG"
nout="$( cd "$MP" && PATH="$STUB:$PATH" HERDR_PANE_ID=wtest:mp bash "$MP/qwbuddy/bin/qwb-run.sh" --task mscen --worker codex --here 2>&1 )"; nrc=$?
{ [[ "$nrc" -ne 0 ]] && printf '%s' "$nout" | grep -q '派发后被改动'; } \
  && ok "改场景后再次派发被拒（rc=${nrc}）" || bad "改场景后再次派发竟放行（rc=${nrc}）"
{ ! grep -q 'tab create' "$STUBLOG" && ! grep -q 'agent start' "$STUBLOG"; } \
  && ok "被拒未触达 herdr（无 tab create / agent start）" || bad "被拒仍触达 herdr"
[[ "$(grep -c '^dispatch:' "$MPT")" == "2" ]] && ok "被拒未追加 dispatch" || bad "被拒仍改账本"
fp3="$(sed -n 's/^scenarios-fp:[[:space:]]*//p' "$MPT" | head -1 | tr -d '[:space:]')"
[[ "$fp3" == "$mpfp" ]] && ok "被拒后原基线仍在" || bad "被拒后基线被覆盖"
# 恢复场景原文（保持 MP 项目一致）
sed -i '' 's/放行执行/拒绝执行/' "$MPT"
# 负例：删基线留 dispatch → 再派发被拒；--accept-new-scenarios 才允许重建且留说明行
MPT2="$MP/tasks/2099-01-33-mscen2.md"
cat > "$MPT2" <<'EOF'
# mscen2
state: running

## 1. 验收场景

### user_正常
Given 前置
When  动作
Then  成功
### user_失败路径
Given 非法输入
When  动作
Then  拒绝执行
EOF
( cd "$MP" && PATH="$STUB:$PATH" HERDR_PANE_ID=wtest:mp bash "$MP/qwbuddy/bin/qwb-run.sh" --task mscen2 --worker codex --here ) >/dev/null \
  && ok "mscen2 首次派发成功" || bad "mscen2 首次派发被拒"
sed -i '' '/^scenarios-fp:/d' "$MPT2"   # 模拟新制任务丢基线
nout="$( cd "$MP" && PATH="$STUB:$PATH" HERDR_PANE_ID=wtest:mp bash "$MP/qwbuddy/bin/qwb-run.sh" --task mscen2 --worker codex --here 2>&1 )"; nrc=$?
{ [[ "$nrc" -ne 0 ]] && printf '%s' "$nout" | grep -q '冻结基线'; } \
  && ok "删基线留 dispatch → 再派发被拒" || bad "删基线留 dispatch 竟放行（rc=${nrc}）"
( cd "$MP" && PATH="$STUB:$PATH" HERDR_PANE_ID=wtest:mp bash "$MP/qwbuddy/bin/qwb-run.sh" --task mscen2 --worker codex --here --accept-new-scenarios ) >/dev/null \
  && ok "--accept-new-scenarios 允许重建基线" || bad "--accept-new-scenarios 仍被拒"
grep -q '^scenarios-fp:' "$MPT2" && ok "基线已重建写回" || bad "未重建基线"
grep -q 'accept-new-scenarios' "$MPT2" && ok "任务书留了重建说明行" || bad "未留重建说明行"

echo "== 36. R2-M3：死键判定——字面量/纯赋值不算读取 =="
LK="$TMP/lkproj"; mkdir -p "$LK"; bash "$ROOT/bin/qwb-init.sh" "$LK" >/dev/null
printf 'QWB_GATE_FAST="true"\nQWB_GATE_FULL="true"\nexport QWB_AUDIT_UNUSED=1\n' >> "$LK/qwbuddy/config.sh"
# 假引用 1：只打印字面量（无 $）→ 仍须判死键
printf '%s\n' '#!/usr/bin/env bash' 'echo QWB_AUDIT_UNUSED' > "$LK/qwbuddy/bin/helper.sh"
lintout="$(bash "$ROOT/bin/qwb-lint.sh" --project "$LK" 2>&1)"; rc=$?
{ [[ "$rc" -eq 1 ]] && printf '%s' "$lintout" | grep -q 'QWB_AUDIT_UNUSED'; } \
  && ok "echo 字面量不算读取 → lint FAIL" || bad "echo 字面量被当成读取（R2-M3 未修，rc=${rc}）"
# 假引用 2：纯赋值 → 仍须判死键
printf '%s\n' '#!/usr/bin/env bash' 'QWB_AUDIT_UNUSED=2' > "$LK/qwbuddy/bin/helper.sh"
lintout="$(bash "$ROOT/bin/qwb-lint.sh" --project "$LK" 2>&1)"; rc=$?
{ [[ "$rc" -eq 1 ]] && printf '%s' "$lintout" | grep -q 'QWB_AUDIT_UNUSED'; } \
  && ok "纯赋值不算读取 → lint FAIL" || bad "纯赋值被当成读取（R2-M3 未修，rc=${rc}）"
# 对照：真读取 → lint 过
printf '%s\n' '#!/usr/bin/env bash' 'echo "$QWB_AUDIT_UNUSED"' > "$LK/qwbuddy/bin/helper.sh"
bash "$ROOT/bin/qwb-lint.sh" --project "$LK" >/dev/null 2>&1 \
  && ok '真读取 $QWB_X → lint 恢复 0（对照）' || bad "真读取仍 FAIL——判定规则有问题"

echo "== 37. R2-M5：文档不得虚构 qwbuddy 子命令入口 =="
if grep -nE 'qwbuddy[[:space:]]+(init|run|wake|status)([^A-Za-z0-9_]|$)' "$ROOT/README.md" "$ROOT/docs/DESIGN.md"; then
  bad "README/DESIGN 仍出现 qwbuddy <子命令> 入口写法（真实入口是 bin/qwb-*.sh）"
else
  ok "README.md 与 DESIGN.md 无 qwbuddy init/run/wake/status 入口写法"
fi
[[ -x "$ROOT/bin/qwb-init.sh" ]] \
  && ok "真实入口 bin/qwb-init.sh 存在且可执行" || bad "bin/qwb-init.sh 缺失或不可执行"

echo "== 38. SDG① 疑点门：未决 spec-defect 阻止派发（无副作用），处置放行，新疑点再拦截 =="
# 模板同步：两行日志约定 + 审票节必须随 qwb-init 装进目标项目
grep -q 'spec-defect' "$TMP/qwbuddy/TASK.md" && ok "安装的 TASK.md 含 spec-defect 疑点约定" || bad "TASK.md 缺 spec-defect 约定"
grep -q 'spec-resolved' "$TMP/qwbuddy/QWBUDDY.md" && ok "安装的 QWBUDDY.md 含 spec-resolved 处置约定" || bad "QWBUDDY.md 缺 spec-resolved 约定"
grep -q '三个审点' "$TMP/qwbuddy/roles/审核者.md" && ok "安装的 审核者.md 含审票三个审点" || bad "审核者.md 缺审票节"
# 独立 git 项目：默认派发会开 worktree——拒绝路径必须证明 worktree 没被创建
SG="$TMP/specgate"; mkdir -p "$SG"
bash "$ROOT/bin/qwb-init.sh" "$SG" >/dev/null
printf 'QWB_GATE_FAST="true"\nQWB_GATE_FULL="true"\n' >> "$SG/qwbuddy/config.sh"
git -C "$SG" init -q
git -C "$SG" -c user.email=t@t.t -c user.name=t commit -qm init --allow-empty
SGT="$SG/tasks/2099-01-50-sdgate.md"
cat > "$SGT" <<'EOF'
# sdgate
state: running

## 1. 验收场景

### user_正常
Given 任务书写好
When  主控派发
Then  派发成功
### user_失败
Given 票上有未决疑点
When  主控派发
Then  拒绝派发
EOF
# 38a：末尾未决疑点 → 拒绝派发，且无 worktree/窗口/账本副作用
printf 'blocked: spec-defect: §2 要求零外部依赖但 §4 又要求 python3；反例：tests/smoke.sh §8；照做会自相矛盾\n' >> "$SGT"
sg_lines_before="$(wc -l < "$SGT" | tr -d ' ')"
: > "$STUBLOG"
nout="$( cd "$SG" && PATH="$STUB:$PATH" HERDR_PANE_ID=wtest:sg bash qwbuddy/bin/qwb-run.sh --task sdgate --worker codex 2>&1 )"; nrc=$?
{ [[ "$nrc" -ne 0 ]] && printf '%s' "$nout" | grep -q 'spec-defect' && printf '%s' "$nout" | grep -q 'spec-resolved'; } \
  && ok "未决疑点拒绝派发且报错含疑点原文与处置指引（rc=${nrc}）" || bad "未决疑点未拦住派发（rc=${nrc}）"
[[ ! -e "$SG/.worktrees/sdgate" ]] && ok "被拒未创建 worktree" || bad "被拒仍创建了 worktree"
{ ! grep -q 'tab create' "$STUBLOG" && ! grep -q 'agent start' "$STUBLOG"; } \
  && ok "被拒未触达 herdr（无 tab create / agent start）" || bad "被拒仍触达 herdr"
{ ! grep -q '^dispatch:' "$SGT" && ! grep -q '^scenarios-fp:' "$SGT" && grep -q '^state: running' "$SGT"; } \
  && ok "被拒任务书零改动（无 dispatch/scenarios-fp，state 未动）" || bad "被拒仍改了任务书"
[[ "$(wc -l < "$SGT" | tr -d ' ')" == "$sg_lines_before" ]] \
  && ok "被拒任务书行数不变" || bad "被拒任务书行数变了"
# 38b：疑点之后只追加普通状态行（done:/working:）→ 不能解除，仍被拒
printf 'done: 工人自述已修复\nworking: 继续下一阶段\n' >> "$SGT"
: > "$STUBLOG"
nout="$( cd "$SG" && PATH="$STUB:$PATH" HERDR_PANE_ID=wtest:sg bash qwbuddy/bin/qwb-run.sh --task sdgate --worker codex 2>&1 )"; nrc=$?
{ [[ "$nrc" -ne 0 ]] && printf '%s' "$nout" | grep -q 'spec-defect'; } \
  && ok "普通 done:/working: 行不解除疑点，仍拒绝（rc=${nrc}）" || bad "普通状态行竟解除了疑点（rc=${nrc}）"
# 38c：主控追加有效 spec-resolved → 放行派发
printf 'working: spec-resolved: spec；逐项回应：删 §4 的 python3 要求，证据：tests 里仅 smoke.sh 用它；改票位置：§4\n' >> "$SGT"
( cd "$SG" && PATH="$STUB:$PATH" HERDR_PANE_ID=wtest:sg bash qwbuddy/bin/qwb-run.sh --task sdgate --worker codex ) >/dev/null \
  && ok "spec-resolved 处置后派发放行" || bad "处置后仍被拒"
grep -q '^dispatch:' "$SGT" && grep -q '^scenarios-fp:' "$SGT" \
  && ok "放行后正常记账（dispatch + scenarios-fp）" || bad "放行后记账缺失"
[[ -d "$SG/.worktrees/sdgate" ]] && ok "放行后创建了隔离 worktree" || bad "放行后未建 worktree"
# 38d：处置之后新提的疑点 → 重新拦截
printf 'blocked: spec-defect: 新疑点：§3 验收门命令与 §5 重复且不一致\n' >> "$SGT"
: > "$STUBLOG"
nout="$( cd "$SG" && PATH="$STUB:$PATH" HERDR_PANE_ID=wtest:sg bash qwbuddy/bin/qwb-run.sh --task sdgate --worker codex 2>&1 )"; nrc=$?
{ [[ "$nrc" -ne 0 ]] && printf '%s' "$nout" | grep -q '新疑点'; } \
  && ok "处置后新疑点重新拦截（rc=${nrc}）" || bad "新疑点未重新拦截（rc=${nrc}）"
[[ "$(grep -c '^dispatch:' "$SGT")" == "1" ]] && ok "重新拦截未追加 dispatch" || bad "重新拦截仍写了 dispatch"
printf 'done: 二轮收尾自述\n' >> "$SGT"   # 给 39a 制造「疑点被普通日志遮住」的形态

echo "== 39. SDG② 显示与唤醒：status 标出被遮住的疑点；值守接收 blocked 行 =="
# 39a：疑点之后有普通日志（done:）→ status 仍要标出未处理，不被遮住
# （status 走 stub herdr：本节只断言账本判定，不依赖真机 herdr 服务器的响应速度）
out="$( cd "$SG" && PATH="$STUB:$PATH" bash qwbuddy/bin/qwb-status.sh 2>&1 )"
printf '%s' "$out" | grep -q '规格疑点未处理' \
  && ok "status 对未决疑点标「规格疑点未处理」" || bad "status 未标未决疑点"
{ printf '%s' "$out" | grep -q '最近: done: 二轮收尾自述' && printf '%s' "$out" | grep -q '新疑点'; } \
  && ok "疑点被后续 done: 遮不住（最近行与疑点行同显）" || bad "疑点被后续普通日志遮住"
# 39b：对照——最后相关事件是 spec-resolved 的票不标
SG2="$TMP/specgate2"; mkdir -p "$SG2"
bash "$ROOT/bin/qwb-init.sh" "$SG2" >/dev/null
printf '# sgres\nstate: running\nblocked: spec-defect: 旧疑点\nworking: spec-resolved: spec；已改票\ndone: 完成\n' \
  > "$SG2/tasks/2099-01-51-sgres.md"
out="$( cd "$SG2" && PATH="$STUB:$PATH" bash qwbuddy/bin/qwb-status.sh 2>&1 )"
printf '%s' "$out" | grep -q '规格疑点未处理' \
  && bad "已处置疑点仍被标未处理" || ok "对照：spec-resolved 后不再标未处理"
# 39c：现有值守接收 blocked: spec-defect 行——它是 blocked 状态行，改变进展指纹 → 叫醒主控
SGW="$SG2/tasks/2099-01-52-sgwake.md"
printf '# sgwake\nstate: running\nworking: 工人开工\n' > "$SGW"
( cd "$SG2" && PATH="$STUB:$PATH" bash qwbuddy/bin/qwb-wake.sh --once --pane wtest:p9 ) >/dev/null
out="$( cd "$SG2" && bash qwbuddy/bin/qwb-wake.sh --dry-run --once 2>&1 )"
printf '%s' "$out" | grep -q '跳过.*sgwake' \
  && ok "对照：进展未变值守跳过" || bad "进展未变仍要叫（对照失败）"
printf 'blocked: spec-defect: §2 条款冲突；值守应把主控叫回来处置\n' >> "$SGW"
out="$( cd "$SG2" && bash qwbuddy/bin/qwb-wake.sh --dry-run --once 2>&1 )"
printf '%s' "$out" | grep -q '未结项（将叫醒）: 2099-01-52-sgwake' \
  && ok "blocked: spec-defect 行改变进展指纹 → 值守将叫醒主控" || bad "值守没接住 spec-defect 行"

echo "== 40. SDG③ 显式修订：无痕改仍拒；revise 留痕且过 lint；空原因/无旧指纹/写入失败不派发 =="
SGR="$SG/tasks/2099-01-53-sgrev.md"
cat > "$SGR" <<'EOF'
# sgrev
state: running

## 1. 验收场景

### user_正常
Given 场景定稿
When  派发
Then  冻结指纹
### user_失败
Given 场景被无痕改
When  再派发
Then  拒绝
EOF
rm -rf "$SG/qwbuddy/.controller.lock"   # 38c 的派发持过锁；本节统一固定 pane id
( cd "$SG" && PATH="$STUB:$PATH" HERDR_PANE_ID=wtest:sg bash qwbuddy/bin/qwb-run.sh --task sgrev --worker codex --here ) >/dev/null \
  && ok "sgrev 首次派发成功（建立基线）" || bad "sgrev 首次派发失败"
oldfp="$(sed -n 's/^scenarios-fp:[[:space:]]*//p' "$SGR" | head -1 | tr -d '[:space:]')"
[[ -n "$oldfp" ]] && ok "基线 scenarios-fp=${oldfp:0:8}… 已写入" || bad "基线未写入"
# 40a：直接编辑场景块（无修订参数）→ 再派发被拒、lint FAIL
sed -i '' 's/拒绝/放行/' "$SGR"
: > "$STUBLOG"
nout="$( cd "$SG" && PATH="$STUB:$PATH" HERDR_PANE_ID=wtest:sg bash qwbuddy/bin/qwb-run.sh --task sgrev --worker codex --here 2>&1 )"; nrc=$?
{ [[ "$nrc" -ne 0 ]] && printf '%s' "$nout" | grep -q '派发后被改动' && printf '%s' "$nout" | grep -q 'revise-scenarios'; } \
  && ok "无痕改场景再派发被拒且指向显式修订通道（rc=${nrc}）" || bad "无痕改场景竟放行（rc=${nrc}）"
[[ "$(grep -c '^dispatch:' "$SGR")" == "1" ]] && ok "无痕改被拒未追加 dispatch" || bad "无痕改被拒仍追加 dispatch"
lintout="$(bash "$ROOT/bin/qwb-lint.sh" --project "$SG" 2>&1)"; rc=$?
{ [[ "$rc" -eq 1 ]] && printf '%s' "$lintout" | grep -q '派发后被改动'; } \
  && ok "无痕改场景 lint FAIL（指纹不一致）" || bad "lint 未检出无痕改（rc=${rc}）"
# 40a2：处置结论不授权绕过指纹检查——加了 spec-resolved 也过不了
printf 'working: spec-resolved: spec；想以此放行改过的场景\n' >> "$SGR"
nout="$( cd "$SG" && PATH="$STUB:$PATH" HERDR_PANE_ID=wtest:sg bash qwbuddy/bin/qwb-run.sh --task sgrev --worker codex --here 2>&1 )"; nrc=$?
{ [[ "$nrc" -ne 0 ]] && printf '%s' "$nout" | grep -q '派发后被改动'; } \
  && ok "spec-resolved 不授权绕过指纹检查（仍拒，rc=${nrc}）" || bad "spec-resolved 竟当成改场景许可（rc=${nrc}）"
# 40b：显式修订 → 更新基线 + 留痕（旧新指纹）+ 派发成功 + lint 通过
( cd "$SG" && PATH="$STUB:$PATH" HERDR_PANE_ID=wtest:sg bash qwbuddy/bin/qwb-run.sh --task sgrev --worker codex --here \
    --revise-scenarios="主控修订：失败路径 Then 细化为放行（依据票 §2 场景条款）" ) >/dev/null \
  && ok "显式修订后派发成功" || bad "显式修订派发失败"
newfp="$(sed -n 's/^scenarios-fp:[[:space:]]*//p' "$SGR" | head -1 | tr -d '[:space:]')"
[[ -n "$newfp" && "$newfp" != "$oldfp" ]] \
  && ok "基线已更新（${oldfp:0:8}… → ${newfp:0:8}…）" || bad "基线未更新或新旧相同"
grep -q "^working: scenarios-revised: old=${oldfp} new=${newfp} reason=主控修订" "$SGR" \
  && ok "修订记录保留旧新指纹与原因（scenarios-revised 留痕）" || bad "修订记录缺失或不完整"
[[ "$(grep -c '^dispatch:' "$SGR")" == "2" ]] && ok "修订后正常追加第二条 dispatch" || bad "修订后 dispatch 行数异常"
lintout="$(bash "$ROOT/bin/qwb-lint.sh" --project "$SG" 2>&1)"; rc=$?
{ [[ "$rc" -eq 0 ]] && printf '%s' "$lintout" | grep -q 'LINT PASS'; } \
  && ok "显式修订后 lint 通过（最新记录 new= 与基线一致）" || { bad "修订后 lint 仍 FAIL（rc=${rc}）:"; printf '%s\n' "$lintout"; }
# 40b2：最新一条修订记录的 new= 与当前基线不一致（伪造/错配）→ lint 必须 FAIL（2.5 第二半：记录核对）
printf 'working: scenarios-revised: old=%s new=0000000000000000000000000000000000000000 reason=伪造记录演练\n' "$newfp" >> "$SGR"
lintout="$(bash "$ROOT/bin/qwb-lint.sh" --project "$SG" 2>&1)"; rc=$?
{ [[ "$rc" -eq 1 ]] && printf '%s' "$lintout" | grep -q '最新修订记录'; } \
  && ok "最新修订记录 new= 与基线错配 → lint FAIL" || bad "修订记录 new= 错配竟过 lint（rc=${rc}）"
sed -i '' '$d' "$SGR"   # 撤掉伪造记录，恢复「最新记录 == 基线」
bash "$ROOT/bin/qwb-lint.sh" --project "$SG" >/dev/null 2>&1 \
  && ok "撤掉伪造记录后 lint 恢复 PASS" || bad "撤掉伪造记录后 lint 仍 FAIL"
# 40c：空原因 → 拒绝派发，不留半更新修订记录
sed -i '' 's/放行/拒绝并报错/' "$SGR"
: > "$STUBLOG"
nout="$( cd "$SG" && PATH="$STUB:$PATH" HERDR_PANE_ID=wtest:sg bash qwbuddy/bin/qwb-run.sh --task sgrev --worker codex --here --revise-scenarios= 2>&1 )"; nrc=$?
{ [[ "$nrc" -ne 0 ]] && printf '%s' "$nout" | grep -q '原因不能为空'; } \
  && ok "空原因拒绝派发（rc=${nrc}）" || bad "空原因竟放行（rc=${nrc}）"
[[ "$(grep -c '^working:[[:space:]]*scenarios-revised:' "$SGR")" == "1" ]] \
  && ok "空原因未留修订记录" || bad "空原因仍写了修订记录"
[[ "$(grep -c '^dispatch:' "$SGR")" == "2" ]] && ok "空原因未派发（dispatch 仍 2 条）" || bad "空原因仍派发"
curfp="$(sed -n 's/^scenarios-fp:[[:space:]]*//p' "$SGR" | head -1 | tr -d '[:space:]')"
[[ "$curfp" == "$newfp" ]] && ok "空原因未动基线" || bad "空原因动了基线"
{ ! grep -q 'tab create' "$STUBLOG" && ! grep -q 'agent start' "$STUBLOG"; } \
  && ok "空原因未触达 herdr" || bad "空原因仍触达 herdr"
# 40d：写入失败（任务书被锁不可替换）→ 拒绝派发，无半更新状态
sed -i '' 's/拒绝并报错/直接拒绝/' "$SGR"
if command -v chflags >/dev/null 2>&1; then
  chflags uchg "$SGR"
  : > "$STUBLOG"
  nout="$( cd "$SG" && PATH="$STUB:$PATH" HERDR_PANE_ID=wtest:sg bash qwbuddy/bin/qwb-run.sh --task sgrev --worker codex --here \
      --revise-scenarios="写入失败演练" 2>&1 )"; nrc=$?
  chflags nouchg "$SGR"
  [[ "$nrc" -ne 0 ]] \
    && ok "写入失败拒绝派发（rc=${nrc}）" || bad "写入失败竟继续派发（rc=${nrc}）"
  [[ "$(grep -c '^working:[[:space:]]*scenarios-revised:' "$SGR")" == "1" ]] \
    && ok "写入失败未留半更新修订记录" || bad "写入失败仍写了修订记录"
  curfp="$(sed -n 's/^scenarios-fp:[[:space:]]*//p' "$SGR" | head -1 | tr -d '[:space:]')"
  [[ "$curfp" == "$newfp" ]] && ok "写入失败基线未半更新" || bad "写入失败基线被半更新"
  [[ "$(grep -c '^dispatch:' "$SGR")" == "2" ]] && ok "写入失败未派发（dispatch 仍 2 条）" || bad "写入失败仍派发"
  { ! grep -q 'tab create' "$STUBLOG" && ! grep -q 'agent start' "$STUBLOG"; } \
    && ok "写入失败未触达 herdr" || bad "写入失败仍触达 herdr"
  [[ -z "$(ls "$SG"/tasks/*.revise.* 2>/dev/null)" ]] \
    && ok "无修订临时文件残留" || bad "有修订临时文件残留"
else
  echo "SKIP  无 chflags，写入失败路径未演练"
fi
# 40e：票内无旧指纹（从未派发）→ 修订拒绝，指向 --accept-new-scenarios
SGR2="$SG/tasks/2099-01-54-sgrev-nofp.md"
cat > "$SGR2" <<'EOF'
# sgrev-nofp
state: running

## 1. 验收场景

### user_正常
Given 场景定稿
When  派发
Then  冻结指纹
### user_失败
Given 无基线还想修订
When  用 --revise-scenarios 派发
Then  拒绝
EOF
: > "$STUBLOG"
nout="$( cd "$SG" && PATH="$STUB:$PATH" HERDR_PANE_ID=wtest:sg bash qwbuddy/bin/qwb-run.sh --task sgrev-nofp --worker codex --here \
    --revise-scenarios="想直接建基线" 2>&1 )"; nrc=$?
{ [[ "$nrc" -ne 0 ]] && printf '%s' "$nout" | grep -q '旧指纹'; } \
  && ok "无旧指纹拒绝修订派发（rc=${nrc}）" || bad "无旧指纹竟接受修订（rc=${nrc}）"
{ ! grep -q '^dispatch:' "$SGR2" && ! grep -q '^scenarios-revised:' "$SGR2"; } \
  && ok "无旧指纹路径零副作用" || bad "无旧指纹路径留了副作用"
# 40f：修订与 --accept-new-scenarios 互斥
nout="$( cd "$SG" && PATH="$STUB:$PATH" HERDR_PANE_ID=wtest:sg bash qwbuddy/bin/qwb-run.sh --task sgrev-nofp --worker codex --here \
    --revise-scenarios="x" --accept-new-scenarios 2>&1 )"; nrc=$?
{ [[ "$nrc" -ne 0 ]] && printf '%s' "$nout" | grep -q '互斥'; } \
  && ok "修订与 --accept-new-scenarios 互斥（rc=${nrc}）" || bad "两个修订参数竟混用（rc=${nrc}）"

echo "== 41. SDG④ 隔离副本幂等：返工/修订后再派不撞已存在；脏目录拒绝（验收报回的主路径）=="
SG3="$TMP/specidem"; mkdir -p "$SG3"
bash "$ROOT/bin/qwb-init.sh" "$SG3" >/dev/null
printf 'QWB_GATE_FAST="true"\nQWB_GATE_FULL="true"\n' >> "$SG3/qwbuddy/config.sh"
git -C "$SG3" init -q
git -C "$SG3" -c user.email=t@t.t -c user.name=t commit -qm init --allow-empty
SGI="$SG3/tasks/2099-01-60-sgidem.md"
cat > "$SGI" <<'EOF'
# sgidem
state: running

## 1. 验收场景

### user_正常
Given 场景定稿
When  默认派发
Then  建隔离副本
### user_失败
Given 目标目录已存在但不是有效 worktree
When  默认派发
Then  拒绝并提示清理
EOF
sgrun() { ( cd "$SG3" && PATH="$STUB:$PATH" HERDR_PANE_ID=wtest:sg3 bash qwbuddy/bin/qwb-run.sh "$@" ); }
wt_count() { git -C "$SG3" worktree list --porcelain 2>/dev/null | grep -c '^worktree .*/\.worktrees/sgidem$'; }
sgrun --task sgidem --worker codex >/dev/null 2>&1 && ok "首次派发成功" || bad "首次派发失败"
[[ "$(wt_count)" == "1" ]] && ok "首次派发后该任务恰一份 worktree" || bad "首次派发后 worktree 份数=$(wt_count)"
# 41a：返工再派（无修订）必须成功且复用同一份副本——验收报的 rc=1 路径
out="$(sgrun --task sgidem --worker codex 2>&1)"; rc=$?
{ [[ "$rc" -eq 0 ]] && printf '%s' "$out" | grep -q '复用既有隔离副本'; } \
  && ok "返工再派发成功且复用既有副本（rc=${rc}）" || { bad "返工再派发失败（rc=${rc}）"; printf '%s\n' "$out" >&2; }
[[ "$(wt_count)" == "1" ]] && ok "复派后仍恰一份 worktree（复用非重建）" || bad "复派后 worktree 份数=$(wt_count)"
[[ "$(grep -c '^dispatch:' "$SGI")" == "2" ]] && ok "复派追加第二条 dispatch" || bad "复派 dispatch 行数=$(grep -c '^dispatch:' "$SGI")"
# 41a2：显式 --create-worktree 同样幂等
out="$(sgrun --task sgidem --worker codex --create-worktree 2>&1)"; rc=$?
{ [[ "$rc" -eq 0 ]] && printf '%s' "$out" | grep -q '复用既有隔离副本'; } \
  && ok "--create-worktree 同样幂等（rc=${rc}）" || { bad "--create-worktree 非幂等（rc=${rc}）"; printf '%s\n' "$out" >&2; }
[[ "$(wt_count)" == "1" ]] && ok "--create-worktree 后仍恰一份 worktree" || bad "--create-worktree 后份数=$(wt_count)"
# 41b：改场景 → 显式修订 → 继续派发（端到端，正是验收失败的那条路）
sed -i '' 's/Then  建隔离副本/Then  复用隔离副本/' "$SGI"
out="$(sgrun --task sgidem --worker codex --revise-scenarios="主控修订：结果措辞细化（依据本票 §1 场景条款）" 2>&1)"; rc=$?
{ [[ "$rc" -eq 0 ]] && printf '%s' "$out" | grep -q '复用既有隔离副本'; } \
  && ok "改场景后 --revise-scenarios 继续派发成功（端到端，rc=${rc}）" || { bad "改场景后修订派发失败（rc=${rc}）"; printf '%s\n' "$out" >&2; }
[[ "$(grep -c '^dispatch:' "$SGI")" == "4" ]] && ok "修订后追加第四条 dispatch" || bad "修订后 dispatch 行数=$(grep -c '^dispatch:' "$SGI")"
[[ "$(wt_count)" == "1" ]] && ok "全程该任务只有一份 worktree（无重复登记）" || bad "worktree 重复登记：$(wt_count)"
# 41c：目录存在但不是有效 worktree（普通脏目录）→ 拒绝 + 提示清理，不盲目复用
SG5="$SG3/tasks/2099-01-61-sgdirty.md"
cat > "$SG5" <<'EOF'
# sgdirty
state: running

## 1. 验收场景

### user_正常
Given 脏目录占位
When  默认派发
Then  拒绝
### user_失败
Given 脏目录占位
When  忽略清理提示再派
Then  仍拒绝
EOF
mkdir -p "$SG3/.worktrees/sgdirty"; printf 'junk\n' > "$SG3/.worktrees/sgdirty/README.junk"
: > "$STUBLOG"
out="$(sgrun --task sgdirty --worker codex 2>&1)"; rc=$?
{ [[ "$rc" -ne 0 ]] && printf '%s' "$out" | grep -q '有效 git worktree' && printf '%s' "$out" | grep -q 'rm -rf'; } \
  && ok "普通脏目录 → 拒绝并提示清理（rc=${rc}）" || bad "脏目录未被拒或未提示清理（rc=${rc}）"
{ ! grep -q '^dispatch:' "$SG5" && [[ -f "$SG3/.worktrees/sgdirty/README.junk" ]] && ! grep -q 'tab create' "$STUBLOG"; } \
  && ok "脏目录路径零副作用（未派发/未删目录/未触达 herdr）" || bad "脏目录路径有副作用"
# 41c2：曾登记但目录已被换掉的残留（git 里仍可查）→ 同样拒绝
rm -rf "$SG3/.worktrees/sgidem"; mkdir -p "$SG3/.worktrees/sgidem"
: > "$STUBLOG"
out="$(sgrun --task sgidem --worker codex 2>&1)"; rc=$?
[[ "$rc" -ne 0 ]] && printf '%s' "$out" | grep -q '有效 git worktree' \
  && ok "已登记但目录被换掉的残留 → 拒绝（rc=${rc}）" || bad "残留目录被盲目复用（rc=${rc}）"
[[ "$(grep -c '^dispatch:' "$SGI")" == "4" ]] && ok "残留拒绝后未追加 dispatch" || bad "残留拒绝后仍派发"

echo "== 42. user_开局无需手工启动值守（qwb-wake.sh --ensure 幂等确保）=="
# 场景（票内 user_开局无需手工启动值守 / user_失活值守明确可见）：
#   Given 项目已安装、主控存活、尚无本项目有效值守  When 主控按开局步骤调 --ensure
#   Then 本 workspace 内建一个可见值守 tab、记录身份、启动 qwb-wake.sh；重复调用复用不重复创建
ENSP="$TMP/ensproj"; mkdir -p "$ENSP"; bash "$ROOT/bin/qwb-init.sh" "$ENSP" >/dev/null
DYN="$TMP/herdr-dyn"
wsan() { printf '%s' "$1" | tr -cd 'a-zA-Z0-9'; }
ensrun() { ( cd "$ENSP" && PATH="$STUB:$PATH" HERDR_WORKSPACE_ID="${ENWS:-wtestW}" HERDR_PANE_ID=wtest:ctl \
    HERDR_DYN_DIR="$DYN" bash qwbuddy/bin/qwb-wake.sh "$@" ); }
mk_plist() { # $1=输出文件；其余参数 = "paneid[@ws]"（纯 shell）或 "paneid[@ws],agent"（agent pane）；ws 缺省 wtestW
  local out="$1"; shift; local spec pid pws first=1
  { printf '{"result":{"panes":['
    for spec in "$@"; do
      pid="${spec%%,agent*}"; pws="${pid##*@}"; [[ "$pws" == "$pid" ]] && pws=wtestW; pid="${pid%%@*}"
      [[ $first -eq 0 ]] && printf ','; first=0
      if [[ "$spec" == *,agent ]]; then
        printf '{"pane_id":"%s","workspace_id":"%s","agent":"devin","agent_status":"idle"}' "$pid" "$pws"
      else
        printf '{"pane_id":"%s","workspace_id":"%s","agent_status":"unknown"}' "$pid" "$pws"
      fi
    done
    printf '],"type":"pane_list"}}'; } > "$out"
}
mk_get() { # $1=pane $2=cwd(物理) [$3=agent名] [$4=workspace] → $DYN/get-<san>.json
  local pid="$1" cwd="$2" ag="${3:-}" ws="${4:-wtestW}" sj
  sj="$(wsan "$pid")"
  sed "s|w8Z:pY|$pid|g; s|/private/tmp/qwb02probe/untrusted-dir|$cwd|g; s|/private/tmp/qwb02probe|$cwd|g; s|\"w8Z\"|\"$ws\"|g" "$FIXDIR/pane-get-shell.json" \
    | { [[ -n "$ag" ]] && sed 's|"agent_status":"unknown"|"agent":"'"$ag"'","agent_status":"idle"|' || cat; } \
    > "$DYN/get-$sj.json"
}
mk_proc() { # $1=pane $2=shell|wake|busy [$3=项目根] [$4=值守 --pane 目标] → $DYN/proc-<san>.json
  local pid="$1" shape="$2" proj="${3:-}" tp="${4:-}" sj
  sj="$(wsan "$pid")"
  sed "s|w8Z:pY|$pid|g" "$FIXDIR/proc-$shape.json" \
    | { [[ -n "$proj" ]] && sed "s|/tmp/qwb02probe|$proj|g; s|/private/tmp/qwb02probe|$proj|g" || cat; } \
    | { [[ -n "$tp" ]] && sed -e "s|--interval 5000|--pane $tp --interval 5000|g" \
          -e "s|\"--interval\"|\"--pane\",\"$tp\",\"--interval\"|g" || cat; } \
    > "$DYN/proc-$sj.json"
}
ensreset() { rm -rf "$DYN" "$ENSP/qwbuddy/.controller.lock"; mkdir -p "$DYN"; rm -f "$ENSP/qwbuddy/.watch"; : > "$STUBLOG";
  mk_get wtest:ctl "$ENSP" "" "${ENWS:-wtestW}"; }  # 目标主控 pane 默认存在且同 workspace（个别用例再覆盖/删除）

# 42a 正例：无值守 → ensure 建可见 tab + 起值守 + 写身份记录
ensreset
mk_plist "$DYN/pane-list.json" "w93:p1,agent"
out="$(ensrun --ensure --pane wtest:ctl 2>&1)"; rc=$?
{ [[ "$rc" -eq 0 ]] && grep -q 'tab create.*--workspace wtestW' "$STUBLOG" \
   && grep -q "pane run w93:p7.*qwb-wake.sh.*--project.*$ENSP" "$STUBLOG"; } \
  && ok "ensure 在调用者 workspace 建 tab 并启动值守（rc=${rc}）" \
  || { bad "ensure 建值守失败（rc=${rc}）"; printf '%s\n' "$out"; cat "$STUBLOG"; }
grep -q 'pane=w93:p7' "$ENSP/qwbuddy/.watch" && ok "ensure 写了 .watch 身份记录" || bad ".watch 未写或缺 pane"

# 42b 幂等：值守进程活着 → 再 ensure 复用，不新建
mk_plist "$DYN/pane-list.json" "w93:p7" "w93:p1,agent"   # stub 的 pane run 已把 proc-w93p7 写成 wake 形
out="$(ensrun --ensure --pane wtest:ctl 2>&1)"; rc=$?
{ [[ "$rc" -eq 0 ]] && [[ "$(grep -c 'tab create' "$STUBLOG")" == "1" ]] && printf '%s' "$out" | grep -q '复用'; } \
  && ok "重复 ensure 复用不新建（rc=${rc}）" || { bad "重复 ensure 行为不对（rc=${rc}）"; printf '%s\n' "$out"; cat "$STUBLOG"; }

# 42c 负例：值守退出 shell 仍在 → 同 pane 重启（不新开 tab），且此前 status 不得报运行
ensreset
printf 'pane=w93:p7 workspace=wtestW pid=111 started=x\n' > "$ENSP/qwbuddy/.watch"
mk_plist "$DYN/pane-list.json" "w93:p7"
mk_get w93:p7 "$ENSP"; mk_proc w93:p7 shell "$ENSP"
sout="$( cd "$ENSP" && PATH="$STUB:$PATH" HERDR_DYN_DIR="$DYN" \
  HERDR_WORKSPACE_ID=wtestW HERDR_PANE_ID=wtest:ctl bash qwbuddy/bin/qwb-status.sh )"
printf '%s' "$sout" | grep -q '值守：未运行' \
  && ok "值守退出 shell 仍在 → status 报未运行（不报运行）" || { bad "status 把活 pane 当成值守健康"; printf '%s\n' "$sout"; }
out="$(ensrun --ensure --pane wtest:ctl 2>&1)"; rc=$?
{ [[ "$rc" -eq 0 ]] && [[ "$(grep -c 'tab create' "$STUBLOG")" == "0" ]] && grep -q 'pane run w93:p7' "$STUBLOG"; } \
  && ok "shell 空闲 → 同一 pane 重启值守（rc=${rc}）" || { bad "原 pane 重启失败（rc=${rc}）"; printf '%s\n' "$out"; cat "$STUBLOG"; }

# 42d 负例：登记 pane 被其他进程占用 → 新开 tab，不动旧 pane
ensreset
printf 'pane=w93:p7 workspace=wtestW pid=111 started=x\n' > "$ENSP/qwbuddy/.watch"
mk_plist "$DYN/pane-list.json" "w93:p7"
mk_get w93:p7 "$ENSP"; mk_proc w93:p7 busy "$ENSP"
printf '{"result":{"root_pane":{"pane_id":"w9E:p2","cwd":"%s","workspace_id":"wtestW"},"tab":{"tab_id":"w9E:t2"}}}\n' "$ENSP" > "$DYN/tab-create.json"
out="$(ensrun --ensure --pane wtest:ctl 2>&1)"; rc=$?
{ [[ "$rc" -eq 0 ]] && grep -q 'tab create' "$STUBLOG" && ! grep -q 'pane run w93:p7' "$STUBLOG" \
   && grep -q 'pane=w9E:p2' "$ENSP/qwbuddy/.watch"; } \
  && ok "登记 pane 被占用 → 新开 tab 并改记 .watch（rc=${rc}）" \
  || { bad "占用 pane 处理不对（rc=${rc}）"; printf '%s\n' "$out"; cat "$STUBLOG"; }

# 42e 负例：登记 pane 已不存在 → 新开 tab
ensreset
printf 'pane=w8Z:pGONE workspace=wtestW pid=1 started=x\n' > "$ENSP/qwbuddy/.watch"
mk_plist "$DYN/pane-list.json" "w93:p1,agent"
out="$(ensrun --ensure --pane wtest:ctl 2>&1)"; rc=$?
{ [[ "$rc" -eq 0 ]] && grep -q 'tab create' "$STUBLOG" && grep -q 'pane=w93:p7' "$ENSP/qwbuddy/.watch"; } \
  && ok "登记 pane 消失 → 新开 tab 重建（rc=${rc}）" || { bad "pane 消失处理不对（rc=${rc}）"; printf '%s\n' "$out"; cat "$STUBLOG"; }

# 42f 负例（第二轮规格反转）：登记 pane 在别的 workspace → 不认领/不重启，拒绝给步骤；
#   且该 pane 上真有本项目值守进程也不许跨 workspace 行动
ensreset
printf 'pane=w8Z:pZ workspace=w8Z pid=111 started=x\n' > "$ENSP/qwbuddy/.watch"
mk_plist "$DYN/pane-list.json" "w8Z:pZ@w8Z" "w93:p1,agent"
mk_get w8Z:pZ "$ENSP" "" w8Z; mk_proc w8Z:pZ wake "$ENSP" "wtest:ctl"
out="$(ensrun --ensure --pane wtest:ctl 2>&1)"; rc=$?
{ [[ "$rc" -ne 0 ]] && printf '%s' "$out" | grep -q 'w8Z' \
   && ! grep -q 'tab create' "$STUBLOG" && ! grep -q 'pane run w8Z:pZ' "$STUBLOG"; } \
  && ok "登记 pane 属别的 workspace → 拒绝不认领（rc=${rc}）" \
  || { bad "跨 workspace 竟认领/重启（rc=${rc}）"; printf '%s\n' "$out"; cat "$STUBLOG"; }

# 42g 负例：发现两个本项目值守实例 → 报错，不新建不杀不占
ensreset
mk_plist "$DYN/pane-list.json" "w8Z:pZ1" "w8Z:pZ2"
mk_get w8Z:pZ1 "$ENSP" "" w8Z; mk_proc w8Z:pZ1 wake "$ENSP"
mk_get w8Z:pZ2 "$ENSP" "" w8Z; mk_proc w8Z:pZ2 wake "$ENSP"
out="$(ensrun --ensure --pane wtest:ctl 2>&1)"; rc=$?
{ [[ "$rc" -ne 0 ]] && printf '%s' "$out" | grep -q 'w8Z:pZ1' && printf '%s' "$out" | grep -q 'w8Z:pZ2' \
   && ! grep -q 'tab create' "$STUBLOG" && ! grep -q 'pane run' "$STUBLOG"; } \
  && ok "双值守实例 → 报错且零副作用（rc=${rc}）" || { bad "双实例未拦住（rc=${rc}）"; printf '%s\n' "$out"; cat "$STUBLOG"; }

# 42h 负例：无 Herdr 上下文（两 env 皆无）→ 明确拒绝
out="$( cd "$ENSP" && PATH="$STUB:$PATH" HERDR_DYN_DIR="$DYN" env -u HERDR_WORKSPACE_ID -u HERDR_PANE_ID \
    bash qwbuddy/bin/qwb-wake.sh --ensure --pane wtest:ctl 2>&1 )"; rc=$?
{ [[ "$rc" -ne 0 ]] && printf '%s' "$out" | grep -qi 'herdr'; } \
  && ok "无 Herdr 上下文 → 拒绝（rc=${rc}）" || bad "无上下文竟执行（rc=${rc}）"
# 42h2 正例变体：只有 HERDR_PANE_ID 时从 pane get 推导 workspace
ensreset
mk_plist "$DYN/pane-list.json" "w93:p1,agent"
mk_get wtest:ctl "$ENSP" "" wtestW
out="$( cd "$ENSP" && PATH="$STUB:$PATH" HERDR_DYN_DIR="$DYN" HERDR_PANE_ID=wtest:ctl env -u HERDR_WORKSPACE_ID \
    bash qwbuddy/bin/qwb-wake.sh --ensure --pane wtest:ctl 2>&1 )"; rc=$?
{ [[ "$rc" -eq 0 ]] && grep -q 'tab create.*--workspace wtestW' "$STUBLOG"; } \
  && ok "仅 HERDR_PANE_ID → 推导 workspace 后正常建（rc=${rc}）" || { bad "workspace 推导失败（rc=${rc}）"; printf '%s\n' "$out"; cat "$STUBLOG"; }

# 42i 负例：herdr 查询失败（pane list 挂）→ 报错，不擅自开实例
ensreset
mk_plist "$DYN/pane-list.json" "w93:p1,agent"
out="$( cd "$ENSP" && PATH="$STUB:$PATH" HERDR_DYN_DIR="$DYN" HERDR_WORKSPACE_ID=wtestW HERDR_PANE_ID=wtest:ctl \
    HERDR_FAIL=list bash qwbuddy/bin/qwb-wake.sh --ensure --pane wtest:ctl 2>&1 )"; rc=$?
{ [[ "$rc" -ne 0 ]] && ! grep -q 'tab create' "$STUBLOG"; } \
  && ok "pane list 失败 → 报错不开新实例（rc=${rc}）" || bad "查询失败仍乱动（rc=${rc}）"

# 42j 负例：--ensure 与 --once/--dry-run 互斥
for mx in --once --dry-run; do
  ensrun --ensure "$mx" >/dev/null 2>&1 && bad "--ensure $mx 竟放行" || ok "--ensure $mx 互斥拒绝"
done

echo "== 43. user_失活值守明确可见（status 值守段）=="
# 场景（票内 user_失活值守明确可见）：Given 账本记录的值守已退出或 pane 在但进程不在
#   When status/开局检查  Then 明确显示未运行或未知，不把「pane 存在」当健康
statrun() { ( cd "$ENSP" && PATH="${SPATH_OVERRIDE:-$STUB:$PATH}" HERDR_DYN_DIR="$DYN" \
    HERDR_WORKSPACE_ID="${ENWS:-wtestW}" HERDR_PANE_ID=wtest:ctl bash qwbuddy/bin/qwb-status.sh ); }
ensreset
# 43a 运行：登记 pane + 进程在
printf 'pane=w93:p7 workspace=wtestW pid=111 started=x\n' > "$ENSP/qwbuddy/.watch"
mk_plist "$DYN/pane-list.json" "w93:p7"; mk_get w93:p7 "$ENSP"; mk_proc w93:p7 wake "$ENSP"
out="$(statrun)"
{ printf '%s' "$out" | grep -q '值守：tab' && printf '%s' "$out" | grep -q 'w93:p7'; } \
  && ok "status 值守显示运行+pane" || { bad "status 未显示运行"; printf '%s\n' "$out"; }
# 43b 进程退出、shell 仍在 → 未运行（不得只凭 pane 存在报健康）
mk_proc w93:p7 shell "$ENSP"
out="$(statrun)"
{ printf '%s' "$out" | grep -q '值守：未运行' && printf '%s' "$out" | grep -qi '退出\|不在'; } \
  && ok "pane 在进程不在 → 未运行" || { bad "进程不在仍报运行"; printf '%s\n' "$out"; }
# 43c 登记 pane 已不存在 → 未运行
rm -f "$DYN/get-$(wsan w93:p7).json" "$DYN/proc-$(wsan w93:p7).json"
out="$(statrun)"
printf '%s' "$out" | grep -q '值守：未运行' \
  && ok "登记 pane 消失 → 未运行" || { bad "pane 消失仍报非未运行"; printf '%s\n' "$out"; }
# 43d 登记 pane 被其他进程占用 → 未运行
mk_get w93:p7 "$ENSP"; mk_proc w93:p7 busy "$ENSP"
out="$(statrun)"
printf '%s' "$out" | grep -q '值守：未运行' \
  && ok "pane 被占用 → 未运行" || { bad "占用 pane 报非未运行"; printf '%s\n' "$out"; }
# 43e 无登记但扫到活的本项目值守（手工启动）→ 运行 + 标明未登记
rm -f "$ENSP/qwbuddy/.watch"
mk_plist "$DYN/pane-list.json" "w8Z:pZ" "w93:p1,agent"; mk_get w8Z:pZ "$ENSP" "" w8Z; mk_proc w8Z:pZ wake "$ENSP"
out="$(statrun)"
{ printf '%s' "$out" | grep -q '值守：tab' && printf '%s' "$out" | grep -q 'w8Z:pZ'; } \
  && ok "未登记值守被扫到 → 运行" || { bad "未登记值守漏检"; printf '%s\n' "$out"; }
# 43f 无登记也扫不到 → 未运行
ensreset
mk_plist "$DYN/pane-list.json" "w93:p1,agent"
out="$(statrun)"
printf '%s' "$out" | grep -q '值守：未运行' \
  && ok "无记录无进程 → 未运行" || { bad "空值守未报未运行"; printf '%s\n' "$out"; }
# 43g 无 herdr → 未知（不许静默报未运行）
out="$(SPATH_OVERRIDE="/usr/bin:/bin" statrun)"
printf '%s' "$out" | grep -q '值守：未知' \
  && ok "无 herdr → 值守状态未知" || { bad "无 herdr 未报未知"; printf '%s\n' "$out"; }
# 43h 登记 pane 存在但进程查询失败 → 未知
ensreset
printf 'pane=w93:p7 workspace=wtestW pid=111 started=x\n' > "$ENSP/qwbuddy/.watch"
mk_plist "$DYN/pane-list.json" "w93:p7"; mk_get w93:p7 "$ENSP"
printf '{"error":{"code":"io_error","message":"mocked proc failure"}}\n' > "$DYN/proc-$(wsan w93:p7).err"
out="$(statrun)"
printf '%s' "$out" | grep -q '值守：未知' \
  && ok "进程查询失败 → 未知" || { bad "查询失败未报未知"; printf '%s\n' "$out"; }

echo "== 44. --pane 复用先核对 cwd 与 pane 状态（派发副作用前拒）=="
# 场景（票内落地要求 3）：--pane 复用要在派发副作用前核对 cwd 与目标 worktree，
#   无法确认或不一致则拒绝并给明确修复步骤；不往未知 TUI 发命令
rm -rf "$TMP/qwbuddy/.controller.lock"
PDIR="$(cd "$TMP" && pwd -P)"
# 44a 正例：pane cwd == DIR 且 shell 空闲 → 放行
mk_plist "$DYN/pane-list.json" "w8Z:pY"
mk_get w8Z:pY "$PDIR"; mk_proc w8Z:pY shell "$PDIR"
dbefore="$(grep -c '^dispatch:' "$DISP")"
out="$( cd "$TMP" && PATH="$STUB:$PATH" HERDR_DYN_DIR="$DYN" HERDR_PANE_ID=wtest:ctl \
    bash qwbuddy/bin/qwb-run.sh --task 2099-01-02-disp --worker codex --here --pane w8Z:pY 2>&1 )"; rc=$?
{ [[ "$rc" -eq 0 ]] && [[ "$(grep -c '^dispatch:' "$DISP")" == "$((dbefore+1))" ]] \
   && grep -q 'pane process-info' "$STUBLOG"; } \
  && ok "--pane cwd 相符+空闲 shell → 放行（rc=${rc}）" || { bad "--pane 正常路径被拒（rc=${rc}）"; printf '%s\n' "$out"; }
grep "^dispatch:" "$DISP" | tail -1 | grep -q 'pane=w8Z:pY' \
  && ok "dispatch 行记录复用 pane" || bad "dispatch 未记 pane"
# 44b 负例：pane cwd 不符 → 拒派，零副作用，报错给修复步骤
mk_get w8Z:pY "/somewhere/else"; mk_proc w8Z:pY shell "/somewhere/else"
dbefore="$(grep -c '^dispatch:' "$DISP")"; : > "$STUBLOG"
out="$( cd "$TMP" && PATH="$STUB:$PATH" HERDR_DYN_DIR="$DYN" HERDR_PANE_ID=wtest:ctl \
    bash qwbuddy/bin/qwb-run.sh --task 2099-01-02-disp --worker codex --here --pane w8Z:pY 2>&1 )"; rc=$?
{ [[ "$rc" -ne 0 ]] && printf '%s' "$out" | grep -q 'cwd' && printf '%s' "$out" | grep -q 'cd ' \
   && [[ "$(grep -c '^dispatch:' "$DISP")" == "$dbefore" ]] \
   && ! grep -q 'agent start' "$STUBLOG"; } \
  && ok "--pane cwd 不符 → 拒派+给 cd 修复步骤+零副作用（rc=${rc}）" || { bad "cwd 不符竟放行（rc=${rc}）"; printf '%s\n' "$out"; }
# 44c 负例：pane 查询不到 → 拒派
rm -f "$DYN/get-$(wsan w8Z:pY).json"
dbefore="$(grep -c '^dispatch:' "$DISP")"
out="$( cd "$TMP" && PATH="$STUB:$PATH" HERDR_DYN_DIR="$DYN" HERDR_PANE_ID=wtest:ctl \
    bash qwbuddy/bin/qwb-run.sh --task 2099-01-02-disp --worker codex --here --pane w8Z:pY 2>&1 )"; rc=$?
{ [[ "$rc" -ne 0 ]] && printf '%s' "$out" | grep -qi '无法确认\|不存在' \
   && [[ "$(grep -c '^dispatch:' "$DISP")" == "$dbefore" ]]; } \
  && ok "--pane 不可查询 → 拒派（rc=${rc}）" || { bad "pane 不存在竟放行（rc=${rc}）"; printf '%s\n' "$out"; }
# 44d 负例：pane 前台有进程在跑（非空闲 shell）→ 拒派
mk_get w8Z:pY "$PDIR"; mk_proc w8Z:pY busy "$PDIR"
out="$( cd "$TMP" && PATH="$STUB:$PATH" HERDR_DYN_DIR="$DYN" HERDR_PANE_ID=wtest:ctl \
    bash qwbuddy/bin/qwb-run.sh --task 2099-01-02-disp --worker codex --here --pane w8Z:pY 2>&1 )"; rc=$?
{ [[ "$rc" -ne 0 ]] && printf '%s' "$out" | grep -qi '占用\|非空闲\|进程'; } \
  && ok "--pane 前台非空闲 → 拒派（rc=${rc}）" || { bad "忙 pane 竟放行（rc=${rc}）"; printf '%s\n' "$out"; }
# 44e 负例：pane 里跑着 agent TUI → 拒派（不往 TUI 发命令）
mk_get w8Z:pY "$PDIR" devin; mk_proc w8Z:pY busy "$PDIR"
out="$( cd "$TMP" && PATH="$STUB:$PATH" HERDR_DYN_DIR="$DYN" HERDR_PANE_ID=wtest:ctl \
    bash qwbuddy/bin/qwb-run.sh --task 2099-01-02-disp --worker codex --here --pane w8Z:pY 2>&1 )"; rc=$?
{ [[ "$rc" -ne 0 ]] && printf '%s' "$out" | grep -qi 'agent'; } \
  && ok "--pane 跑着 agent → 拒派（rc=${rc}）" || { bad "agent pane 竟放行（rc=${rc}）"; printf '%s\n' "$out"; }

echo "== 45. 主控返修：换主控不复用错误目标 / cwd预检不造资源 / 未确认不算成功 =="
# 场景（返修票 user_切换主控不能复用错误目标）：值守在跑但指向旧主控 → 拒绝给步骤，非0零副作用
ensreset
mk_plist "$DYN/pane-list.json" "w8Z:pZ@wtestW" "w93:p1,agent"
mk_get w8Z:pZ "$ENSP" "" wtestW; mk_proc w8Z:pZ wake "$ENSP" "wold:pA"
out="$(ensrun --ensure --pane wtest:ctl 2>&1)"; rc=$?
{ [[ "$rc" -ne 0 ]] && printf '%s' "$out" | grep -q 'wold:pA' && printf '%s' "$out" | grep -q 'wtest:ctl' \
   && ! grep -q 'tab create' "$STUBLOG" && ! grep -q 'pane run' "$STUBLOG"; } \
  && ok "值守指向旧主控 → 拒绝不复用+给修复步骤（rc=${rc}）" \
  || { bad "指向旧主控竟静默复用（rc=${rc}）"; printf '%s\n' "$out"; cat "$STUBLOG"; }
# 45a2 反转对照：同一 pane 值守指向本次要求的目标 → 正常复用
mk_proc w8Z:pZ wake "$ENSP" "wtest:ctl"
out="$(ensrun --ensure --pane wtest:ctl 2>&1)"; rc=$?
{ [[ "$rc" -eq 0 ]] && printf '%s' "$out" | grep -q '复用' && ! grep -q 'tab create' "$STUBLOG"; } \
  && ok "值守目标一致 → 正常复用（rc=${rc}）" || { bad "目标一致竟拒绝（rc=${rc}）"; printf '%s\n' "$out"; cat "$STUBLOG"; }
# 45b 负例：候选 pane 查询失败 → 不得忽略失败新开实例
ensreset
mk_plist "$DYN/pane-list.json" "w8Z:pQ" "w93:p1,agent"
printf '{"error":{"code":"io_error","message":"mocked proc failure"}}\n' > "$DYN/proc-$(wsan w8Z:pQ).err"
out="$(ensrun --ensure --pane wtest:ctl 2>&1)"; rc=$?
{ [[ "$rc" -ne 0 ]] && ! grep -q 'tab create' "$STUBLOG" && ! grep -q 'pane run' "$STUBLOG"; } \
  && ok "候选查询失败 → 拒绝不新开（rc=${rc}）" || { bad "查询失败竟新开实例（rc=${rc}）"; printf '%s\n' "$out"; cat "$STUBLOG"; }
# 45c 负例：启动命令投递了但进程始终不可确认 → 非0、不登记、不算成功
ensreset
mk_plist "$DYN/pane-list.json" "w93:p1,agent"
out="$( cd "$ENSP" && PATH="$STUB:$PATH" HERDR_WORKSPACE_ID=wtestW HERDR_PANE_ID=wtest:ctl \
    HERDR_DYN_DIR="$DYN" QWB_STUB_NOPROC=1 bash qwbuddy/bin/qwb-wake.sh --ensure --pane wtest:ctl 2>&1 )"; rc=$?
{ [[ "$rc" -ne 0 ]] && [[ ! -f "$ENSP/qwbuddy/.watch" ]] && grep -q 'pane run' "$STUBLOG"; } \
  && ok "投递后不可确认 → 非0且不登记（rc=${rc}）" || { bad "未确认竟报成功（rc=${rc}）"; printf '%s\n' "$out"; cat "$STUBLOG"; }
# 45d 负例：pane run 投递失败 → 非0
ensreset
mk_plist "$DYN/pane-list.json" "w93:p1,agent"
out="$( cd "$ENSP" && PATH="$STUB:$PATH" HERDR_WORKSPACE_ID=wtestW HERDR_PANE_ID=wtest:ctl \
    HERDR_DYN_DIR="$DYN" HERDR_FAIL=run bash qwbuddy/bin/qwb-wake.sh --ensure --pane wtest:ctl 2>&1 )"; rc=$?
{ [[ "$rc" -ne 0 ]] && [[ ! -f "$ENSP/qwbuddy/.watch" ]]; } \
  && ok "投递失败 → 非0（rc=${rc}）" || { bad "投递失败竟成功（rc=${rc}）"; printf '%s\n' "$out"; cat "$STUBLOG"; }
# 45e 反转：cwd 预检必须早于 worktree 创建——默认派发目标=.worktrees/<id>，pane cwd=项目根 → 拒绝且不建目录/分支/改动任务书
SGP="$SG3/tasks/2099-01-62-sgpwt.md"
cat > "$SGP" <<'EOF'
# sgpwt
state: running

## 1. 验收场景

### user_正常
Given pane cwd 与目标一致
When  派发
Then  放行
### user_失败
Given pane cwd 与目标 worktree 不符
When  派发
Then  在创建任何资源之前拒绝
EOF
rm -rf "$SG3/qwbuddy/.controller.lock"
SG3P="$(cd "$SG3" && pwd -P)"
mk_plist "$DYN/pane-list.json" "w8Z:pY"; mk_get w8Z:pY "$SG3P"; mk_proc w8Z:pY shell "$SG3P"
sha_before="$(shasum "$SGP" | cut -d' ' -f1)"; : > "$STUBLOG"
out="$(sgrun --task sgpwt --worker codex --pane w8Z:pY 2>&1)"; rc=$?
{ [[ "$rc" -ne 0 ]] && printf '%s' "$out" | grep -q 'cwd' \
   && [[ ! -e "$SG3/.worktrees/sgpwt" ]] \
   && ! git -C "$SG3" show-ref --verify --quiet "refs/heads/sgpwt" \
   && ! grep -q 'tab create\|agent start' "$STUBLOG" \
   && [[ "$(shasum "$SGP" | cut -d' ' -f1)" == "$sha_before" ]] \
   && ! grep -q '^dispatch:' "$SGP"; } \
  && ok "--pane cwd 不符（默认worktree未建）→ 拒绝且零资源零改动（rc=${rc}）" \
  || { bad "cwd 预检发生在副作用之后或放行（rc=${rc}）"; printf '%s\n' "$out"; }
# 45f 反转：预检也必须早于显式修订写——场景已改+坏 pane → 拒绝且不留 scenarios-revised 记录
sed -i '' 's/Then  复用隔离副本/Then  再改措辞/' "$SGI"
fp_before="$(sed -n 's/^scenarios-fp:[[:space:]]*//p' "$SGI" | head -1)"
rev_before="$(grep -c 'scenarios-revised:' "$SGI")"
out="$(sgrun --task sgidem --worker codex --pane w8Z:pY --revise-scenarios="测试：预检应先于修订写" 2>&1)"; rc=$?
{ [[ "$rc" -ne 0 ]] && [[ "$(grep -c 'scenarios-revised:' "$SGI")" == "$rev_before" ]] \
   && [[ "$(sed -n 's/^scenarios-fp:[[:space:]]*//p' "$SGI" | head -1)" == "$fp_before" ]]; } \
  && ok "--pane 预检失败 → 修订写也被拦下（rc=${rc}）" || { bad "预检晚于修订写（rc=${rc}）"; printf '%s\n' "$out"; }

echo "== 46. 第二轮返修：workspace 边界 / 混合不确定态 / 中断清锁 =="
# 46a 负例：一个活实例 + 一个查询失败候选 → ensure 必须先判未知拒绝，不能抢复用成功
ensreset
mk_plist "$DYN/pane-list.json" "w8Z:pZ" "w8Z:pQ"
mk_get w8Z:pZ "$ENSP" "" wtestW; mk_proc w8Z:pZ wake "$ENSP" "wtest:ctl"
printf '{"error":{"code":"io_error","message":"mocked proc failure"}}\n' > "$DYN/proc-$(wsan w8Z:pQ).err"
out="$(ensrun --ensure --pane wtest:ctl 2>&1)"; rc=$?
{ [[ "$rc" -ne 0 ]] && printf '%s' "$out" | grep -qi '无法排除\|未知' \
   && ! grep -q 'tab create' "$STUBLOG" && ! grep -q 'pane run' "$STUBLOG" \
   && ! printf '%s' "$out" | grep -q '复用已'; } \
  && ok "活实例+查询失败 → ensure 拒绝（不抢先复用，rc=${rc}）" \
  || { bad "混合不确定态竟报成功（rc=${rc}）"; printf '%s\n' "$out"; cat "$STUBLOG"; }
# 46a2 同一布局下 status 必须明确未知，不保证单实例
out="$(statrun)"
{ printf '%s' "$out" | grep -q '值守：未知' && printf '%s' "$out" | grep -q 'w8Z:pZ'; } \
  && ok "活实例+查询失败 → status 明确未知不保证单实例" || { bad "混合态 status 误报（输出见上）"; printf '%s\n' "$out"; }
# 46b 正例反转：活实例目标一致且无查询失败 → 仍正常复用
rm -f "$DYN/proc-$(wsan w8Z:pQ).err"; mk_proc w8Z:pQ shell "$ENSP"
out="$(ensrun --ensure --pane wtest:ctl 2>&1)"; rc=$?
{ [[ "$rc" -eq 0 ]] && printf '%s' "$out" | grep -q '复用'; } \
  && ok "无查询失败 → 正常复用（rc=${rc}）" || { bad "无失败竟拒绝（rc=${rc}）"; printf '%s\n' "$out"; cat "$STUBLOG"; }
# 46c 真实 SIGTERM：持锁期间被 TERM → 锁清、退出码非0、下一次 ensure 可用
ensreset
mk_plist "$DYN/pane-list.json" "w93:p1,agent"
( cd "$ENSP" && PATH="$STUB:$PATH" HERDR_WORKSPACE_ID=wtestW HERDR_PANE_ID=wtest:ctl \
    HERDR_DYN_DIR="$DYN" QWB_STUB_SLOW_LIST=1 exec bash qwbuddy/bin/qwb-wake.sh --ensure --pane wtest:ctl ) &
termpid=$!
for _ in 1 2 3 4 5 6 7 8 9 10; do [[ -d "$ENSP/qwbuddy/.watch.lock" ]] && break; sleep 0.2; done
[[ -d "$ENSP/qwbuddy/.watch.lock" ]] || bad "慢 list 期间未见 .watch.lock（信号时序没锁住）"
kill -TERM "$termpid" 2>/dev/null; wait "$termpid"; rc=$?
{ [[ "$rc" -ne 0 ]] && [[ ! -d "$ENSP/qwbuddy/.watch.lock" ]]; } \
  && ok "真实 SIGTERM → 锁已清且非0（rc=${rc}）" || { bad "TERM 后锁残留（rc=${rc}）"; ls -la "$ENSP/qwbuddy/"; }
out="$(ensrun --ensure --pane wtest:ctl 2>&1)"; rc=$?
{ [[ "$rc" -eq 0 ]] && [[ ! -d "$ENSP/qwbuddy/.watch.lock" ]]; } \
  && ok "TERM 后下一次 ensure 正常可用（rc=${rc}）" || { bad "TERM 后续跑失败（rc=${rc}）"; printf '%s\n' "$out"; cat "$STUBLOG"; }
# 46d 负例：目标主控 pane 不存在 → 获锁前拒绝，零副作用（无锁/无登记/无 herdr 动作）
ensreset
rm -f "$DYN/get-$(wsan wtest:ctl).json"
out="$(ensrun --ensure --pane wtest:ctl 2>&1)"; rc=$?
{ [[ "$rc" -ne 0 ]] && printf '%s' "$out" | grep -q '不存在' \
   && ! grep -q 'tab create' "$STUBLOG" && ! grep -q 'pane run' "$STUBLOG" \
   && ! grep -q 'pane list' "$STUBLOG" \
   && [[ ! -f "$ENSP/qwbuddy/.watch" ]] && [[ ! -d "$ENSP/qwbuddy/.watch.lock" ]]; } \
  && ok "目标 pane 不存在 → 拒绝零副作用（rc=${rc}）" \
  || { bad "目标 pane 不存在竟执行（rc=${rc}）"; printf '%s\n' "$out"; cat "$STUBLOG"; }
# 46e 负例：目标主控 pane 在别的 workspace → 拒绝，零副作用
ensreset
mk_get wtest:ctl "$ENSP" "" w8Z   # 目标 pane 属 w8Z，调用者 ws=wtestW
mk_plist "$DYN/pane-list.json" "w93:p1,agent"
out="$(ensrun --ensure --pane wtest:ctl 2>&1)"; rc=$?
{ [[ "$rc" -ne 0 ]] && printf '%s' "$out" | grep -q 'w8Z' \
   && ! grep -q 'tab create' "$STUBLOG" && ! grep -q 'pane run' "$STUBLOG" \
   && [[ ! -f "$ENSP/qwbuddy/.watch" ]]; } \
  && ok "目标 pane 异 workspace → 拒绝零副作用（rc=${rc}）" \
  || { bad "目标 pane 异 workspace 竟执行（rc=${rc}）"; printf '%s\n' "$out"; cat "$STUBLOG"; }
# 46f 对照：目标 pane 存在且同 workspace → 正常建
ensreset
mk_plist "$DYN/pane-list.json" "w93:p1,agent"
out="$(ensrun --ensure --pane wtest:ctl 2>&1)"; rc=$?
{ [[ "$rc" -eq 0 ]] && grep -q 'tab create' "$STUBLOG" && grep -q 'pane=' "$ENSP/qwbuddy/.watch"; } \
  && ok "目标 pane 同 workspace → 正常建（rc=${rc}）" || { bad "同 ws 目标竟拒绝（rc=${rc}）"; printf '%s\n' "$out"; cat "$STUBLOG"; }

echo "== 47. worker launch modes：herdr 默认 / pane-run（cmd 与 zcode）=="
assert_file "$ROOT/tests/fixtures/herdr/agent-get-cmd.json"
assert_file "$ROOT/tests/fixtures/herdr/agent-get-error.json"
LM="$TMP/launch-modes"; mkdir -p "$LM"; bash "$ROOT/bin/qwb-init.sh" "$LM" >/dev/null
printf '%s\n' 'QWB_WORKERS="codex cmd zcode"' 'QWB_AGENT_START_MS=300' >> "$LM/qwbuddy/config.sh"

mk_launch_task() {
  local id="$1"
  cat > "$LM/tasks/2099-02-01-${id}.md" <<EOF
# ${id}
state: blocked

## 1. 验收场景

### user_正常
Given 任务与工人配置合法
When 主控派发
Then 工人在最终 pane 收到提示词

### user_失败
Given 启动方式非法或检测超时
When 主控派发
Then 拒绝或失败且不发送提示词
EOF
}

LMNOW="$TMP/launch-now"; LMSLEEP="$TMP/launch-sleep.log"
cat > "$TMP/launch-now.sh" <<EOF
#!/usr/bin/env bash
cat "$LMNOW"
EOF
cat > "$TMP/launch-sleep.sh" <<EOF
#!/usr/bin/env bash
echo "\$1" >> "$LMSLEEP"
echo \$(( \$(cat "$LMNOW") + \$1 )) > "$LMNOW"
EOF
chmod +x "$TMP/launch-now.sh" "$TMP/launch-sleep.sh"

# 47a pane-run：检测延迟两次后成功；顺序、寻址目标与 dispatch pane 均取 tab create 的 pane。
printf '%s\n' 'qwb_worker codex herdr' 'qwb_worker cmd pane-run cmd' 'qwb_worker zcode herdr' > "$LM/qwbuddy/workers.sh"
mk_launch_task paneok
: > "$STUBLOG"; echo 0 > "$TMP/herdr-agent-get.count"; echo 0 > "$LMNOW"; : > "$LMSLEEP"
out="$(cd "$LM" && PATH="$STUB:$PATH" HERDR_PANE_ID=wtest:lm HERDR_FAIL=wait HERDR_AGENT_GET_FAILS=2 \
  HERDR_AGENT_GET_COUNT_FILE="$TMP/herdr-agent-get.count" QWB_NOW_MS_CMD="$TMP/launch-now.sh" \
  QWB_SLEEP_CMD="$TMP/launch-sleep.sh" bash qwbuddy/bin/qwb-run.sh --task paneok --worker cmd --here --name qwb-disp 2>&1)"; rc=$?
[[ "$rc" -eq 0 ]] && ok "pane-run 检测延迟后派发成功" || { bad "pane-run 成功路径 rc=${rc}"; printf '%s\n' "$out"; }
calls="$(cat "$STUBLOG")"
{ [[ "$(grep -c 'agent get w93:p7' "$STUBLOG" || true)" -ge 3 ]] \
   && grep -q "pane run w93:p7 'cmd'" "$STUBLOG" \
   && grep -q 'agent rename w93:p7 qwb-disp' "$STUBLOG" \
   && grep -q "pane run w93:p7 你是本任务的执行者。唯一规格来源：$LM/tasks/2099-02-01-paneok.md" "$STUBLOG" \
   && grep -q '写完状态行再收工' "$STUBLOG" \
   && grep -q 'agent wait w93:p7 --until working --until done --until blocked --timeout 300' "$STUBLOG" \
   && grep -q 'pane send-keys w93:p7 enter' "$STUBLOG" \
   && ! grep -q 'agent start' "$STUBLOG" && ! grep -q 'agent prompt' "$STUBLOG"; } \
  && ok "pane-run 直打后无状态转换会补 Enter，且不走 agent start/prompt" \
  || { bad "pane-run 调用序列不完整"; printf '%s\n' "$calls"; }
tabln="$(grep -n 'tab create' "$STUBLOG" | head -1 | cut -d: -f1)"
runln="$(grep -n "pane run w93:p7 'cmd'" "$STUBLOG" | head -1 | cut -d: -f1)"
getln="$(grep -n 'agent get w93:p7' "$STUBLOG" | head -1 | cut -d: -f1)"
renln="$(grep -n 'agent rename w93:p7 qwb-disp' "$STUBLOG" | head -1 | cut -d: -f1)"
prmln="$(grep -n 'pane run w93:p7 你是本任务的执行者' "$STUBLOG" | head -1 | cut -d: -f1)"
[[ "$tabln" -lt "$runln" && "$runln" -lt "$getln" && "$getln" -lt "$renln" && "$renln" -lt "$prmln" ]] \
  && ok "pane-run 调用顺序为 tab→run→get→rename→pane run 提示词" || bad "pane-run 调用顺序错误"
grep -q '^dispatch: .* worker=cmd agent=qwb-disp pane=w93:p7 ' "$LM/tasks/2099-02-01-paneok.md" \
  && ok "pane-run dispatch 记录最终 pane" || bad "pane-run dispatch 内容错误"

# 47b pane-run：假时钟推进到 300ms 仍未检测到 agent，本次 dispatch 原位标为 not-sent 并记 blocked，不发送 prompt。
mk_launch_task panetimeout
: > "$STUBLOG"; echo 0 > "$TMP/herdr-agent-get.count"; echo 0 > "$LMNOW"; : > "$LMSLEEP"
out="$(cd "$LM" && PATH="$STUB:$PATH" HERDR_PANE_ID=wtest:lm HERDR_AGENT_GET_FAILS=99 \
  HERDR_AGENT_GET_COUNT_FILE="$TMP/herdr-agent-get.count" QWB_NOW_MS_CMD="$TMP/launch-now.sh" \
  QWB_SLEEP_CMD="$TMP/launch-sleep.sh" bash qwbuddy/bin/qwb-run.sh --task panetimeout --worker cmd --here 2>&1)"; rc=$?
{ [[ "$rc" -ne 0 ]] && printf '%s' "$out" | grep -q 'pane-run 工人检测' \
   && printf '%s' "$out" | grep -q '超时（300ms）' && printf '%s' "$out" | grep -q 'pane=w93:p7' \
   && printf '%s' "$out" | grep -q '查 herdr pane read / process-info / agent get'; } \
  && ok "pane-run 300ms 检测超时给出 pane 与排查命令" || { bad "pane-run 超时输出不对（rc=${rc}）"; printf '%s\n' "$out"; }
[[ "$(cat "$LMNOW")" -eq 300 ]] && ok "pane-run 超时由假时钟精确推进 300ms" || bad "pane-run 假时钟未停在 300ms"
{ grep -q '^not-sent: .* worker=cmd .* pane=w93:p7 ' "$LM/tasks/2099-02-01-panetimeout.md" \
   && grep -q '^blocked: .*step=pane-run 工人检测 rc=1 pane=w93:p7' "$LM/tasks/2099-02-01-panetimeout.md" \
   && ! grep -q '^dispatch:' "$LM/tasks/2099-02-01-panetimeout.md" \
   && grep -q '^herdr tab close w93:t7' "$STUBLOG"; } \
  && ok "pane-run 超时原位标记 not-sent、记录 blocked 并关闭新 tab" || bad "pane-run 超时失败记账或清理不对"
[[ "$(grep -c 'pane run w93:p7' "$STUBLOG" || true)" -eq 1 ]] \
  && ok "pane-run 超时后无第二次 pane run（未发提示词）" || bad "pane-run 超时后仍发送提示词"

# 47c 非法方式在锁/窗口/账本之前拒绝。
printf '%s\n' 'qwb_worker codex herdr' 'qwb_worker cmd teleport' 'qwb_worker zcode herdr' > "$LM/qwbuddy/workers.sh"
mk_launch_task badmode
rm -rf "$LM/qwbuddy/.controller.lock"; : > "$STUBLOG"
out="$(cd "$LM" && PATH="$STUB:$PATH" HERDR_PANE_ID=wtest:lm bash qwbuddy/bin/qwb-run.sh --task badmode --worker cmd --here 2>&1)"; rc=$?
{ [[ "$rc" -ne 0 ]] && printf '%s' "$out" | grep -q 'herdr' && printf '%s' "$out" | grep -q 'pane-run' \
   && ! printf '%s' "$out" | grep -q 'zcodecli-chat' && [[ ! -s "$STUBLOG" ]] \
   && [[ ! -d "$LM/qwbuddy/.controller.lock" ]] && ! grep -q '^dispatch:' "$LM/tasks/2099-02-01-badmode.md"; } \
  && ok "非法启动方式在全部副作用前拒绝并列出合法方式" || { bad "非法启动方式拒绝不完整（rc=${rc}）"; printf '%s\n' "$out"; }

printf '%s\n' 'qwb_worker codex herdr' 'qwb_worker cmd pane-run cmd -p' 'qwb_worker zcode herdr' > "$LM/qwbuddy/workers.sh"
mk_launch_task headless
rm -rf "$LM/qwbuddy/.controller.lock"; : > "$STUBLOG"
out="$(cd "$LM" && PATH="$STUB:$PATH" HERDR_PANE_ID=wtest:lm bash qwbuddy/bin/qwb-run.sh --task headless --worker cmd --here 2>&1)"; rc=$?
{ [[ "$rc" -ne 0 ]] && printf '%s' "$out" | grep -q 'headless' && [[ ! -s "$STUBLOG" ]] \
   && ! grep -q '^dispatch:' "$LM/tasks/2099-02-01-headless.md"; } \
  && ok "pane-run 拒绝 -p 等 headless 命令且零副作用" \
  || { bad "pane-run headless 禁令未生效（rc=${rc}）"; printf '%s\n' "$out"; }

# 47d 值含空格：按下一个「工人名=」切分，zcode 启动命令保持完整的 zcodecli chat。
printf '%s\n' 'qwb_worker codex herdr' 'qwb_worker cmd pane-run cmd' 'qwb_worker zcode pane-run zcodecli chat' > "$LM/qwbuddy/workers.sh"
mk_launch_task zspace
rm -rf "$LM/qwbuddy/.controller.lock"; : > "$STUBLOG"; echo 0 > "$TMP/herdr-agent-get.count"
out="$(cd "$LM" && PATH="$STUB:$PATH" HERDR_PANE_ID=wtest:lm HERDR_AGENT_GET_FAILS=1 \
  HERDR_AGENT_GET_COUNT_FILE="$TMP/herdr-agent-get.count" QWB_NOW_MS_CMD="$TMP/launch-now.sh" \
  QWB_SLEEP_CMD="$TMP/launch-sleep.sh" bash qwbuddy/bin/qwb-run.sh --task zspace --worker zcode --here --name qwb-disp 2>&1)"; rc=$?
[[ "$rc" -eq 0 ]] && ok "含空格的 zcode pane-run 派发成功" || { bad "zcode 空格命令 rc=${rc}"; printf '%s\n' "$out"; }
{ grep -qxF "herdr pane run w93:p7 'zcodecli' 'chat'" "$STUBLOG" \
   && grep -q "pane run w93:p7 你是本任务的执行者。唯一规格来源：$LM/tasks/2099-02-01-zspace.md" "$STUBLOG" \
   && grep -q 'agent wait w93:p7 --until working --until done --until blocked --timeout 300' "$STUBLOG" \
   && ! grep -q 'pane send-keys w93:p7 enter' "$STUBLOG" \
   && ! grep -q 'agent start' "$STUBLOG" && ! grep -q 'agent prompt' "$STUBLOG"; } \
  && ok "zcode pane-run 保留整条命令并在状态已转换时不补 Enter" \
  || { bad "zcode 空格命令被截断或走错提示词入口"; cat "$STUBLOG"; }
grep -q '^dispatch: .* worker=zcode agent=qwb-disp pane=w93:p7 ' "$LM/tasks/2099-02-01-zspace.md" \
  && ok "zcode pane-run dispatch 记录最终 pane" || bad "zcode pane-run dispatch 内容错误"

echo "== 48. F：工人 tab 落在项目 workspace（QWB_WORKSPACE 三级解析 + --ensure 同款）=="
# 场景（票 §1）：显式声明优先｜声明了但 herdr 查不到即拒绝（任何副作用之前）｜未声明按 worktree.repo_root 匹配｜
#   未声明且无匹配回退调用者 workspace 并警告｜多匹配取 focused（都不 focused 取第一个+警告）｜--ensure 同款｜
#   workspace list 查询失败即拒绝｜响应不合契约即拒绝。workspace list 应答取自真录 workspace-list.json。
WSJ="$TMP/wsproj"; mkdir -p "$WSJ"; bash "$ROOT/bin/qwb-init.sh" "$WSJ" >/dev/null
printf 'QWB_GATE_FAST="true"\nQWB_GATE_FULL="true"\n' >> "$WSJ/qwbuddy/config.sh"
WSDYN="$TMP/ws-dyn"; mkdir -p "$WSDYN"
WSERR="$TMP/ws-err.log"; WST="$WSJ/tasks/2099-03-01-"

mk_ws_task() { # $1=任务 id（唯一；避免互为前缀，--task 是按 id 模糊匹配的）
  cat > "${WST}$1.md" <<EOF
# $1
state: blocked

## 1. 验收场景

### user_正常
Given 任务书与配置合法
When  主控派发
Then  工人 tab 落在解析出的 workspace

### user_失败
Given QWB_WORKSPACE 声明了本机不存在的 id
When  主控派发
Then  在任何副作用之前拒绝
EOF
}
# 以真录 workspace-list.json 为底稿改 repo_root 指向（其余字段原样）：
#   one            = 只有 focused 的那个 workspace 指向本项目（另一个去掉 worktree，验证不误匹配）
#   multi          = 带 worktree 的两个都指向本项目（其中 focused 的是 w8Z）
#   multi-nofocus  = 同上但都不 focused（验证「取第一个 + 警告」）
mk_wslist() { # $1=one|multi|multi-nofocus $2=本项目根路径（故意给未归一化的真路径）
  perl -MJSON::PP=decode_json,encode_json -e '
    my ($mode, $root, $src) = @ARGV;
    open my $fh, "<", $src or die "读真录失败: $!";
    my $raw = do { local $/; <$fh> }; close $fh;
    $raw =~ s/^#.*\n//mg;
    my $j = decode_json($raw);
    my $n = 0;
    for my $w (@{ $j->{result}{workspaces} }) {
      next unless ref $w->{worktree} eq "HASH";
      $n++;
      if ($mode eq "one") {
        if ($w->{focused}) { $w->{worktree}{repo_root} = $root }
        else { delete $w->{worktree} }
      } else {
        $w->{worktree}{repo_root} = $root;
        if ($mode eq "multi-nofocus") { $w->{focused} = $JSON::PP::false }
      }
    }
    die "真录里没有带 worktree 的 workspace，无法构造场景\n" if $n == 0;
    print encode_json($j), "\n";
  ' "$1" "$2" "$FIXDIR/workspace-list.json" > "$WSDYN/workspace-list.json"
}
wsrun_in() { # $1=派发目录 $2=任务 id，其余=额外参数；调用者自行重定向输出
  local d="$1" t="$2"; shift 2
  ( cd "$d" && PATH="$STUB:$PATH" HERDR_DYN_DIR="$WSDYN" HERDR_PANE_ID=wtest:ws HERDR_WORKSPACE_ID="${WS_CALLER:-wY}" \
      bash qwbuddy/bin/qwb-run.sh --task "$t" --worker codex --here "$@" )
}
wsrun() { wsrun_in "$WSJ" "$@"; }
ws_clean() { # $1=任务 id：断言拒绝路径零副作用（无 tab/agent/账本写/锁，state 未动）
  local f="${WST}$1.md"
  grep -q 'tab create' "$STUBLOG" && return 1
  grep -q 'agent start' "$STUBLOG" && return 1
  grep -q '^dispatch:' "$f" && return 1
  grep -q '^scenarios-fp:' "$f" && return 1
  grep -q '^state: blocked' "$f" || return 1
  [[ -d "$WSJ/qwbuddy/.controller.lock" ]] && return 1
  return 0
}
ws_set_ws() { # $1=QWB_WORKSPACE 的值（空 = 删掉该键，即未声明）
  sed -i '' '/^QWB_WORKSPACE=/d' "$WSJ/qwbuddy/config.sh"
  [[ -n "$1" ]] && printf 'QWB_WORKSPACE="%s"\n' "$1" >> "$WSJ/qwbuddy/config.sh"
  return 0
}

# 48a 显式声明优先：QWB_WORKSPACE=wA3 存在，调用者在 wY → tab 落 wA3，无警告
mk_ws_task wsAdecl; ws_set_ws wA3
: > "$STUBLOG"; : > "$WSERR"; rm -rf "$WSJ/qwbuddy/.controller.lock"
wsrun wsAdecl >/dev/null 2>"$WSERR"; rc=$?
{ [[ "$rc" -eq 0 ]] && grep -q 'tab create --workspace wA3' "$STUBLOG" && [[ ! -s "$WSERR" ]]; } \
  && ok "显式 QWB_WORKSPACE=wA3 → tab create --workspace wA3 且 stderr 无警告（rc=${rc}）" \
  || { bad "显式声明未生效（rc=${rc}）"; printf 'stderr: '; cat "$WSERR"; }

# 48b 声明了但查不到 → 在任何副作用之前拒绝（失败路径）
mk_ws_task wsBmiss; ws_set_ws wZ
rm -rf "$WSJ/qwbuddy/.controller.lock"; : > "$STUBLOG"; : > "$WSERR"
wsrun wsBmiss >/dev/null 2>"$WSERR"; rc=$?
{ [[ "$rc" -ne 0 ]] && grep -q 'wZ' "$WSERR" && grep -q 'QWB_WORKSPACE' "$WSERR" && ws_clean wsBmiss; } \
  && ok "QWB_WORKSPACE=wZ 不存在 → 拒绝且零副作用（rc=${rc}）" \
  || { bad "不存在的声明未被拒或留了副作用（rc=${rc}）"; printf 'stderr: '; cat "$WSERR"; }

# 48c 未声明：按 worktree.repo_root 匹配（项目根经符号链接 → 必须归一成物理路径才匹配得上）
mk_ws_task wsCmatch; ws_set_ws ""
ln -sfn "$WSJ" "$TMP/wslink"
mk_wslist one "$WSJ"            # 真录底稿里 focused 的 w8Z 指向本项目（路径未归一）
: > "$STUBLOG"; : > "$WSERR"; rm -rf "$WSJ/qwbuddy/.controller.lock"
wsrun_in "$TMP/wslink" wsCmatch >/dev/null 2>"$WSERR"; rc=$?
{ [[ "$rc" -eq 0 ]] && grep -q 'tab create --workspace w8Z' "$STUBLOG" \
   && ! grep -q 'tab create.*--workspace wY' "$STUBLOG" && [[ ! -s "$WSERR" ]]; } \
  && ok "未声明 → 按 repo_root 匹配到 w8Z（/var 与 /private/var 符号链接差异被归一）" \
  || { bad "repo_root 匹配失败（rc=${rc}）"; printf 'stderr: '; cat "$WSERR"; }

# 48d 未声明且无匹配 → 回退调用者 workspace + 恰一行警告；退出码 0
mk_ws_task wsDfall
rm -f "$WSDYN/workspace-list.json"   # 回退真录原样：没有任何 workspace 指向本项目
: > "$STUBLOG"; : > "$WSERR"; rm -rf "$WSJ/qwbuddy/.controller.lock"
WS_CALLER=wY wsrun wsDfall >/dev/null 2>"$WSERR"; rc=$?
{ [[ "$rc" -eq 0 ]] && [[ "$(grep -c '未声明 QWB_WORKSPACE' "$WSERR")" == "1" ]] \
   && grep -q '未声明 QWB_WORKSPACE' "$WSERR" && grep -q 'wY' "$WSERR" \
   && grep -q '^dispatch:' "${WST}wsDfall.md" \
   && ! grep -q 'tab create.*--workspace' "$STUBLOG"; } \
  && ok "无匹配 → 落调用者 workspace wY 且恰一行「未声明 QWB_WORKSPACE」警告（rc=${rc}）" \
  || { bad "回退路径不对（rc=${rc}）"; printf 'stderr: '; cat "$WSERR"; }

# 48e linked 任务 Space 不参与主 workspace 匹配，即使用户聚焦它或没有任何焦点。
mk_ws_task wsEmulti; mk_wslist multi "$WSJ"
: > "$STUBLOG"; : > "$WSERR"; rm -rf "$WSJ/qwbuddy/.controller.lock"
wsrun wsEmulti >/dev/null 2>"$WSERR"; rc=$?
{ [[ "$rc" -eq 0 ]] && grep -q 'tab create --workspace w8Z' "$STUBLOG" && [[ ! -s "$WSERR" ]]; } \
  && ok "两项 repo_root 都匹配 → 取 focused 的 w8Z 且无警告" \
  || { bad "多匹配未取 focused（rc=${rc}）"; printf 'stderr: '; cat "$WSERR"; }
mk_ws_task wsFnofocus; mk_wslist multi-nofocus "$WSJ"
: > "$STUBLOG"; : > "$WSERR"; rm -rf "$WSJ/qwbuddy/.controller.lock"
wsrun wsFnofocus >/dev/null 2>"$WSERR"; rc=$?
{ [[ "$rc" -eq 0 ]] && grep -q 'tab create --workspace w8Z' "$STUBLOG" \
   && ! grep -q '多个 workspace 匹配' "$WSERR"; } \
  && ok "任务 linked Space 不影响主 workspace 解析" \
  || { bad "都不 focused 时的兜底不对（rc=${rc}）"; printf 'stderr: '; cat "$WSERR"; }

# 48f workspace list 查询失败 → 拒绝并带出原始错误（失败路径，零副作用）
mk_ws_task wsGfail
rm -f "$WSDYN/workspace-list.json"; : > "$STUBLOG"; : > "$WSERR"; rm -rf "$WSJ/qwbuddy/.controller.lock"
( cd "$WSJ" && PATH="$STUB:$PATH" HERDR_DYN_DIR="$WSDYN" HERDR_FAIL=wslist HERDR_PANE_ID=wtest:ws \
    HERDR_WORKSPACE_ID=wY bash qwbuddy/bin/qwb-run.sh --task wsGfail --worker codex --here ) >/dev/null 2>"$WSERR"; rc=$?
{ [[ "$rc" -ne 0 ]] && grep -q 'mocked workspace list failure' "$WSERR" && ws_clean wsGfail; } \
  && ok "workspace list 查询失败 → 拒绝且 stderr 含原始错误、零副作用（rc=${rc}）" \
  || { bad "查询失败路径不对（rc=${rc}）"; printf 'stderr: '; cat "$WSERR"; }

# 48f2 响应不合契约（workspace_id 为对象）→ 拒绝（R2-M2：运行时边界也拦）
mk_ws_task wsHbad
perl -MJSON::PP=decode_json,encode_json -e '
  open my $fh, "<", $ARGV[0] or die;
  my $raw = do { local $/; <$fh> }; close $fh; $raw =~ s/^#.*\n//mg;
  my $j = decode_json($raw);
  $j->{result}{workspaces}[0]{workspace_id} = { bad => 1 };
  print encode_json($j), "\n";
' "$FIXDIR/workspace-list.json" > "$WSDYN/workspace-list.json"
: > "$STUBLOG"; : > "$WSERR"; rm -rf "$WSJ/qwbuddy/.controller.lock"
wsrun wsHbad >/dev/null 2>"$WSERR"; rc=$?
{ [[ "$rc" -ne 0 ]] && grep -q '契约' "$WSERR" && ws_clean wsHbad; } \
  && ok "workspace_id 为对象（错型）→ 拒绝且零副作用（rc=${rc}）" \
  || { bad "错型响应未被拦（rc=${rc}）"; printf 'stderr: '; cat "$WSERR"; }

# 48g --ensure 同款：建 tab 带 --workspace、.watch 记该 workspace
printf 'QWB_WORKSPACE="wA3"\n' >> "$ENSP/qwbuddy/config.sh"   # 调用者是 wtestW，声明的是 wA3
ensreset; mk_plist "$DYN/pane-list.json" "w93:p1,agent"
out="$(ensrun --ensure --pane wtest:ctl 2>&1)"; rc=$?
{ [[ "$rc" -eq 0 ]] && grep -q 'tab create --workspace wA3' "$STUBLOG" \
   && grep -q 'workspace=wA3' "$ENSP/qwbuddy/.watch" && ! printf '%s' "$out" | grep -q '未声明 QWB_WORKSPACE'; } \
  && ok "--ensure 建 tab 带 --workspace wA3，.watch 记 workspace=wA3（rc=${rc}）" \
  || { bad "--ensure 未用项目 workspace（rc=${rc}）"; printf '%s\n' "$out"; cat "$ENSP/qwbuddy/.watch" 2>/dev/null; }
# 48g2 负例：ensure 声明的 workspace 不存在 → 拒绝，不建 tab、不登记
sed -i '' 's/^QWB_WORKSPACE=.*/QWB_WORKSPACE="wZ"/' "$ENSP/qwbuddy/config.sh"
ensreset; mk_plist "$DYN/pane-list.json" "w93:p1,agent"
out="$(ensrun --ensure --pane wtest:ctl 2>&1)"; rc=$?
{ [[ "$rc" -ne 0 ]] && ! grep -q 'tab create' "$STUBLOG" && [[ ! -f "$ENSP/qwbuddy/.watch" ]] \
   && ! grep -q 'pane run' "$STUBLOG"; } \
  && ok "--ensure 声明的 wZ 不存在 → 拒绝且不建 tab 不登记（rc=${rc}）" \
  || { bad "ensure 未校验声明的 workspace（rc=${rc}）"; printf '%s\n' "$out"; }
sed -i '' '/^QWB_WORKSPACE=/d' "$ENSP/qwbuddy/config.sh"

echo "== 49. JEV 自动派工（qwb-dispatch.sh：off/clear/ambiguous/坏规则/响应校验/key 纪律 + qwb-run auto 集成）=="
bash "$ROOT/tests/optional-routing.sh" && ok "可选路由公开 CLI 结构化契约" || bad "可选路由公开 CLI 结构化契约"
# 假 curl 手法沿 firstmate tests/fm-dispatch-resolve.test.sh：记录 argv/请求体/fd3 头/子进程环境，
# 按 FAKE_CURL_* 应答。零网络、零真 key。
DT="$(mktemp -d)"
DFB="$DT/fakebin"; DLOG="$DT/log"
mkdir -p "$DFB" "$DLOG" "$DT/qwbuddy"
cat > "$DFB/curl" <<'FAKE'
#!/usr/bin/env bash
set -u
if [ -n "${TYPESAFE_API_KEY+x}" ]; then printf 'curl:secret-present\n' >> "${CHILD_ENV_LOG:?}"
else printf 'curl:clean\n' >> "${CHILD_ENV_LOG:?}"; fi
out=''
while [ $# -gt 0 ]; do
  case "$1" in
    -o) out=$2; shift 2 ;;
    *) printf '%s\n' "$1" >> "${FAKE_CURL_LOG:?}/argv"; shift ;;
  esac
done
cat > "${FAKE_CURL_LOG:?}/body"
cat /dev/fd/3 > "${FAKE_CURL_LOG:?}/header" 2>/dev/null || printf 'fd3 不可读\n' > "${FAKE_CURL_LOG:?}/header"
[ "${FAKE_CURL_FAIL:-0}" = 1 ] && exit 7
cp "${FAKE_CURL_RESPONSE:?}" "$out"
printf '%s' "${FAKE_CURL_HTTP:-200}"
FAKE
chmod +x "$DFB/curl"

cat > "$DT/qwbuddy/dispatch-rules.json" <<'JSON'
{
  "rules": [
    {"when": "复杂架构、跨模块重构、高风险改动", "worker": "codex"},
    {"when": "常规实现、机械改动、调研", "worker": "pi"},
    {"when": "代码审核、对抗性审查", "worker": "claude"}
  ],
  "default": {"worker": "pi"}
}
JSON
cat > "$DT/brief.md" <<'MD'
# 任务
跨模块重构 worker 解析层，高风险改动，需要架构判断。
MD
export FAKE_CURL_LOG="$DLOG" FAKE_CURL_RESPONSE="$DT/resp.json" CHILD_ENV_LOG="$DLOG/child-env"
DKEY='test-key-jev-port-never-on-argv'

dresp() { # <path> <choice> <confidence> —— 合法应答：winner 拿 conf，其余平分余量（和恰为 1）
  jq -n --arg c "$2" --argjson conf "$3" '
    (["rule_1","rule_2","rule_3","default"] | map(select(. != $c))) as $rest |
    ((1 - $conf) / ($rest | length)) as $share |
    {model: "jev-1.13.0",
     answers: {rule: {type: "choice", choice: $c, confidence: $conf,
       probabilities: (reduce $rest[] as $k ({}; .[$k] = $share) | .[$c] = $conf)}},
     usage: {input_tokens: 100, output_tokens: 20}}' > "$1"
}
dreset() { rm -rf "$DLOG"; mkdir -p "$DLOG"; }
drun() { # 可先设 DENV="VAR=值"（逐次覆盖）；结果在 D_OUT/D_ERR/D_RC；设 DKEY 则带环境 key
  D_ERR="$DT/stderr.txt"
  D_OUT="$(cd "$DT" && env -u TYPESAFE_API_KEY ${DKEY:+TYPESAFE_API_KEY=$DKEY} ${DENV:-} \
    PATH="$DFB:$PATH" bash "$ROOT/bin/qwb-dispatch.sh" "$@" 2>"$D_ERR")"; D_RC=$?
  DENV=''
}

# 49.1 off 门：无 key 无 .env → stderr 一行 off、exit 0、stdout 空、零网络（内联跑，不注入 key）
dreset
D_OUT="$(cd "$DT" && env -u TYPESAFE_API_KEY PATH="$DFB:$PATH" bash "$ROOT/bin/qwb-dispatch.sh" brief.md 2>"$DT/stderr.txt")"; D_RC=$?; D_ERR="$DT/stderr.txt"
{ [[ "$D_RC" -eq 0 ]] && [[ -z "$D_OUT" ]] && grep -q 'qwb-dispatch: off' "$D_ERR" && [[ ! -e "$DLOG/argv" ]]; } \
  && ok "off 门：exit 0、stdout 空、stderr 一行 off、零网络调用" \
  || { bad "off 门不对（rc=${D_RC}）"; printf 'out=[%s] err=[%s]\n' "$D_OUT" "$(cat "$D_ERR" 2>/dev/null)"; }

# 49.2 .env key → clear：worker 与规则一致；key 走 fd3 头不上 argv；模型看不到 worker/key
printf 'OTHER=1\nexport TYPESAFE_API_KEY="%s"\n' "$DKEY" > "$DT/.env"
dreset; dresp "$DT/resp.json" rule_1 0.94; drun brief.md
{ [[ "$D_RC" -eq 0 ]] && grep -q '^  status: clear' <<<"$D_OUT" && grep -q '^  worker: codex' <<<"$D_OUT" \
    && grep -q '复杂架构' <<<"$D_OUT" && grep -q 'confidence: 0.94' <<<"$D_OUT"; } \
  && ok ".env key 激活：rule_1 命中 → clear + worker codex（置信度 0.94）" \
  || { bad ".env clear 不对（rc=${D_RC}）"; printf '%s\n' "$D_OUT"; cat "$D_ERR"; }
grep -q "Authorization: Bearer $DKEY" "$DLOG/header" \
  && ok "key 经 fd3 头送达 curl" || bad "fd3 头缺 key"
argv="$(cat "$DLOG/argv")"
{ grep -q 'https://api.typesafe.ai/v1/systemone' <<<"$argv" && ! grep -q "$DKEY" <<<"$argv"; } \
  && ok "请求打固定端点；key 不在 argv" || bad "argv 检查失败"
body="$(cat "$DLOG/body")"
{ [[ "$(jq -r .model <<<"$body")" == 'jev-latest' ]] \
    && [[ "$(jq -r .state.task.project <<<"$body")" == "$(basename "$DT")" ]] \
    && grep -q '跨模块重构' <<<"$body" \
    && [[ "$(jq -c '.questions | keys' <<<"$body")" == '["rule"]' ]] \
    && [[ "$(jq -c '.questions.rule.criteria | keys | sort' <<<"$body")" == '["default","rule_1","rule_2","rule_3"]' ]]; } \
  && ok "请求体：jev-latest + project + brief 全文 + 单 choice 问题（rule_1..3 + default）" \
  || bad "请求体形状不对"
{ ! grep -q "$DKEY" <<<"$body" && ! grep -q 'codex' <<<"$body"; } \
  && ok "模型看不到 key 也看不到 worker 名" || bad "body 泄漏"
[[ "$(cat "$DLOG/child-env")" == 'curl:clean' ]] \
  && ok "key 不出现在子进程环境" || bad "子进程环境有 key（$(cat "$DLOG/child-env")）"
# 对照：环境变量 key 优先于 .env
D_OUT="$(cd "$DT" && TYPESAFE_API_KEY='env-wins-key' PATH="$DFB:$PATH" bash "$ROOT/bin/qwb-dispatch.sh" brief.md 2>/dev/null)"
grep -q 'Authorization: Bearer env-wins-key' "$DLOG/header" \
  && ok "环境变量 key 优先于 .env" || bad "env key 未生效"

# 49.3 ambiguous：confidence < 0.6 → ambiguous + probabilities 全文 + 无 worker 行
dreset; dresp "$DT/resp.json" rule_2 0.41; drun brief.md
{ [[ "$D_RC" -eq 0 ]] && grep -q '^  status: ambiguous' <<<"$D_OUT" \
    && grep -q '低于门槛 0.6' <<<"$D_OUT" \
    && grep -q 'rule_1=' <<<"$D_OUT" && grep -q 'rule_3=' <<<"$D_OUT" && grep -q 'default=' <<<"$D_OUT" \
    && ! grep -q '^  worker:' <<<"$D_OUT"; } \
  && ok "低置信度 → ambiguous + probabilities 全文，不出 worker 行" \
  || { bad "ambiguous 不对（rc=${D_RC}）"; printf '%s\n' "$D_OUT"; }

# 49.4 default：无规则命中 → clear + default worker
dreset; dresp "$DT/resp.json" default 0.94; drun brief.md
grep -q '^  worker: pi' <<<"$D_OUT" && grep -q 'rule: default' <<<"$D_OUT" \
  && ok "default 选项 → clear + default worker pi" || bad "default 不对：$(grep '^  status' <<<"$D_OUT")"

# 49.5 响应校验与网络错：全部 error + exit 0（派工流程不被卡死）
# rule_9 用例：probabilities 合法但 choice 不在选项集 → 落到解析层判 error
jq -n '{model:"jev-1.13.0",answers:{rule:{type:"choice",choice:"rule_9",confidence:0.94,
  probabilities:{rule_1:0.94,rule_2:0.02,rule_3:0.02,default:0.02}}},
  usage:{input_tokens:100,output_tokens:20}}' > "$DT/resp.json"
drun brief.md
{ [[ "$D_RC" -eq 0 ]] && grep -q '^  status: error' <<<"$D_OUT" && grep -q 'rule_9 不在规则文件里' <<<"$D_OUT"; } \
  && ok "未知选项 rule_9 → error（exit 0）" || { bad "rule_9 未判 error：$(grep '^  reason' <<<"$D_OUT")"; }
dresp_bad() { # <变换 jq 表达式> <期望 reason 片段> <用例名>
  dreset; dresp "$DT/resp.json" rule_1 0.94
  jq "$1" "$DT/resp.json" > "$DT/r2.json" && mv "$DT/r2.json" "$DT/resp.json"
  drun brief.md
  { [[ "$D_RC" -eq 0 ]] && grep -q '^  status: error' <<<"$D_OUT" && grep -q "$2" <<<"$D_OUT"; } \
    && ok "$3 → error（exit 0）" || { bad "$3 未判 error"; printf '%s\n' "$D_OUT"; }
}
dresp_bad '.answers.rule.probabilities |= del(.default)' 'rule Choice' 'probabilities 键不全'
dresp_bad '.answers.rule.probabilities = {rule_1:0.1,rule_2:0.1,rule_3:0.1,default:0.1}' 'rule Choice' 'probabilities 和≠1'
dresp_bad '.answers.rule.confidence = 2' 'rule Choice' 'confidence 越界'
dresp_bad '.usage = "bad"' 'rule Choice' 'usage 非对象'
dreset; dresp "$DT/resp.json" rule_1 0.94; DENV='FAKE_CURL_HTTP=500'; drun brief.md
{ [[ "$D_RC" -eq 0 ]] && grep -q 'http 500' <<<"$D_OUT"; } \
  && ok "HTTP 500 → error（exit 0）" || bad "http 500 未判 error"
dreset; dresp "$DT/resp.json" rule_1 0.94; DENV='FAKE_CURL_FAIL=1'; drun brief.md
grep -q 'http 000' <<<"$D_OUT" && ok "网络失败 → http 000 error" || bad "网络失败未判 error"

# 49.6 坏规则文件 → exit 2（配置错误不绕过）、不联网
dreset; printf '%s\n' '{"rules":[' > "$DT/qwbuddy/dispatch-rules.json"
drun brief.md
{ [[ "$D_RC" -eq 2 ]] && grep -q '不是合法 JSON' "$D_ERR" && [[ ! -e "$DLOG/argv" ]]; } \
  && ok "坏 JSON 规则 → exit 2 且零网络" || { bad "坏 JSON 未 exit 2（rc=${D_RC}）"; cat "$D_ERR"; }
printf '%s\n' '{"rules":[{"when":"x","worker":"has space"}],"default":{"worker":"pi"}}' > "$DT/qwbuddy/dispatch-rules.json"
drun brief.md
{ [[ "$D_RC" -eq 2 ]] && grep -q '合法 worker' "$D_ERR"; } \
  && ok "worker 含空格 → exit 2" || { bad "worker 空格未拒（rc=${D_RC}）"; cat "$D_ERR"; }
printf '%s\n' '{"rules":[{"when":"x","worker":"pi"}]}' > "$DT/qwbuddy/dispatch-rules.json"
drun brief.md
{ [[ "$D_RC" -eq 2 ]] && grep -q 'default' "$D_ERR"; } \
  && ok "缺 default → exit 2" || { bad "缺 default 未拒（rc=${D_RC}）"; cat "$D_ERR"; }

# 49.7 规则文件不存在 → exit 0、stderr 一行 no rules、零网络
dreset; mv "$DT/qwbuddy/dispatch-rules.json" "$DT/rules.bak"
drun brief.md
{ [[ "$D_RC" -eq 0 ]] && [[ -z "$D_OUT" ]] && grep -q 'no rules' "$D_ERR" && [[ ! -e "$DLOG/argv" ]]; } \
  && ok "无规则文件 → exit 0、no rules、零网络" || bad "no-rules 路径不对（rc=${D_RC}）"
mv "$DT/rules.bak" "$DT/qwbuddy/dispatch-rules.json"

# 49.8 qwb-run.sh --worker auto 集成（stub herdr；$TMP 是前面装好的假项目）
# 注：$DT/config 里的规则文件此时是 49.6 留下的坏文件，$TMP 直接写好规则，不从 $DT 拷
rm -f "$DT/.env"
mkdir -p "$TMP/qwbuddy"
cat > "$TMP/qwbuddy/dispatch-rules.json" <<'JSON'
{
  "rules": [
    {"when": "复杂架构、跨模块重构、高风险改动", "worker": "codex"},
    {"when": "常规实现、机械改动、调研", "worker": "pi"},
    {"when": "代码审核、对抗性审查", "worker": "claude"}
  ],
  "default": {"worker": "pi"}
}
JSON
AUT="$TMP/tasks/2099-01-50-autodisp.md"
cat > "$AUT" <<'EOF'
# autodisp
state: blocked

## 1. 验收场景

### user_正常
Given 任务书就绪
When  auto 派发
Then  落到解析出的工人
### user_失败
Given 派工不可用
When  auto 派发
Then  落默认工人不阻塞
EOF
autoworker() { grep '^dispatch:' "$AUT" | tail -1 | sed -n 's/.*worker=\([^[:space:]]*\).*/\1/p'; }
rm -rf "$TMP/qwbuddy/.controller.lock"
auto_run() { # 额外 env 以 DENV 传；stderr 落 $DT/run.err
  ( cd "$TMP" && env -u TYPESAFE_API_KEY ${AUTO_KEY:+TYPESAFE_API_KEY=$AUTO_KEY} ${DENV:-} \
      PATH="$DFB:$STUB:$PATH" HERDR_PANE_ID=wtest:dp \
      bash qwbuddy/bin/qwb-run.sh --task autodisp --worker auto --here 2>"$DT/run.err" ) >/dev/null; }
# (a) off → 默认工人 pi，不阻塞
dreset; dresp "$DT/resp.json" rule_1 0.94
auto_run; a_rc=$?
{ [[ "$a_rc" -eq 0 ]] && [[ "$(autoworker)" == "pi" ]] \
    && grep -q 'qwb-dispatch: off' "$DT/run.err" && grep -q '按默认工人 pi' "$DT/run.err"; } \
  && ok "auto+off → 落默认工人 pi 派发成功，stderr 有说明（验收 4）" \
  || { bad "auto+off 不对（rc=${a_rc}）"; cat "$DT/run.err"; }
# (b) clear → 规则命中的 codex
dreset; dresp "$DT/resp.json" rule_1 0.94; AUTO_KEY="$DKEY"
auto_run; a_rc=$?; AUTO_KEY=''
{ [[ "$a_rc" -eq 0 ]] && [[ "$(autoworker)" == "codex" ]] && grep -q 'auto 派工命中 → codex' "$DT/run.err"; } \
  && ok "auto+clear → 派给规则命中的 codex（验收 2 延伸）" \
  || { bad "auto+clear 不对（rc=${a_rc}，worker=$(autoworker)）"; cat "$DT/run.err"; }
# (c) error（HTTP 500）→ 默认工人不阻塞（带 key 走到网络层才真测 error 路径）
dreset; dresp "$DT/resp.json" rule_1 0.94; DENV='FAKE_CURL_HTTP=500'; AUTO_KEY="$DKEY"
auto_run; a_rc=$?; DENV=''; AUTO_KEY=''
{ [[ "$a_rc" -eq 0 ]] && [[ "$(autoworker)" == "pi" ]] && grep -q '未命中' "$DT/run.err"; } \
  && ok "auto+error（http 500）→ 落默认工人 pi 不阻塞（验收 4）" \
  || { bad "auto+error 不对（rc=${a_rc}）"; cat "$DT/run.err"; }
# 远端反射 Authorization 时，上层回退照常执行，任何输出不得含凭据 canary。
dreset; printf 'Authorization: Bearer %s\n' "$DKEY" > "$DT/resp.json"
DENV='FAKE_CURL_HTTP=500'; AUTO_KEY="$DKEY"
auto_run; a_rc=$?; DENV=''; AUTO_KEY=''
{ [[ "$a_rc" -eq 0 ]] && [[ "$(autoworker)" == "pi" ]] \
  && ! grep -qF "$DKEY" "$DT/run.err"; } \
  && ok "auto+反射 Authorization → 默认工人且 stderr 无 canary" \
  || bad "auto+反射 Authorization 回退或凭据保护失败（rc=${a_rc}）"
# (d) 坏规则文件 → 拒绝派发（exit 2）、零副作用（带 key 才会走到规则校验）
nd_before="$(grep -c '^dispatch:' "$AUT")"
printf '%s\n' '{"rules":[' > "$TMP/qwbuddy/dispatch-rules.json"
AUTO_KEY="$DKEY"
auto_run; a_rc=$?; AUTO_KEY=''
{ [[ "$a_rc" -eq 2 ]] && [[ "$(grep -c '^dispatch:' "$AUT")" -eq "$nd_before" ]] \
    && grep -q '配置错误' "$DT/run.err"; } \
  && ok "auto+坏规则 → 拒绝派发（exit 2）零副作用" \
  || { bad "auto+坏规则不对（rc=${a_rc}）"; cat "$DT/run.err"; }
# (e) 规则解析出 QWB_WORKERS 之外的工人 → 整词校验拒绝（自建 ghost 规则，不依赖 (d) 遗留状态）
jq -n '{rules:[{when:"复杂架构、跨模块重构、高风险改动",worker:"ghost"},
  {when:"常规实现、机械改动、调研",worker:"pi"},
  {when:"代码审核、对抗性审查",worker:"claude"}],default:{worker:"pi"}}' \
  > "$TMP/qwbuddy/dispatch-rules.json"
dreset; dresp "$DT/resp.json" rule_1 0.94; AUTO_KEY="$DKEY"
auto_run; a_rc=$?; AUTO_KEY=''
{ [[ "$a_rc" -eq 1 ]] && [[ "$(grep -c '^dispatch:' "$AUT")" -eq "$nd_before" ]] \
    && grep -q '合法工人' "$DT/run.err"; } \
  && ok "规则解析出 QWB_WORKERS 外工人 → 整词校验拒绝" \
  || { bad "ghost 未拒（rc=${a_rc}）"; cat "$DT/run.err"; }
rm -rf "$DT"

echo "== 50. brief-include：常驻附页原样追加 / 无附页零改动 / 不可读拒绝 / 重复派发不叠加 =="
rm -rf "$TMP/qwbuddy/.controller.lock"   # 前面节（JEV auto）的派发持过锁；本节统一用固定 pane id 当主控
BI_T="$TMP/tasks/2099-01-06-binc.md"
cat > "$BI_T" <<'EOF'
# 附页测试
state: blocked

## 验收场景

### user_正常路径
Given 任务书已写好
When  主控派发
Then  账本追加 dispatch 行

### user_失败路径
Given 附页路径是目录
When  主控派发
Then  拒绝派发并报错
EOF
BIF="$TMP/qwbuddy/brief-include.md"
bi_run() { ( cd "$TMP" && PATH="$STUB:$PATH" HERDR_PANE_ID=wtest:ctl bash qwbuddy/bin/qwb-run.sh --task binc --worker codex --here ) 2>&1; }

# init 装项目时拷模板，且不覆盖项目已改过的附页（幂等）
assert_file "$BIF"
printf '项目自己的常驻规则\n' > "$BIF"
bash "$ROOT/bin/qwb-init.sh" "$TMP" >/dev/null
grep -qF '项目自己的常驻规则' "$BIF" && ok "init 幂等：已存在 brief-include.md 不覆盖" || bad "init 覆盖了项目自己的 brief-include.md"

# 场景：无附页 → 行为与今天一致（无附页节、stderr 无附页字样、退出 0）
rm -f "$BIF"
bi_out="$(bi_run)"; bi_rc=$?
{ [[ "$bi_rc" -eq 0 ]] && ! grep -q '常驻附页' "$BI_T" && ! printf '%s' "$bi_out" | grep -q '附页'; } \
  && ok "无附页：派发退出 0、任务书无附页节、stderr 无附页字样" \
  || bad "无附页派发不对（rc=${bi_rc}，out=${bi_out}）"

# 场景：有附页（中文多行）→ 任务书末尾原样追加附页节 + 声明；scenarios-fp 冻结语义不变
cat > "$BIF" <<'EOF'
  提交纪律：行首空格要保留

第二段：不 trim、不改写；含中文与 $(id) 不展开。
EOF
bi_out="$(bi_run)"; bi_rc=$?
inc_line="$(grep -n '^## 常驻附页' "$BI_T" | cut -d: -f1)"
disp_line="$(grep -n '^dispatch:' "$BI_T" | tail -1 | cut -d: -f1)"
{ [[ "$bi_rc" -eq 0 ]] \
  && [[ "$(grep -c '^## 常驻附页' "$BI_T")" == "1" ]] \
  && grep -qF '  提交纪律：行首空格要保留' "$BI_T" \
  && grep -qF '$(id) 不展开' "$BI_T" \
  && grep -qF '以其余各节为准' "$BI_T" \
  && grep -q '^brief-include-fp: ' "$BI_T" \
  && [[ "$inc_line" -lt "$disp_line" ]]; } \
  && ok "有附页：末尾原样追加（保留行首空格/不展开）、含声明、在 dispatch 行之前" \
  || bad "有附页追加不对（rc=${bi_rc}，inc=${inc_line}，disp=${disp_line}，out=${bi_out}）"

# 场景：重复派发同一附页 → 不叠加；scenarios-fp 冻结基线不被附页追加破坏（对照用例）
bi_out="$(bi_run)"; bi_rc=$?
{ [[ "$bi_rc" -eq 0 ]] && [[ "$(grep -c '^## 常驻附页' "$BI_T")" == "1" ]]; } \
  && ok "重复派发：附页仍只有一份，冻结基线核对通过（rc=0）" \
  || bad "重复派发不对（rc=${bi_rc}，out=${bi_out}）"

# 附页内容变化 → 能追加新版（最后一份为新内容），不因已有附页节而永远跳过
printf '新版常驻规则\n' > "$BIF"
bi_out="$(bi_run)"; bi_rc=$?
new_fp="$(printf '%s' "$(cat "$BIF")" | shasum | cut -d' ' -f1)"
{ [[ "$bi_rc" -eq 0 ]] && [[ "$(grep -c '^## 常驻附页' "$BI_T")" == "2" ]] \
  && grep -qF '新版常驻规则' "$BI_T" \
  && [[ "$(grep '^brief-include-fp: ' "$BI_T" | tail -1)" == "brief-include-fp: $new_fp" ]]; } \
  && ok "附页内容变化：追加新版且最后一份指纹为新内容" \
  || bad "附页内容变化不对（rc=${bi_rc}，out=${bi_out}）"
# 顺序不变量：附页恒在 dispatch 行之前——dispatch 是启动工人前写入的最后一行，
# agent start 失败时才能按「删最后一行且回到写前行数」安全回滚（§67/§69 有回滚用例钉住）
[[ "$inc_line" -lt "$disp_line" ]] \
  && ok "顺序不变量：附页节在 dispatch 行之前（dispatch 恒为启动前最后一行）" \
  || bad "附页节跑到 dispatch 行之后，破坏回滚前提（inc=${inc_line}，disp=${disp_line}）"

# 场景：附页路径是目录 → 报明确错误拒绝派发，任务书零写入（不留半截）
cp "$BI_T" "$BI_T.snap"
rm -f "$BIF"; mkdir "$BIF"
bi_out="$(bi_run)"; bi_rc=$?
{ [[ "$bi_rc" -ne 0 ]] && printf '%s' "$bi_out" | grep -q '可读的常规文件' && cmp -s "$BI_T" "$BI_T.snap"; } \
  && ok "附页是目录：拒绝派发（rc≠0），任务书与派发前逐字节一致" \
  || bad "附页目录拒绝不对（rc=${bi_rc}，out=${bi_out}）"
rmdir "$BIF"; rm -f "$BI_T.snap"

echo "== 51. 工人最高权限启动：QWB_WORKER_ARGS 按工人追加 herdr agent start 的 -- 参数 =="
# 场景（票 §1）：herdr 模式带参数｜参数含空格按词切｜未配置的工人不加 --（字节一致）｜
#   pane-run 工人在 ARGS 里配了值则拒绝（零副作用）｜pane-run 命令行带权限参数照常且过 headless 检查｜
#   参数里混入 headless 形式则拒绝（零副作用）｜模板默认值可被 lint 与 source 接受。
# 真实调用序列仍全部经 stub herdr；stub 应答取自 tests/fixtures/herdr/ 真录（agent-start.json 等）。
MPX="$TMP/maxperm"; mkdir -p "$MPX"; bash "$ROOT/bin/qwb-init.sh" "$MPX" >/dev/null
printf '%s\n' 'QWB_GATE_FAST="true"' 'QWB_GATE_FULL="true"' 'QWB_AGENT_START_MS=300' \
  'QWB_WORKERS="codex claude devin omp pi cmd"' >> "$MPX/qwbuddy/config.sh"
MPXT="$MPX/tasks/2099-04-01-"

mp_task() { # $1=任务 id（短小写，便于断言 agent 名 qwb-<id>）
  cat > "${MPXT}$1.md" <<EOF
# $1
state: blocked

## 1. 验收场景

### user_正常
Given 任务书与工人配置合法
When  主控派发
Then  工人以配置的启动参数被拉起

### user_失败
Given 工人参数配错或含 headless 形式
When  主控派发
Then  在任何副作用之前拒绝
EOF
}
MP_LAUNCH=""; MP_ARGS=""
mp_emit_workers() { # 历史用例的长串输入仅在测试夹具里转换；运行入口只读 workers.sh
  MP_LAUNCH="$MP_LAUNCH" MP_ARGS="$MP_ARGS" MP_OUT="$MPX/qwbuddy/workers.sh" python3 - <<'PYWORKERS'
import os, shlex
names = ("codex", "claude", "devin", "omp", "pi", "cmd")
def parse(raw):
    result, current = {}, None
    for word in raw.split():
        prefix = word.split("=", 1)[0]
        if "=" in word and prefix in names:
            current = prefix
            result[current] = [word.split("=", 1)[1]]
        elif current is not None:
            result[current].append(word)
    return {key: " ".join(value) for key, value in result.items()}
launch, args = parse(os.environ["MP_LAUNCH"]), parse(os.environ["MP_ARGS"])
with open(os.environ["MP_OUT"], "w") as out:
    for name in names:
        mode = launch.get(name, "herdr")
        params = args.get(name, "")
        if mode.startswith("pane-run:"):
            words = [name, "pane-run", *mode[len("pane-run:"):].split()]
        else:
            words = [name, mode, *params.split()]
        out.write("qwb_worker " + " ".join(shlex.quote(x) for x in words) + "\n")
        if mode.startswith("pane-run:") and params:
            out.write("qwb_worker " + " ".join(shlex.quote(x) for x in [name, "herdr", *params.split()]) + "\n")
PYWORKERS
}
mp_set() { # $1=键名 $2=值；旧输入只用于保留已有公开派发断言
  case "$1" in
    QWB_WORKER_LAUNCH) MP_LAUNCH="$2"; mp_emit_workers ;;
    QWB_WORKER_ARGS) MP_ARGS="$2"; mp_emit_workers ;;
    *) sed -i '' "/^$1=/d" "$MPX/qwbuddy/config.sh"
       [[ -n "$2" ]] && printf '%s="%s"\n' "$1" "$2" >> "$MPX/qwbuddy/config.sh"
       return 0 ;;
  esac
}

mp_pre() { rm -rf "$MPX/qwbuddy/.controller.lock"; : > "$STUBLOG"; }
mp_run() { ( cd "$MPX" && PATH="$STUB:$PATH" HERDR_PANE_ID=wtest:mp HERDR_WORKSPACE_ID=wtestW \
  bash qwbuddy/bin/qwb-run.sh "$@" ); }
mp_clean() { # $1=任务 id：断言拒绝路径零副作用（无 herdr 调用/无 dispatch/无基线/state 未动/无锁）
  local f="${MPXT}$1.md"
  [[ -s "$STUBLOG" ]] && return 1
  grep -q '^dispatch:' "$f" && return 1
  grep -q '^scenarios-fp:' "$f" && return 1
  grep -q '^state: blocked' "$f" || return 1
  [[ -d "$MPX/qwbuddy/.controller.lock" ]] && return 1
  return 0
}
# 参数未声明时默认走 herdr；QWB_WORKER_LAUNCH 只在个别用例里覆盖
mp_set QWB_WORKER_LAUNCH ""; mp_set QWB_WORKER_ARGS ""

# 51a herdr 模式带参数：agent start 行以 `-- <参数>` 结尾，agent prompt 照常，退出码 0
mp_task mpstart; mp_set QWB_WORKER_ARGS "codex=--dangerously-bypass-approvals-and-sandbox claude=--dangerously-skip-permissions"
mp_pre
out="$(mp_run --task mpstart --worker codex --here 2>&1)"; rc=$?
[[ "$rc" -eq 0 ]] && ok "带 QWB_WORKER_ARGS 的 herdr 派发退出 0" || { bad "带参数派发非 0（rc=${rc}）"; printf '%s\n' "$out"; }
grep -qxF 'herdr agent start qwb-mpstart --kind codex --pane w93:p7 --timeout 300 -- --dangerously-bypass-approvals-and-sandbox' "$STUBLOG" \
  && ok "agent start 行以「-- --dangerously-bypass-approvals-and-sandbox」结尾" \
  || { bad "agent start 行未按预期追加参数："; grep '^herdr agent start' "$STUBLOG"; }
grep -q '^herdr agent prompt qwb-mpstart ' "$STUBLOG" && ok "带参数时 agent prompt 照常" || bad "带参数时 agent prompt 缺失"
grep -qF -e '--dangerously-bypass-approvals-and-sandbox --dangerously-skip-permissions' "$STUBLOG" \
  && bad "claude 的参数串串进了 codex 的参数（切分越界）" || ok "claude 的参数未串进 codex 的参数"

# 51b 参数含空格按词切：devin 得两个词，omp 的参数不串进来；换工人取各自的参数
mp_task mpdev; mp_task mpomp
mp_set QWB_WORKER_ARGS "devin=--permission-mode dangerous omp=--auto-approve"
mp_pre
out="$(mp_run --task mpdev --worker devin --here 2>&1)"; rc=$?
[[ "$rc" -eq 0 ]] && ok "含空格参数（devin）派发退出 0" || { bad "devin 派发非 0（rc=${rc}）"; printf '%s\n' "$out"; }
grep -qxF 'herdr agent start qwb-mpdev --kind devin --pane w93:p7 --timeout 300 -- --permission-mode dangerous' "$STUBLOG" \
  && ok "agent start 行以「-- --permission-mode dangerous」结尾（两个词）" \
  || { bad "含空格参数未按词切："; grep '^herdr agent start' "$STUBLOG"; }
grep -q 'omp=' "$STUBLOG" && bad "omp= 串进了 devin 的参数" || ok "stub 日志不含 omp=（切分到下一个工人名= 为止）"
mp_pre
out="$(mp_run --task mpomp --worker omp --here 2>&1)"; rc=$?
[[ "$rc" -eq 0 ]] \
  && grep -qxF 'herdr agent start qwb-mpomp --kind omp --pane w93:p7 --timeout 300 -- --auto-approve' "$STUBLOG" \
  && ok "--worker omp 只带自己的「-- --auto-approve」" \
  || { bad "omp 参数不对（rc=${rc}）："; grep '^herdr agent start' "$STUBLOG"; }

# 51c 未配置的工人不加 --：整行与现状字节一致（无 `--`、无尾随空格）
mp_task mpbare
mp_set QWB_WORKER_ARGS ""
mp_pre
out="$(mp_run --task mpbare --worker codex --here 2>&1)"; rc=$?
sl="$(grep '^herdr agent start' "$STUBLOG")"
{ [[ "$rc" -eq 0 ]] && [[ "$(grep -c '^herdr agent start' "$STUBLOG")" == "1" ]] \
   && [[ "$sl" == "herdr agent start qwb-mpbare --kind codex --pane w93:p7 --timeout 300" ]]; } \
  && ok "QWB_WORKER_ARGS 未声明 → agent start 行与现状字节一致（无 --）" \
  || { bad "未声明时 agent start 行变了（rc=${rc}）：${sl}"; }
# 对照：ARGS 非空但不含该工人 → 该工人同样不加 --
mp_task mpother
mp_set QWB_WORKER_ARGS "claude=--dangerously-skip-permissions"
mp_pre
out="$(mp_run --task mpother --worker codex --here 2>&1)"; rc=$?
sl="$(grep '^herdr agent start' "$STUBLOG")"
{ [[ "$rc" -eq 0 ]] && [[ "$sl" == "herdr agent start qwb-mpother --kind codex --pane w93:p7 --timeout 300" ]]; } \
  && ok "ARGS 不含 codex= → codex 仍不加 --（逐工人生效）" \
  || { bad "未列出的工人被加了参数（rc=${rc}）：${sl}"; }

# 51d pane-run 工人在 ARGS 里配了值 → 在锁/worktree/tab/账本写之前拒绝并指回 LAUNCH
mp_task mpcollide
mp_set QWB_WORKER_LAUNCH "cmd=pane-run:cmd"; mp_set QWB_WORKER_ARGS "cmd=--yolo"
mp_pre
out="$(mp_run --task mpcollide --worker cmd --here 2>&1)"; rc=$?
{ [[ "$rc" -ne 0 ]] && printf '%s' "$out" | grep -q '重复启动定义' \
   && mp_clean mpcollide; } \
  && ok "pane-run 工人在 ARGS 里配值 → 拒绝且零副作用（rc=${rc}）" \
  || { bad "pane-run 冲突未拦住或留了副作用（rc=${rc}）"; printf '%s\n' "$out"; }

# 51e pane-run 命令行带权限参数照常，且不被 headless 检查误拒
mp_task mppane
mp_set QWB_WORKER_LAUNCH "cmd=pane-run:cmd --yolo --trust"; mp_set QWB_WORKER_ARGS ""
mp_pre
out="$(mp_run --task mppane --worker cmd --here 2>&1)"; rc=$?
{ [[ "$rc" -eq 0 ]] && grep -qxF "herdr pane run w93:p7 'cmd' '--yolo' '--trust'" "$STUBLOG" \
   && grep -q '^herdr agent rename w93:p7 qwb-mppane' "$STUBLOG" \
   && ! grep -q 'agent start' "$STUBLOG"; } \
  && ok "pane-run 命令行带 --yolo --trust 照常启动且未被误判 headless（rc=${rc}）" \
  || { bad "pane-run 权限参数路径不对（rc=${rc}）"; printf '%s\n' "$out"; grep '^herdr ' "$STUBLOG"; }

# 51f 参数里混入 headless 形式 → 拒绝；四种形式同一条检查，且只对配了该形式的工人生效
# （任务 id 不互为前缀：--task 是按 id 模糊匹配的）
mp_task mphead; mp_task mpfine
mp_set QWB_WORKER_LAUNCH ""
for hform in '-p' '--print' '--exec' 'exec'; do
  mp_set QWB_WORKER_ARGS "claude=--dangerously-skip-permissions ${hform}"
  mp_pre
  out="$(mp_run --task mphead --worker claude --here 2>&1)"; rc=$?
  { [[ "$rc" -ne 0 ]] && printf '%s' "$out" | grep -qi 'headless' && mp_clean mphead; } \
    && ok "ARGS 含 headless 形式「${hform}」→ 拒绝且零副作用（rc=${rc}）" \
    || { bad "headless 形式「${hform}」未被拦（rc=${rc}）"; printf '%s\n' "$out"; }
done
# 对照：同一份配置里没配该形式的工人照常派发——检查逐工人生效，不整表拒绝
mp_pre
out="$(mp_run --task mpfine --worker codex --here 2>&1)"; rc=$?
{ [[ "$rc" -eq 0 ]] && [[ "$(grep '^herdr agent start' "$STUBLOG")" == "herdr agent start qwb-mpfine --kind codex --pane w93:p7 --timeout 300" ]]; } \
  && ok "对照：同表里未配 headless 形式的工人照常派发" \
  || { bad "对照失败——检查整表拒绝而非逐工人（rc=${rc}）"; printf '%s\n' "$out"; }

# 51g 模板默认值：可被 source 与 bash -n 接受、被 lint 认作活键，且真派发时按工人生效
mp_task mptmpl
cp "$ROOT/templates/workers.sh" "$MPX/qwbuddy/workers.sh"
printf '%s\n' 'qwb_worker cmd herdr' >> "$MPX/qwbuddy/workers.sh"
bash -n "$ROOT/templates/config.sh" && bash -n "$ROOT/templates/workers.sh" \
  && ok "bash -n config.sh / workers.sh 退出 0" || bad "工人配置模板语法错误"
if grep -qxF 'qwb_worker codex herdr --dangerously-bypass-approvals-and-sandbox' "$ROOT/templates/workers.sh" \
  && grep -qxF 'qwb_worker claude herdr --dangerously-skip-permissions' "$ROOT/templates/workers.sh" \
  && grep -qxF 'qwb_worker devin herdr --permission-mode dangerous --respect-workspace-trust false' "$ROOT/templates/workers.sh" \
  && grep -qxF 'qwb_worker omp herdr --auto-approve' "$ROOT/templates/workers.sh" \
  && grep -qxF 'qwb_worker pi herdr --approve' "$ROOT/templates/workers.sh"; then
  ok "模板默认参数与票 §0 一致（5 个 herdr-kind 工人，devin 含信任参数）"
else
  bad "模板默认参数与票不符"
fi
grep -qxF 'qwb_worker codex herdr --dangerously-bypass-approvals-and-sandbox' "$TMP/qwbuddy/workers.sh" \
  && ok "qwb-init 装出的 workers.sh 带默认权限参数" || bad "安装的 workers.sh 缺默认参数"
lintout="$(bash "$ROOT/bin/qwb-lint.sh" --project "$ROOT" 2>&1)"; rc=$?
{ [[ "$rc" -eq 0 ]] && printf '%s' "$lintout" | grep -q 'LINT PASS' \
   && printf '%s' "$lintout" | grep -q '键全部被.*引用'; } \
  && ok "lint 过且「config 无死键」PASS" \
  || { bad "lint 未过或无死键检查 PASS（rc=${rc}）"; printf '%s\n' "$lintout"; }
mp_pre
out="$(mp_run --task mptmpl --worker codex --here 2>&1)"; rc=$?
{ [[ "$rc" -eq 0 ]] \
   && grep -qxF 'herdr agent start qwb-mptmpl --kind codex --pane w93:p7 --timeout 300 -- --dangerously-bypass-approvals-and-sandbox' "$STUBLOG"; } \
  && ok "用模板默认值真派发：codex 拿到自己的最高权限参数（rc=${rc}）" \
  || { bad "模板默认值派发不对（rc=${rc}）"; printf '%s\n' "$out"; grep '^herdr agent start' "$STUBLOG"; }
echo "== 52. 派发前预置目录信任（trust-preseed）=="
# 场景（票 §1）：claude 写 ~/.claude.json（保留原有项目、幂等）｜codex 追加 ~/.codex/config.toml
# 块（原内容不变、不重复追加）｜.claude.json 非法 → stderr 一行警告、文件不动、派发照常 rc=0。
# HOME 已在顶部隔离到 $TMP/home。复用 51 节的 mp_* 装置（本节之后才 rm -rf $MPX）。
mp_task tpc; mp_task tpx
mp_set QWB_WORKER_LAUNCH ""; mp_set QWB_WORKER_ARGS ""
tp_claude="$TMP/home/.claude.json"; tp_codex="$TMP/home/.codex/config.toml"
rm -rf "$TMP/home"; mkdir -p "$TMP/home/.codex"
printf '{"projects":{"/other/proj":{"hasTrustDialogAccepted":false},"/two":{"allowedTools":["Bash"]}}}' > "$tp_claude"
printf '[projects."/existing/proj"]\ntrust_level = "trusted"\n' > "$tp_codex"
tp_snap="$(cat "$tp_codex")"
tp_projdir="$MPX"

# 52a claude：写入 projects[<项目根>].hasTrustDialogAccepted=true，原有项目保留、仍是合法 JSON
mp_pre
out="$(mp_run --task tpc --worker claude --here 2>&1)"; rc=$?
tp_read='my $j = decode_json(<STDIN>); my $p = $j->{projects} // {}; print(($p->{$ARGV[0]}{hasTrustDialogAccepted} ? "T" : "F"), (exists $p->{"/other/proj"} ? "o" : "x"), (exists $p->{"/two"} ? "w" : "x"))'
tp_got="$(perl -MJSON::PP=decode_json -e "$tp_read" "$tp_projdir" < "$tp_claude" 2>/dev/null)"
{ [[ "$rc" -eq 0 ]] && [[ "$tp_got" == "Tow" ]] && perl -MJSON::PP=decode_json -e 'decode_json(join "", <>)' < "$tp_claude"; } \
  && ok "claude：hasTrustDialogAccepted=true 写入，原有两个项目保留，仍是合法 JSON" \
  || { bad "claude 预置不对（rc=${rc}，读值=${tp_got:-不可解码}）"; printf '%s\n' "$out"; }

# 52b claude 幂等：已 true 再派一次 → 文件字节不变
n1=$(wc -c < "$tp_claude" | tr -d ' ')
mp_pre
mp_run --task tpc --worker claude --here >/dev/null 2>&1
[[ "$(wc -c < "$tp_claude" | tr -d ' ')" == "$n1" ]] \
  && ok "claude：已受信任再派一次文件字节不变（幂等）" \
  || bad "claude：幂等失败，二次派发改写了文件"

# 52c codex：尾部追加本项目根块，原内容不变；再派一次不重复追加
mp_pre
out="$(mp_run --task tpx --worker codex --here 2>&1)"; rc=$?
{ [[ "$rc" -eq 0 ]] \
   && [[ "$(head -2 "$tp_codex")" == "$tp_snap" ]] \
   && grep -qxF '[projects."'"$tp_projdir"'"]' "$tp_codex" \
   && grep -qxF 'trust_level = "trusted"' "$tp_codex"; } \
  && ok "codex：尾部追加本项目块，原有内容逐字保留" \
  || { bad "codex 预置不对（rc=${rc}）"; printf '%s\n' "$out"; cat "$tp_codex"; }
mp_pre
mp_run --task tpx --worker codex --here >/dev/null 2>"$TMP/tp2.err"
{ [[ "$(grep -cF '[projects."'"$tp_projdir"'"]' "$tp_codex")" == "1" ]] && [[ "$(cat "$tp_codex")" == "${tp_snap}
[projects.\"$tp_projdir\"]
trust_level = \"trusted\"" ]]; } \
  && ok "codex：已受信任再派一次不重复追加（块恰一个、文件内容不变）" \
  || { bad "codex：幂等失败（重复追加或内容漂移）"; echo "[dump] tp_codex:"; cat "$tp_codex"; echo "[dump] err2:"; cat "$TMP/tp2.err"; }

# 52d 失败路径：.claude.json 非法 → stderr 一行警告、文件不动、派发照常 rc=0
printf '{bad' > "$tp_claude"
mp_pre
out="$(mp_run --task tpc --worker claude --here 2>"$TMP/tp.err")"; rc=$?
{ [[ "$rc" -eq 0 ]] \
   && [[ "$(cat "$tp_claude")" == '{bad' ]] \
   && [[ "$(grep -c '跳过 claude 信任预置' "$TMP/tp.err")" == "1" ]] \
   && grep -qxF 'herdr agent start qwb-tpc --kind claude --pane w93:p7 --timeout 300' "$STUBLOG"; } \
  && ok "claude.json 非法：stderr 恰一行警告、文件不动、派发照常 rc=0" \
  || { bad "非法 JSON 路径不对（rc=${rc}）"; cat "$TMP/tp.err" >&2; printf '%s\n' "$out"; }
# 对照：codex 工人不碰 claude.json（只对实际派的工人做）
printf '{bad' > "$tp_claude"
mp_pre
mp_run --task tpx --worker codex --here >/dev/null 2>&1
[[ "$(cat "$tp_claude")" == '{bad' ]] \
  && ok "对照：派 codex 不碰 .claude.json（只对实际派的工人预置）" \
  || bad "派 codex 却改写了 .claude.json"

rm -rf "$MPX"

echo "== 51h. 默认值自洽（2026-09-16 spec-defect 回归门）=="
dworkers="$( . "$ROOT/templates/config.sh"; printf '%s' "$QWB_WORKERS" )"
dargs="$(awk '$1 == "qwb_worker" { print $2 }' "$ROOT/templates/workers.sh")"
miss=""
for w in $dworkers; do
  table_count=0; definition_count=0
  for nm in $dworkers; do [[ "$nm" == "$w" ]] && table_count=$((table_count+1)); done
  for nm in $dargs; do [[ "$nm" == "$w" ]] && definition_count=$((definition_count+1)); done
  [[ "$table_count" -eq 1 && "$definition_count" -eq 1 ]] \
    || miss="${miss} ${w}(table=${table_count},definition=${definition_count})"
done
for nm in $dargs; do
  inself=0
  for w in $dworkers; do [[ "$nm" == "$w" ]] && { inself=1; break; }; done
  [[ "$inself" -eq 1 ]] || miss="${miss} ${nm}"
done
{ [[ -n "$dworkers" && -z "$miss" && "$(printf '%s' "$dworkers" | wc -w | tr -d ' ')" == "5" ]]; } \
  && ok "默认 workers.sh 的每个工人都在 QWB_WORKERS 且声明唯一" \
  || bad "默认 workers.sh 含未知或重复工人:${miss}"

echo "== 53. qwb-wake.sh --block：exit 2/0/124 + REWAKE 兑底（值守隐形化核心）=="
# 独立项目跑本节：其他节会改写共享 $TMP 的 config.sh（如第 27 节追加 QWB_REWAKE_MS=0）与账本，
# --block 的去重/REWAKE 判定依赖干净 config，不与它们共账本
BP="$TMP/block-proj"; mkdir -p "$BP/tasks"; cp -R "$TMP/qwbuddy" "$BP/qwbuddy"
cp "$ROOT/templates/config.sh" "$BP/qwbuddy/config.sh"   # $TMP 的 config 已被第 27 节负例追加 QWB_REWAKE_MS=0，覆盖回干净模板
BLK="$BP/tasks/2099-01-07-blk.md"
printf '# block\nstate: running\ndone: 工人完成 block 场景\n' > "$BLK"
: > "$STUBLOG"
blk_out="$( cd "$BP" && PATH="$STUB:$PATH" env -u HERDR_PANE_ID bash "$BP/qwbuddy/bin/qwb-wake.sh" --project "$BP" --block --max-ms 5000 2>&1 )"; blk_rc=$?
{ [[ "$blk_rc" -eq 2 ]] \
  && printf '%s' "$blk_out" | grep -q '2099-01-07-blk' \
  && printf '%s' "$blk_out" | grep -qF 'done: 工人完成 block 场景' \
  && grep -q '^wake:' "$BLK"; } \
  && ok "--block 有变化：rc=2 + 摘要含票名与 done 行 + 写 wake 行" \
  || bad "--block 有变化路径不对（rc=${blk_rc}，out=${blk_out}）"
{ ! grep -q 'pane run' "$STUBLOG" && ! grep -q 'tab create' "$STUBLOG"; } \
  && ok "--block 无窗口：stub 日志无 pane run / tab create" \
  || { bad "--block 竟调了 herdr 窗口动作"; cat "$STUBLOG"; }

# 场景：账本全部已结 → rc 0、任何票文件字节不变、stub 日志无 herdr 调用
BLK_SNAP="$TMP/blk.snap"; sed -i '' 's/^state: running/state: verified/' "$BLK"
cp "$BLK" "$BLK_SNAP"   # 快照取在改 state 之后：断言的是 --block 不动已结票
: > "$STUBLOG"
( cd "$BP" && PATH="$STUB:$PATH" env -u HERDR_PANE_ID bash "$BP/qwbuddy/bin/qwb-wake.sh" --project "$BP" --block --max-ms 5000 ) >/dev/null 2>&1; blk_rc=$?
{ [[ "$blk_rc" -eq 0 ]] && cmp -s "$BLK" "$BLK_SNAP" && [[ ! -s "$STUBLOG" ]]; } \
  && ok "--block 无未结项：rc=0、票字节不变、零 herdr 调用" \
  || bad "--block 无未结项路径不对（rc=${blk_rc}）"

# 场景（失败路径）：有未结项但指纹与最后 wake 行一致且未超 REWAKE，--max-ms 500 + 假时钟
#   → rc 124、票字节不变、假时钟推进 ≥500ms、sleep 调用有上界（不忙循环）
BLKFP="$(printf '%s\n' 'running' | shasum | cut -d' ' -f1)"
BLKC="$BP/tasks/2099-01-08-blkc.md"
printf '# c\nstate: running\nwake: 2026-01-01T00:00:00Z state=running fp=%s\n' "$BLKFP" > "$BLKC"
BLKNOW="$BP/blk-now"; BLKSLEEP="$BP/blk-sleep.log"
echo 0 > "$BLKNOW"; : > "$BLKSLEEP"
cat > "$BP/blk-now.sh" <<EOF
#!/usr/bin/env bash
cur="\$(( \$(cat "$BLKNOW") + 100 ))"; echo "\$cur" > "$BLKNOW"; echo "\$cur"
EOF
cat > "$BP/blk-sleep.sh" <<EOF
#!/usr/bin/env bash
echo "\$1" >> "$BLKSLEEP"
[[ "\$(wc -l < "$BLKSLEEP" | tr -d ' ')" -ge 30 ]] && kill "\$PPID" 2>/dev/null
exit 0
EOF
chmod +x "$BP/blk-now.sh" "$BP/blk-sleep.sh"
BLKC_SNAP="$BP/blkc.snap"; cp "$BLKC" "$BLKC_SNAP"
( cd "$BP" && PATH="$STUB:$PATH" QWB_NOW_MS_CMD="$BP/blk-now.sh" QWB_SLEEP_CMD="$BP/blk-sleep.sh" env -u HERDR_PANE_ID \
    bash "$BP/qwbuddy/bin/qwb-wake.sh" --project "$BP" --block --max-ms 500 --interval 300 ) >/dev/null 2>&1; blk_rc=$?
blk_sleeps="$(wc -l < "$BLKSLEEP" | tr -d ' ')"
{ [[ "$blk_rc" -eq 124 ]] && cmp -s "$BLKC" "$BLKC_SNAP" \
  && [[ "$(cat "$BLKNOW")" -ge 500 ]] && [[ "$blk_sleeps" -le 6 ]]; } \
  && ok "--block 到期无变化：rc=124、零写入、假时钟推进 ≥500ms、sleep 仅 ${blk_sleeps} 次" \
  || bad "--block 124 路径不对（rc=${blk_rc}，now=$(cat "$BLKNOW")，sleeps=${blk_sleeps}）"

# 场景：指纹一致但该 wake 时间戳距假时钟"现在"≥ QWB_REWAKE_MS → 仍 rc 2 + 追加新 wake 行
BLKD="$BP/tasks/2099-01-09-blkd.md"
printf '# d\nstate: running\nwake: 2026-01-01T00:00:00Z state=running fp=%s\n' "$BLKFP" > "$BLKD"
printf '#!/usr/bin/env bash\necho 99999999999999\n' > "$BP/blk-far.sh"; chmod +x "$BP/blk-far.sh"
( cd "$BP" && PATH="$STUB:$PATH" QWB_NOW_MS_CMD="$BP/blk-far.sh" \
    env -u HERDR_PANE_ID bash "$BP/qwbuddy/bin/qwb-wake.sh" --project "$BP" --block --max-ms 999999999 ) >/dev/null 2>&1; blk_rc=$?
{ [[ "$blk_rc" -eq 2 ]] && [[ "$(grep -c '^wake:' "$BLKD")" -eq 2 ]]; } \
  && ok "--block REWAKE 兑底：超期再叫 rc=2 + 新 wake 行" \
  || bad "--block REWAKE 兑底不对（rc=${blk_rc}，wakes=$(grep -c '^wake:' "$BLKD")）"

echo "== 54. qwb-hook-claude-stop.sh：守卫 / 单飞 / 残留锁接管 =="
# hook 内部以自身位置推项目根并跑 --block（读该项目 config.sh）——同样用独立项目防 config 污染
HP="$TMP/hook-proj"; mkdir -p "$HP/tasks"; cp -R "$TMP/qwbuddy" "$HP/qwbuddy"
cp "$ROOT/templates/config.sh" "$HP/qwbuddy/config.sh"   # 同上：覆盖回干净 config
# 本节所有 --block 调用必须带上限（测试纪律：回归时要变红、不能挂死）——hook 内部把
# QWB_HOOK_MAX_MS 透传给 --block --max-ms；压小后若实现坏掉会以 124 到期退出，断言 rc=2 变红
printf 'QWB_HOOK_MAX_MS=4000\n' >> "$HP/qwbuddy/config.sh"
mkdir -p "$HP/qwbuddy/.controller.lock"
printf '2026-01-01T00:00:00Z wtest:ctl\n' > "$HP/qwbuddy/.controller.lock/owner"
HOOK="$HP/tasks/2099-01-10-hook.md"
printf '# hook\nstate: running\ndone: hook 场景可动作变化\n' > "$HOOK"
hook_run() { ( cd "$HP" && PATH="$STUB:$PATH" QWB_NOW_MS_CMD="$HP/blk-far.sh" HERDR_PANE_ID="$1" \
    bash qwbuddy/bin/qwb-hook-claude-stop.sh </dev/null 2>&1 ); }   # </dev/null：模拟 Claude Code 写完 stdin 即关闭

# 场景（失败路径）：非锁主 → rc 0 立即返回、假时钟不推进、票无新 wake 行、不创建 .hook.lock
printf '#!/usr/bin/env bash\necho 99999999999999\n' > "$HP/blk-far.sh"; chmod +x "$HP/blk-far.sh"
hook_out="$(hook_run wtest:p2)"; hook_rc=$?
{ [[ "$hook_rc" -eq 0 ]] && [[ ! -d "$HP/qwbuddy/.hook.lock" ]] \
  && ! grep -q '^wake:' "$HOOK"; } \
  && ok "hook 非锁主：rc=0、零副作用（无锁、无 wake 行）" \
  || bad "hook 非锁主不对（rc=${hook_rc}，out=${hook_out}）"

# 场景（失败路径）：本进程是锁主但 .hook.lock 已有活实例 → rc 0 立即、不动已有锁、不跑 --block
mkdir "$HP/qwbuddy/.hook.lock"
echo $$ > "$HP/qwbuddy/.hook.lock/pid"
hook_out="$(hook_run wtest:ctl)"; hook_rc=$?
{ [[ "$hook_rc" -eq 0 ]] && [[ "$(cat "$HP/qwbuddy/.hook.lock/pid")" == "$$" ]] \
  && ! grep -q '^wake:' "$HOOK"; } \
  && ok "hook 单飞：已有活锁 → rc=0 立即让位、原锁未动、未跑 --block" \
  || bad "hook 单飞不对（rc=${hook_rc}，out=${hook_out}）"

# 场景：锁存在但 pid 已死 → 接管、跑 --block、rc 2、摘要在输出里、结束后锁已清
DEADPID=$(sleep 0.1 & echo $!); sleep 0.4
echo "$DEADPID" > "$HP/qwbuddy/.hook.lock/pid"
hook_out="$(hook_run wtest:ctl)"; hook_rc=$?
{ [[ "$hook_rc" -eq 2 ]] \
  && printf '%s' "$hook_out" | grep -qF 'done: hook 场景可动作变化' \
  && [[ ! -d "$HP/qwbuddy/.hook.lock" ]] \
  && grep -q '^wake:' "$HOOK"; } \
  && ok "hook 残留锁接管：rc=2 + 摘要 + 锁已清 + wake 行" \
  || bad "hook 接管不对（rc=${hook_rc}，out=${hook_out}）"

echo "== 55. qwb-init.sh 合并 .claude/settings.json：幂等、不覆盖、非法 JSON 拒绝 =="
# 场景：已有 PreToolUse 与别人的 Stop hook → 跑两次，qwb hook 恰一条，别人内容原样，合法 JSON
mkdir -p "$TMP/.claude"
SETJ="$TMP/.claude/settings.json"
cat > "$SETJ" <<'EOF'
{
  "otherKey": {"keep": true},
  "hooks": {
    "PreToolUse": [
      {"matcher": "Bash", "hooks": [{"type": "command", "command": "echo someone-else-pretool"}]}
    ],
    "Stop": [
      {"hooks": [{"type": "command", "command": "echo someone-else-stop", "timeout": 60}]}
    ]
  }
}
EOF
cp "$SETJ" "$TMP/settings.before"
out="$(bash "$ROOT/bin/qwb-init.sh" "$TMP" 2>&1)"; rc1=$?
out2="$(bash "$ROOT/bin/qwb-init.sh" "$TMP" 2>&1)"; rc2=$?
chk_settings() { CLAUDE_DIR="$ROOT" python3 - "$TMP" <<'PYEOF'
import json, os, sys

tmp = sys.argv[1]
new = json.load(open(os.path.join(tmp, ".claude", "settings.json")))
old = json.load(open(os.path.join(tmp, "settings.before")))
stop = new["hooks"]["Stop"]
qwb = [h for g in stop for h in g.get("hooks", []) if "qwb-hook-claude-stop.sh" in (h.get("command") or "")]
assert len(qwb) == 1, f"qwb hook 数={len(qwb)}"
assert qwb[0]["asyncRewake"] is True and qwb[0]["timeout"] == 7200, "entry 字段不对"
assert old["hooks"]["PreToolUse"] == new["hooks"]["PreToolUse"], "PreToolUse 被改"
assert old["hooks"]["Stop"] == new["hooks"]["Stop"][:1], "别人的 Stop hook 被改或被挤位置"
assert old["otherKey"] == new["otherKey"], "otherKey 被改"
print("SETTINGS-OK")
PYEOF
}
{ [[ "$rc1" -eq 0 && "$rc2" -eq 0 ]] \
  && printf '%s' "$out2" | grep -q '已有 qwb-hook-claude-stop.sh' \
  && chk_settings; } \
  && ok "init 合并 settings.json：两次后恰一条 qwb hook、幂等跳过、别人内容原样、合法 JSON" \
  || bad "init 合并断言失败（rc1=${rc1}，rc2=${rc2}，out=${out2}）"

# 场景（失败路径）：settings.json 内容非法 → rc≠0、stderr 指出文件与未写入、字节不变
printf '{not json' > "$SETJ"; cp "$SETJ" "$TMP/settings.bad"
out="$(bash "$ROOT/bin/qwb-init.sh" "$TMP" 2>&1)"; rc=$?
{ [[ "$rc" -ne 0 ]] && printf '%s' "$out" | grep -q '不是合法 JSON' \
  && printf '%s' "$out" | grep -q '未写入' \
  && printf '%s' "$out" | grep -q '其余安装已照常完成' \
  && cmp -s "$SETJ" "$TMP/settings.bad"; } \
  && ok "init 遇非法 JSON：拒绝、指明文件与未写入、字节不变、说明其余已装" \
  || bad "非法 JSON 拒绝不对（rc=${rc}，out=${out}）"
rm -f "$TMP/settings.before" "$TMP/settings.bad"

echo "== 56. status 值守三态：hook / tab（pane …）/ 未运行 =="
DYN="$TMP/herdr-dyn-s4"; mkdir -p "$DYN"; rm -f "$TMP/qwbuddy/.watch"
stat4() { ( cd "$TMP" && PATH="$STUB:$PATH" HERDR_DYN_DIR="$DYN" HERDR_WORKSPACE_ID=wtestW \
    bash qwbuddy/bin/qwb-status.sh ); }
# hook 态：.hook.lock/pid 存活 → 「值守：hook（pid …）」
mkdir "$TMP/qwbuddy/.hook.lock"; echo $$ > "$TMP/qwbuddy/.hook.lock/pid"
out="$(stat4)"
printf '%s' "$out" | grep -q "值守：hook（pid $$）" \
  && ok "status 三态：hook 活 → 值守：hook" || { bad "status 未报 hook"; printf '%s\n' "$out"; }
# tab 态：无 hook 锁，.watch 登记 + pane 前台有值守进程 → 「值守：tab（pane …）」
rm -rf "$TMP/qwbuddy/.hook.lock"
printf 'pane=w54:p1 workspace=wtestW pid=111 started=x\n' > "$TMP/qwbuddy/.watch"
mk_plist "$DYN/pane-list.json" "w54:p1"
mk_proc w54:p1 wake "$TMP"
out="$(stat4)"
printf '%s' "$out" | grep -q '值守：tab（pane w54:p1）' \
  && ok "status 三态：tab 值守 → 值守：tab（pane w54:p1）" || { bad "status 未报 tab"; printf '%s\n' "$out"; }
# 未运行态：两者皆无 → 「值守：未运行」
rm -f "$TMP/qwbuddy/.watch"; rm -rf "$DYN"; mkdir -p "$DYN"
mk_plist "$DYN/pane-list.json"
out="$(stat4)"
printf '%s' "$out" | grep -q '值守：未运行' \
  && ok "status 三态：两者皆无 → 值守：未运行" || { bad "status 未报未运行"; printf '%s\n' "$out"; }

echo "== 57. 模板新票不污染状态（列首状态行缺口回归）=="
# 场景：把 templates/TASK.md 原样复制为两张新票（state: running）→
#   status 无「最近:」行；wake --once 后各票 wake 行 fp == sha1("running\n")（最后状态行为空）
TPLP="$TMP/tplproj"; mkdir -p "$TPLP"; bash "$ROOT/bin/qwb-init.sh" "$TPLP" >/dev/null
cp "$ROOT/templates/TASK.md" "$TPLP/tasks/2099-01-01-t.md"
cp "$ROOT/templates/TASK.md" "$TPLP/tasks/2099-01-01-t2.md"
out="$( cd "$TPLP" && PATH="$STUB:$PATH" bash qwbuddy/bin/qwb-status.sh )"
{ printf '%s' "$out" | grep -q '2099-01-01-t.md' && ! printf '%s' "$out" | grep -q '最近:'; } \
  && ok "模板复制的新票 status 无「最近:」行" || bad "模板新票竟有「最近:」（模板列首示例污染）"
out="$( cd "$TPLP" && bash qwbuddy/bin/qwb-wake.sh --dry-run --once )"
{ printf '%s' "$out" | grep -q '未结项（将叫醒）: 2099-01-01-t' \
  && ! printf '%s' "$out" | grep -q '最近:'; } \
  && ok "dry-run 同样无最近行（指纹基为空状态行）" || bad "dry-run 仍显示模板示例行"
: > "$STUBLOG"
( cd "$TPLP" && PATH="$STUB:$PATH" bash qwbuddy/bin/qwb-wake.sh --once --pane wtest:p9 ) >/dev/null
EXPECT_FP="$(printf 'running\n' | shasum | cut -d' ' -f1)"
fp1="$(grep '^wake:' "$TPLP/tasks/2099-01-01-t.md" | tail -1 | sed -n 's/.*fp=\([^[:space:]]*\).*/\1/p')"
fp2="$(grep '^wake:' "$TPLP/tasks/2099-01-01-t2.md" | tail -1 | sed -n 's/.*fp=\([^[:space:]]*\).*/\1/p')"
{ [[ "$fp1" == "$EXPECT_FP" && "$fp2" == "$EXPECT_FP" ]] \
  && [[ "$(grep -c '^herdr pane run wtest:p9 看账本' "$STUBLOG" || true)" -eq 1 ]]; } \
  && ok "两票 fp 均 = sha1(\"running\\n\") 且一轮恰好 1 条投递" \
  || bad "fp 不对（${fp1:0:8}/${fp2:0:8} ≠ ${EXPECT_FP:0:8}）"

echo "== 58. 模板残留半行不误拒 + lint 第 8 项警告 =="
# 场景（失败路径变通过）：一票只含模板第一行示例（缩进后的 blocked: spec-defect: <…>）且无真实疑点
#   → 疑点门不拒派发；lint 第 8 项对缩进行无警告
cat > "$TPLP/tasks/2099-01-01-t3.md" <<'EOF'
# 半行残留票
state: running

  blocked:  spec-defect: <票的哪一条条款；反例或证据路径；继续照做会错在哪里>

## 1. 验收场景

### user_正常
Given 任务写好
When  派发
Then  记账成功
### user_失败
Given 列首占位示例
When  派发
Then  不误拒
EOF
out="$( cd "$TPLP" && PATH="$STUB:$PATH" HERDR_PANE_ID=wtest:ctl bash qwbuddy/bin/qwb-run.sh --task t3 --worker pi --here 2>&1 )"; rc=$?
[[ "$rc" -eq 0 ]] && ok "缩进的模板半行不触发疑点门（派发 rc=0）" || bad "缩进半行仍被疑点门拒绝（rc=${rc}）：$(printf '%s' "$out" | tail -2)"
# 对照：列首占位行 → lint 第 8 项警告（stderr 含文件名与「占位状态行」），但退出码仍 0
printf '# 占位票\nstate: running\nworking: spec-resolved: <impl|spec>\n' > "$TPLP/tasks/2099-01-01-t4.md"
printf 'QWB_GATE_FAST="true"\nQWB_GATE_FULL="true"\n' >> "$TPLP/qwbuddy/config.sh"
lint_err="$( cd "$TPLP" && bash qwbuddy/bin/qwb-lint.sh 2>&1 >/dev/null )"; lint_rc=$?
{ [[ "$lint_rc" -eq 0 ]] && printf '%s' "$lint_err" | grep -q '2099-01-01-t4.md' \
  && printf '%s' "$lint_err" | grep -q '占位状态行'; } \
  && ok "lint 第 8 项对列首占位行警告但不 FAIL（rc=0）" \
  || bad "lint 第 8 项行为不对（rc=${lint_rc}）"
printf '%s' "$lint_err" | grep -q '2099-01-01-t3.md' \
  && bad "缩进行被 lint 第 8 项误报" || ok "lint 第 8 项不报缩进行（缩进不算列首）"

echo "== 59. 主控锁残留自动回收（判活：pid 与 pane）=="
LP="$TMP/lockproj"; mkdir -p "$LP"; bash "$ROOT/bin/qwb-init.sh" "$LP" >/dev/null
LK="$LP/qwbuddy/.controller.lock"
# 59a 死 pid → 自动回收
rm -rf "$LK"; mkdir "$LK"
DEADPID="$(sleep 0.1 & echo $!)"; sleep 0.4
printf '2020-01-01T00:00:00Z pid:%s\n' "$DEADPID" > "$LK/owner"
out="$( cd "$LP" && PATH="$STUB:$PATH" bash qwbuddy/bin/qwb-lock.sh acquire --owner me 2>&1 )"; rc=$?
{ [[ "$rc" -eq 0 ]] && printf '%s' "$out" | grep -q '回收残留锁' \
  && [[ "$(sed -n 's/^[^ ]* //p' "$LK/owner" | head -1)" == "me" ]]; } \
  && ok "死 pid 锁主 → 回收残留锁并获锁（rc=0）" || { bad "死 pid 未回收（rc=${rc}）：$out"; }
# 59b pane 已不存在（stub 默认 pane_not_found）→ 自动回收
rm -rf "$LK"; mkdir "$LK"; printf '2020-01-01T00:00:00Z wX:p9\n' > "$LK/owner"
out="$( cd "$LP" && PATH="$STUB:$PATH" HERDR_DYN_DIR="$LP/dyn" bash qwbuddy/bin/qwb-lock.sh acquire --owner me 2>&1 )"; rc=$?
{ [[ "$rc" -eq 0 ]] && printf '%s' "$out" | grep -q '回收残留锁' \
  && [[ "$(sed -n 's/^[^ ]* //p' "$LK/owner" | head -1)" == "me" ]]; } \
  && ok "pane_not_found 锁主 → 回收残留锁并获锁（rc=0）" || { bad "pane 死锁未回收（rc=${rc}）：$out"; }
# 59c（失败路径）活锁照旧拒绝：owner 字节不变
rm -rf "$LP/dyn"; mkdir -p "$LP/dyn"
sed "s|w8Z:pY|wX:p1|g" "$FIXDIR/pane-get-shell.json" > "$LP/dyn/get-wXp1.json"
rm -rf "$LK"; mkdir "$LK"; printf '2020-01-01T00:00:00Z wX:p1\n' > "$LK/owner"
cp "$LK/owner" "$LP/owner.snap"
out="$( cd "$LP" && PATH="$STUB:$PATH" HERDR_DYN_DIR="$LP/dyn" bash qwbuddy/bin/qwb-lock.sh acquire --owner me 2>&1 )"; rc=$?
{ [[ "$rc" -eq 1 ]] && printf '%s' "$out" | grep -q '锁已被占用' && cmp -s "$LK/owner" "$LP/owner.snap"; } \
  && ok "活锁（pane 在）照旧拒绝且 owner 字节不变" || { bad "活锁被误回收（rc=${rc}）"; }
# 59d（失败路径）herdr 查询报错（非 pane_not_found）→ 拒绝不回收（fail-closed）
rm -f "$LP/dyn/get-wXp1.json"   # stub .json 优先于 .err：不删会走不到查询失败分支（仍是 §59c 的活锁）
printf '{"error":{"code":"io_error","message":"mocked pane get failure"},"id":"cli:test"}\n' > "$LP/dyn/get-wXp1.err"
out="$( cd "$LP" && PATH="$STUB:$PATH" HERDR_DYN_DIR="$LP/dyn" bash qwbuddy/bin/qwb-lock.sh acquire --owner me 2>&1 )"; rc=$?
{ [[ "$rc" -eq 1 ]] && printf '%s' "$out" | grep -q '无法判活' && cmp -s "$LK/owner" "$LP/owner.snap"; } \
  && ok "查询报错不回收（fail-closed）且 owner 字节不变" || { bad "查询失败竟回收/放行（rc=${rc}）"; }
# 59e（失败路径）herdr 不在 PATH → 拒绝不回收
out="$( cd "$LP" && PATH='/usr/bin:/bin' bash qwbuddy/bin/qwb-lock.sh acquire --owner me 2>&1 )"; rc=$?
{ [[ "$rc" -eq 1 ]] && printf '%s' "$out" | grep -q '无法判活' && cmp -s "$LK/owner" "$LP/owner.snap"; } \
  && ok "herdr 不在 PATH：拒绝不回收（fail-closed）" || { bad "无 herdr 竟回收（rc=${rc}）"; }

echo "== 60. 孤儿 --block 不消费唤醒（主控锁复核）=="
OP="$TMP/orphanproj"; mkdir -p "$OP"; bash "$ROOT/bin/qwb-init.sh" "$OP" >/dev/null
mkdir "$OP/qwbuddy/.controller.lock"; printf '2020-01-01T00:00:00Z wX:p1\n' > "$OP/qwbuddy/.controller.lock/owner"
mk_orphan_ticket() { printf '# o\nstate: running\ndone: 新进展待消费\n' > "$OP/tasks/2099-01-01-orphan.md"; }
mk_orphan_ticket
( cd "$OP" && PATH="$STUB:$PATH" HERDR_PANE_ID=wX:p2 bash qwbuddy/bin/qwb-wake.sh --project "$OP" --block --max-ms 5000 ) >/dev/null 2>&1; rc=$?
{ [[ "$rc" -eq 0 ]] && ! grep -q '^wake:' "$OP/tasks/2099-01-01-orphan.md"; } \
  && ok "锁主≠本进程：孤儿 --block exit 0 不写 wake 行" || { bad "孤儿竟消费唤醒（rc=${rc}）"; }
mk_orphan_ticket
( cd "$OP" && PATH="$STUB:$PATH" HERDR_PANE_ID=wX:p1 bash qwbuddy/bin/qwb-wake.sh --project "$OP" --block --max-ms 5000 ) >/dev/null 2>&1; rc=$?
{ [[ "$rc" -eq 2 ]] && grep -q '^wake:' "$OP/tasks/2099-01-01-orphan.md"; } \
  && ok "锁主=本进程：正常消费（rc=2 + wake 行）" || { bad "锁主路径不对（rc=${rc}）"; }
mk_orphan_ticket
( cd "$OP" && PATH="$STUB:$PATH" env -u HERDR_PANE_ID bash qwbuddy/bin/qwb-wake.sh --project "$OP" --block --max-ms 5000 ) >/dev/null 2>&1; rc=$?
{ [[ "$rc" -eq 2 ]] && grep -c '^wake:' "$OP/tasks/2099-01-01-orphan.md" | grep -q '^1$'; } \
  && ok "HERDR_PANE_ID 未设：跳过复核照常消费（rc=2）" || { bad "无 HERDR_PANE_ID 路径不对（rc=${rc}）"; }

echo "== 61. 一轮一条投递 + 投递失败一行不写 =="
BP2="$TMP/batchproj"; mkdir -p "$BP2"; bash "$ROOT/bin/qwb-init.sh" "$BP2" >/dev/null
for i in 1 2 3; do
  printf '# b%s\nstate: running\ndone: 批量票 %s 的进展行\n' "$i" "$i" > "$BP2/tasks/2099-01-0$i-b$i.md"
done
: > "$STUBLOG"
( cd "$BP2" && PATH="$STUB:$PATH" bash qwbuddy/bin/qwb-wake.sh --once --pane wX:p1 ) >/dev/null 2>&1
nrun="$(grep -c '^herdr pane run wX:p1 看账本' "$STUBLOG" || true)"
runline="$(grep '^herdr pane run wX:p1 看账本' "$STUBLOG" | head -1)"
{ [[ "$nrun" -eq 1 ]] \
  && printf '%s' "$runline" | grep -q '2099-01-01-b1' && printf '%s' "$runline" | grep -q '2099-01-02-b2' \
  && printf '%s' "$runline" | grep -q '2099-01-03-b3' \
  && printf '%s' "$runline" | grep -q 'done: 批量票 1 的进展行' && printf '%s' "$runline" | grep -q 'done: 批量票 3 的进展行' \
  && [[ "$(grep -c '^wake:' "$BP2/tasks/2099-01-01-b1.md")" -eq 1 ]] \
  && [[ "$(grep -c '^wake:' "$BP2/tasks/2099-01-02-b2.md")" -eq 1 ]] \
  && [[ "$(grep -c '^wake:' "$BP2/tasks/2099-01-03-b3.md")" -eq 1 ]]; } \
  && ok "三票一轮恰好 1 条 pane run，文本含三个文件名与各自 done 行，三票各写一行 wake" \
  || bad "批量投递不对（nrun=${nrun}）：${runline:0:200}"
# 失败路径：投递失败 → 三票均无新 wake 行、退出码 0
for i in 1 2 3; do sed -i '' '/^wake:/d' "$BP2/tasks/2099-01-0$i-b$i.md"; done
out="$( cd "$BP2" && PATH="$STUB:$PATH" HERDR_FAIL=run bash qwbuddy/bin/qwb-wake.sh --once --pane wX:p1 2>&1 )"; rc=$?
{ [[ "$rc" -eq 0 ]] && ! grep -q '^wake:' "$BP2/tasks/2099-01-01-b1.md" \
  && ! grep -q '^wake:' "$BP2/tasks/2099-01-02-b2.md" && ! grep -q '^wake:' "$BP2/tasks/2099-01-03-b3.md"; } \
  && ok "投递失败：三票一行 wake 都不写、主循环不死（rc=0）" || bad "失败路径写了 wake 或 rc≠0（rc=${rc}）"

echo "== 62. REWAKE 兜底只对 running（blocked/needs-decision 等裁决不重叫）=="
RWP="$TMP/rewakeproj"; mkdir -p "$RWP"; bash "$ROOT/bin/qwb-init.sh" "$RWP" >/dev/null
RUNFP="$(printf 'running\n' | shasum | cut -d' ' -f1)"
NDFP="$(printf 'needs-decision\n' | shasum | cut -d' ' -f1)"
printf '# rw-r\nstate: running\nwake: 2000-01-01T00:00:00Z state=running fp=%s\n' "$RUNFP" > "$RWP/tasks/2099-01-01-rwr.md"
printf '# rw-n\nstate: needs-decision\nwake: 2000-01-01T00:00:00Z state=needs-decision fp=%s\n' "$NDFP" > "$RWP/tasks/2099-01-02-rwn.md"
printf '#!/usr/bin/env bash\necho 99999999999999\n' > "$RWP/far.sh"; chmod +x "$RWP/far.sh"
out="$( cd "$RWP" && PATH="$STUB:$PATH" QWB_NOW_MS_CMD="$RWP/far.sh" bash qwbuddy/bin/qwb-wake.sh --once --pane wX:p1 2>&1 )"
{ printf '%s' "$out" | grep -q '跳过：2099-01-02-rwn' && printf '%s' "$out" | grep -q '等裁决' \
  && [[ "$(grep -c '^wake:' "$RWP/tasks/2099-01-02-rwn.md")" -eq 1 ]] \
  && [[ "$(grep -c '^wake:' "$RWP/tasks/2099-01-01-rwr.md")" -eq 2 ]]; } \
  && ok "needs-decision 超期不重叫（跳过·等裁决），running 超期重叫" \
  || bad "REWAKE 收窄不对：out=${out:0:200}"
runline="$(grep '^herdr pane run wX:p1 看账本' "$STUBLOG" | tail -1)"
printf '%s' "$runline" | grep -q '2099-01-01-rwr' && ! printf '%s' "$runline" | grep -q '2099-01-02-rwn' \
  && ok "重叫投递文本只含 running 票" || bad "重叫文本混入 needs-decision"
# --block 同一构造：exit 2 且摘要只含 running 那张（「跳过：… 等裁决」说明行合法存在，
# 只断言「看账本：」摘要行本身不含 needs-decision 那张）
printf '# rw-r\nstate: running\nwake: 2000-01-01T00:00:00Z state=running fp=%s\n' "$RUNFP" > "$RWP/tasks/2099-01-01-rwr.md"
blk_out="$( cd "$RWP" && PATH="$STUB:$PATH" QWB_NOW_MS_CMD="$RWP/far.sh" env -u HERDR_PANE_ID bash qwbuddy/bin/qwb-wake.sh --project "$RWP" --block --max-ms 999999999 2>&1 )"; rc=$?
blk_summary="$(printf '%s\n' "$blk_out" | grep '^看账本：' | tail -1)"
{ [[ "$rc" -eq 2 ]] && printf '%s' "$blk_summary" | grep -q '2099-01-01-rwr' \
  && ! printf '%s' "$blk_summary" | grep -q '2099-01-02-rwn'; } \
  && ok "--block 同构造：rc=2 且摘要只含 running" || { bad "--block REWAKE 收窄不对（rc=${rc}）：${blk_out:0:200}"; }

echo "== 63. worktree 初始化钩子 QWB_WORKTREE_SETUP =="
GP2="$TMP/wtproj"; mkdir -p "$GP2"
( cd "$GP2" && git init -q && git config user.email t@t && git config user.name t && git commit -q --allow-empty -m init )
bash "$ROOT/bin/qwb-init.sh" "$GP2" >/dev/null
mk_wt_task() { # $1=id
cat > "$GP2/tasks/2099-01-01-$1.md" <<EOF
# $1
state: running

## 1. 验收场景

### user_正常
Given git 项目
When  派发
Then  钩子执行
### user_失败
Given 钩子非 0
When  派发
Then  拒绝派发
EOF
}
mk_wt_task wtsetup
# 场景要求钩子 cwd 在副本物理路径里（pwd -P）；副本派发时才创建，物理路径（/var vs /private/var）
# 事先不可知——钩子把 pwd -P 写进文件，派发后与副本物理路径比对，语义等价
printf "QWB_WORKTREE_SETUP='pwd -P > phys-path.txt && echo run >> setup-count.txt'\n" >> "$GP2/qwbuddy/config.sh"
rm -rf "$GP2/qwbuddy/.controller.lock"
( cd "$GP2" && PATH="$STUB:$PATH" HERDR_PANE_ID=wtest:wt bash qwbuddy/bin/qwb-run.sh --task wtsetup --worker pi ) >/dev/null 2>&1; rc=$?
wt_phys="$(cd "$GP2/.worktrees/wtsetup" && pwd -P)"
{ [[ "$rc" -eq 0 ]] && [[ "$(wc -l < "$GP2/.worktrees/wtsetup/setup-count.txt" | tr -d ' ')" -eq 1 ]] \
  && [[ "$(cat "$GP2/.worktrees/wtsetup/phys-path.txt")" == "$wt_phys" ]]; } \
  && ok "首次派发（新建副本）：钩子在副本物理目录执行恰一次" || { bad "钩子未执行/多次/cwd 不符（rc=${rc}）"; }
# 再次派发（复用副本）→ 钩子不再执行
( cd "$GP2" && PATH="$STUB:$PATH" HERDR_PANE_ID=wtest:wt bash qwbuddy/bin/qwb-run.sh --task wtsetup --worker pi ) >/dev/null 2>&1; rc=$?
[[ "$(wc -l < "$GP2/.worktrees/wtsetup/setup-count.txt" | tr -d ' ')" -eq 1 ]] \
  && ok "复用副本再派发：钩子不再执行（计数仍 1）" || bad "复用副本竟重跑钩子"
# 失败路径：钩子非 0 → 拒绝派发、无 dispatch 行、无 tab/agent、副本保留
mk_wt_task wtfail
printf "QWB_WORKTREE_SETUP='exit 3'\n" >> "$GP2/qwbuddy/config.sh"
: > "$STUBLOG"
out="$( cd "$GP2" && PATH="$STUB:$PATH" HERDR_PANE_ID=wtest:wt bash qwbuddy/bin/qwb-run.sh --task wtfail --worker pi 2>&1 )"; rc=$?
{ [[ "$rc" -ne 0 ]] && printf '%s' "$out" | grep -q 'worktree 初始化失败' && printf '%s' "$out" | grep -q '3' \
  && ! grep -q '^dispatch:' "$GP2/tasks/2099-01-01-wtfail.md" \
  && ! grep -q 'tab create' "$STUBLOG" && ! grep -q 'agent start' "$STUBLOG" \
  && [[ -d "$GP2/.worktrees/wtfail" ]]; } \
  && ok "钩子失败：拒绝派发（退出码 3 上报）、零副作用、副本保留" || { bad "钩子失败处理不对（rc=${rc}）：${out:0:200}"; }

echo "== 64. 工人丢失：status 标出、值守只叫一次、shell 算丢失、在/未知不算 =="
WLP="$TMP/lostproj"; mkdir -p "$WLP"; bash "$ROOT/bin/qwb-init.sh" "$WLP" >/dev/null
LFP="$(printf 'running\ndone: 完成一半' | shasum | cut -d' ' -f1)"   # 实现指纹输入无尾随换行
mk_lost_ticket() {
  # 种子 wake 行用新鲜时间戳：2020 年会被 REWAKE 超期判定合法重叫，破坏「指纹一致不重叫」的对照
  printf '# lost\nstate: running\ndone: 完成一半\ndispatch: 2020-01-01T00:00:00Z worker=pi agent=qwb-lost pane=wX:p9 dir=/tmp\nwake: %s state=running fp=%s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$LFP" > "$WLP/tasks/2099-01-01-lost.md"
}
mk_lost_ticket
out="$( cd "$WLP" && PATH="$STUB:$PATH" bash qwbuddy/bin/qwb-status.sh 2>&1 )"
printf '%s' "$out" | grep -q '工人丢失: pane wX:p9' \
  && ok "pane 查不到 → status 标「工人丢失: pane wX:p9」" || { bad "status 未标丢失"; }
: > "$STUBLOG"
( cd "$WLP" && PATH="$STUB:$PATH" bash qwbuddy/bin/qwb-wake.sh --once --pane wX:p1 ) >/dev/null 2>&1
runline="$(grep '^herdr pane run wX:p1 看账本' "$STUBLOG" | tail -1)"
{ printf '%s' "$runline" | grep -q '2099-01-01-lost' && printf '%s' "$runline" | grep -q '工人丢失' \
  && [[ "$(grep -c '^wake:' "$WLP/tasks/2099-01-01-lost.md")" -eq 2 ]]; } \
  && ok "工人一消失指纹变一次：第一轮叫一次并写 wake 行" || { bad "丢失轮没叫或没写行"; }
out="$( cd "$WLP" && PATH="$STUB:$PATH" bash qwbuddy/bin/qwb-wake.sh --once --pane wX:p1 2>&1 )"
{ printf '%s' "$out" | grep -q '跳过：2099-01-01-lost' \
  && [[ "$(grep -c '^wake:' "$WLP/tasks/2099-01-01-lost.md")" -eq 2 ]]; } \
  && ok "第二轮指纹未变：跳过且无新 wake 行（沿用去重）" || bad "丢失后反复重叫"
# pane 在但 agent 空（退回 shell）也算丢失
mk_lost_ticket
mkdir -p "$WLP/dyn"; sed "s|w8Z:pY|wX:p9|g" "$FIXDIR/pane-get-shell.json" > "$WLP/dyn/get-wXp9.json"
out="$( cd "$WLP" && PATH="$STUB:$PATH" HERDR_DYN_DIR="$WLP/dyn" bash qwbuddy/bin/qwb-status.sh 2>&1 )"
printf '%s' "$out" | grep -q '工人丢失: pane wX:p9' \
  && ok "pane 在但无 agent（退回 shell）→ 同样标工人丢失" || bad "shell 态未标丢失"
# 工人在（带 agent 字段）→ 不算丢失；指纹与不做判定时一致（对照）
mk_lost_ticket
sed "s|w8Z:pY|wX:p9|g" "$FIXDIR/pane-get-shell.json" | sed 's|"agent_status":"unknown"|"agent":"pi","agent_status":"idle"|' > "$WLP/dyn/get-wXp9.json"
out="$( cd "$WLP" && PATH="$STUB:$PATH" HERDR_DYN_DIR="$WLP/dyn" bash qwbuddy/bin/qwb-status.sh 2>&1 )"
printf '%s' "$out" | grep -q '工人丢失' && bad "工人健在竟标丢失" || ok "工人在（agent 字段非空）不标丢失"
( cd "$WLP" && PATH="$STUB:$PATH" HERDR_DYN_DIR="$WLP/dyn" bash qwbuddy/bin/qwb-wake.sh --once --pane wX:p1 ) >/dev/null 2>&1
{ [[ "$(grep -c '^wake:' "$WLP/tasks/2099-01-01-lost.md")" -eq 1 ]]; } \
  && ok "对照：工人在 → 指纹与不做丢失判定一致，不再叫" || bad "工人在却因丢失指纹多叫一次"
# 查询失败（非 pane_not_found）→ 工人状态未知：status 标未知、值守不当丢失
mk_lost_ticket
rm -f "$WLP/dyn/get-wXp9.json"   # stub .json 优先于 .err：不删会走不到查询失败分支
printf '{"error":{"code":"io_error","message":"mocked pane get failure"},"id":"cli:test"}\n' > "$WLP/dyn/get-wXp9.err"
out="$( cd "$WLP" && PATH="$STUB:$PATH" HERDR_DYN_DIR="$WLP/dyn" bash qwbuddy/bin/qwb-status.sh 2>&1 )"
printf '%s' "$out" | grep -q '工人状态未知' \
  && ok "查询失败 → status 打印「工人状态未知」" || bad "查询失败未标未知"
wake_err="$( cd "$WLP" && PATH="$STUB:$PATH" HERDR_DYN_DIR="$WLP/dyn" bash qwbuddy/bin/qwb-wake.sh --once --pane wX:p1 2>&1 >/dev/null )"
{ [[ "$(grep -c '^wake:' "$WLP/tasks/2099-01-01-lost.md")" -eq 1 ]] && printf '%s' "$wake_err" | grep -q '无法确认工人状态'; } \
  && ok "查询失败 → 值守不当丢失（不新写 wake 行、stderr 一行说明）" || bad "查询失败被当丢失或没说明"

echo "== 65. --task 精确 id 优先；worktree finish 只记本票账本 =="
mk_foo_task() { # $1=id
cat > "$GP2/tasks/2099-01-02-$1.md" <<EOF
# $1
state: running

## 1. 验收场景

### user_正常
Given 多张相似票
When  精确 id 派发
Then  唯一命中
### user_失败
Given 模糊 id
When  派发
Then  多份拒绝
EOF
}
mk_foo_task foo; mk_foo_task foo-bar
( cd "$GP2" && PATH="$STUB:$PATH" HERDR_PANE_ID=wtest:wt bash qwbuddy/bin/qwb-run.sh --task foo --worker pi --here ) >/dev/null 2>&1; rc=$?
{ [[ "$rc" -eq 0 ]] && grep -q '^dispatch:' "$GP2/tasks/2099-01-02-foo.md" \
  && ! grep -q '^dispatch:' "$GP2/tasks/2099-01-02-foo-bar.md"; } \
  && ok "--task foo 精确命中 foo（dispatch 落对文件）" || { bad "--task foo 行为不对（rc=${rc}）"; }
( cd "$GP2" && PATH="$STUB:$PATH" HERDR_PANE_ID=wtest:wt bash qwbuddy/bin/qwb-run.sh --task foo-bar --worker pi --here ) >/dev/null 2>&1; rc=$?
[[ "$rc" -eq 0 ]] && grep -q '^dispatch:' "$GP2/tasks/2099-01-02-foo-bar.md" \
  && ok "--task foo-bar 命中 foo-bar" || bad "--task foo-bar 行为不对（rc=${rc}）"
out="$( cd "$GP2" && PATH="$STUB:$PATH" HERDR_PANE_ID=wtest:wt bash qwbuddy/bin/qwb-run.sh --task fo --worker pi --here 2>&1 )"; rc=$?
{ [[ "$rc" -ne 0 ]] && printf '%s' "$out" | grep -q '匹配到 2 份'; } \
  && ok "--task fo 仍报「匹配到 2 份」拒绝" || bad "模糊 id 未拒绝（rc=${rc}）"
# worktree finish 精确命中本票任务书；目标必须是本仓登记的 worktree
git -C "$GP2" worktree add -q -b foo "$GP2/.worktrees/foo" HEAD
( cd "$GP2" && bash qwbuddy/bin/qwb-worktree.sh finish foo --keep=测试保留 ) >/dev/null 2>&1; rc=$?
{ [[ "$rc" -eq 0 ]] && grep -q '^worktree: keep' "$GP2/tasks/2099-01-02-foo.md" \
  && ! grep -q '^worktree:' "$GP2/tasks/2099-01-02-foo-bar.md"; } \
  && ok "worktree finish 精确命中 foo（记账落对文件）" || { bad "finish 记账落点不对（rc=${rc}）"; }

echo "== 66. agent 名塌缩兜底（中文 id → qwb-<sha1 前 8 位>）=="
ANP="$TMP/agentname"; mkdir -p "$ANP"; bash "$ROOT/bin/qwb-init.sh" "$ANP" >/dev/null
mk_an_task() { # $1=id
cat > "$ANP/tasks/2099-01-01-$1.md" <<EOF
# $1
state: running

## 1. 验收场景

### user_正常
Given 中文名票
When  派发
Then  agent 名兜底
### user_失败
Given 同名
When  再派
Then  不撞名
EOF
}
mk_an_task "场景完善-01真实闭环"
: > "$STUBLOG"
( cd "$ANP" && PATH="$STUB:$PATH" HERDR_PANE_ID=wtest:an bash qwbuddy/bin/qwb-run.sh --task "场景完善-01真实闭环" --worker pi --here ) >/dev/null 2>&1; rc=$?
anline="$(grep 'agent start' "$STUBLOG" | head -1)"
{ [[ "$rc" -eq 0 ]] && printf '%s' "$anline" | grep -Eq 'agent start qwb-[0-9a-f]{8} '; } \
  && ok "中文 id 净化后塌缩 → agent 名兜底为 qwb-<8hex>（${anline:0:60}…）" \
  || bad "中文 id 兜底不对（rc=${rc}，line=${anline:0:80}）"
grep -q '^dispatch: .*agent=qwb-[0-9a-f]\{8\} ' "$ANP/tasks/2099-01-01-场景完善-01真实闭环.md" \
  && ok "dispatch 行记录兜底后的实际 agent 名" || bad "dispatch 行 agent 名不对"
mk_an_task "plain-id"
: > "$STUBLOG"
( cd "$ANP" && PATH="$STUB:$PATH" HERDR_PANE_ID=wtest:an bash qwbuddy/bin/qwb-run.sh --task plain-id --worker pi --here ) >/dev/null 2>&1; rc=$?
grep -q 'agent start qwb-plain-id ' "$STUBLOG" \
  && ok "ASCII id 名字与现状字节一致（qwb-plain-id）" || { bad "ASCII id 名被改动"; }
mk_an_task "named"
: > "$STUBLOG"
( cd "$ANP" && PATH="$STUB:$PATH" HERDR_PANE_ID=wtest:an bash qwbuddy/bin/qwb-run.sh --task named --worker pi --here --name custom ) >/dev/null 2>&1; rc=$?
grep -q 'agent start custom ' "$STUBLOG" \
  && ok "--name custom 仍用 custom（兜底不覆盖显式指定）" || { bad "--name 被兜底覆盖"; }


echo "== 67. init 写 .gitignore（幂等/新建/git status 反证）与 dispatch-rules 落点 qwbuddy/ =="
GIP="$TMP/gitign"; mkdir -p "$GIP"
( cd "$GIP" && git init -q && git config user.email t@t && git config user.name t && printf 'node_modules/\n' > .gitignore && git add -A && git commit -qm init )
gi_run() { bash "$ROOT/bin/qwb-init.sh" "$GIP" 2>&1; }
gi1="$(gi_run)"; gi_rc=$?
{ [[ "$gi_rc" -eq 0 ]] && printf '%s' "$gi1" | grep -q '写入：.gitignore 追加 QW buddy 运行态'; } \
  && ok "init 写 .gitignore：stdout 一行「写入：.gitignore 追加 QW buddy 运行态」" \
  || { bad "init 写 .gitignore 失败（rc=${gi_rc}）"; printf '%s\n' "$gi1"; }
[[ "$(head -1 "$GIP/.gitignore")" == 'node_modules/' ]] \
  && ok "原有条目字节不变（node_modules/ 仍在首行）" || bad "原有 .gitignore 条目被改动"
{ [[ "$(grep -cF '# QW buddy 运行态（qwb-init.sh 写入，勿手改本段）' "$GIP/.gitignore")" == "1" ]] \
  && grep -qxF '.worktrees/' "$GIP/.gitignore" \
  && grep -qxF 'qwbuddy/.controller.lock/' "$GIP/.gitignore" \
  && grep -qxF 'qwbuddy/.watch' "$GIP/.gitignore" \
  && grep -qxF 'qwbuddy/.watch.lock/' "$GIP/.gitignore" \
  && grep -qxF 'qwbuddy/.hook.lock/' "$GIP/.gitignore" \
  && grep -qxF 'qwbuddy/.hook.err' "$GIP/.gitignore" \
  && grep -qxF 'qwbuddy/.pi-watch.err' "$GIP/.gitignore"; } \
  && ok "QW buddy 段恰好一次，含 .worktrees/ 与 Pi 错误日志等七条" \
  || bad "QW buddy 段缺失或重复：$(cat "$GIP/.gitignore")"
gi_sha1="$(shasum "$GIP/.gitignore" | cut -d' ' -f1)"
gi2="$(gi_run)"
{ [[ "$(shasum "$GIP/.gitignore" | cut -d' ' -f1)" == "$gi_sha1" ]] \
  && printf '%s' "$gi2" | grep -q '跳过：.gitignore 已有'; } \
  && ok "幂等：再跑一次 .gitignore 字节不变，stdout「跳过：.gitignore 已有」" \
  || bad "二次 init 不幂等或 stdout 不对"
# 无 .gitignore 的新项目 → 新建且首行即段标记
GIP2="$TMP/gitign2"; mkdir -p "$GIP2"
bash "$ROOT/bin/qwb-init.sh" "$GIP2" >/dev/null
[[ "$(head -1 "$GIP2/.gitignore")" == '# QW buddy 运行态（qwb-init.sh 写入，勿手改本段）' ]] \
  && ok "无 .gitignore 项目：文件被新建且含 QW buddy 段" || bad "新建 .gitignore 不对"
# 失败路径反证：git status 干净 → 删段后 .worktrees 与 .controller.lock 现身（证明段落有效）
( cd "$GIP" && git add -A && git commit -qm install )
bash "$GIP/qwbuddy/bin/qwb-lock.sh" acquire --project "$GIP" --owner "pid:$$" >/dev/null
mkdir -p "$GIP/.worktrees/x"; : > "$GIP/.worktrees/x/w.txt"   # 空目录 git 永不显示，放个文件才真验忽略
gs="$(git -C "$GIP" status --porcelain)"
{ [[ -z "$gs" ]]; } \
  && ok "装完+提交+抢锁+建 .worktrees/x → git status --porcelain 干净" \
  || bad "status 竟然脏：$gs"
perl -i -ne 'print unless /^# QW buddy 运行态/ || /^\.worktrees\/$/ || /^qwbuddy\/\.(controller\.lock\/|watch|watch\.lock\/|hook\.lock\/|hook\.err|pi-watch\.err)$/' "$GIP/.gitignore"
gs="$(git -C "$GIP" status --porcelain)"
{ printf '%s' "$gs" | grep -q 'worktrees' && printf '%s' "$gs" | grep -q '.controller.lock'; } \
  && ok "删掉 QW buddy 段后 .worktrees 与 .controller.lock 在 status 现身（反证段落有效）" \
  || bad "删段后反证失败：$gs"
bash "$GIP/qwbuddy/bin/qwb-lock.sh" release --project "$GIP" >/dev/null
# dispatch-rules 落点：init 拷模板且字节相同；改过不覆盖；读新路径、不回退旧路径
{ cmp -s "$GIP/qwbuddy/dispatch-rules.json" "$ROOT/templates/dispatch-rules.json"; } \
  && ok "qwbuddy/dispatch-rules.json 存在且与模板字节相同" \
  || bad "规则文件缺失或与模板不一致"
printf '{"rules":[],"项目自己改过的规则":true}\n' > "$GIP/qwbuddy/dispatch-rules.json"
gi3="$(gi_run)"
{ grep -qF '项目自己改过的规则' "$GIP/qwbuddy/dispatch-rules.json" \
  && printf '%s' "$gi3" | grep -q '保留：qwbuddy/dispatch-rules.json 已存在，不覆盖'; } \
  && ok "再跑 init 不覆盖项目改过的规则文件（幂等）" \
  || bad "init 覆盖了项目自己的 dispatch-rules.json"
DP3="$TMP/oldpath"; mkdir -p "$DP3/config"
printf '# 简\n' > "$DP3/brief.md"
printf '%s\n' '{"rules":[{"when":"x","worker":"pi"}],"default":{"worker":"pi"}}' > "$DP3/config/dispatch-rules.json"
dp_out="$(cd "$DP3" && TYPESAFE_API_KEY=stub PATH="$DFB:$PATH" bash "$ROOT/bin/qwb-dispatch.sh" brief.md 2>&1 >/dev/null)"; dp_rc=$?
{ [[ "$dp_rc" -eq 0 ]] && printf '%s' "$dp_out" | grep -q 'no rules' \
  && ! printf '%s' "$dp_out" | grep -q '合法 worker'; } \
  && ok "旧路径 config/ 存在而新路径缺失 → 报 no rules（不读旧路径、不做兼容）" \
  || bad "旧路径回退不应发生：rc=${dp_rc}，out=$dp_out"

echo "== 68. 母本仓双配置守卫（lint：双配置质量门必须一致）=="
MRP="$TMP/mrepo"; mkdir -p "$MRP/templates" "$MRP/bin" "$MRP/tasks" "$MRP/docs"
cp "$ROOT"/templates/QWBUDDY.md "$MRP/templates/"
cp "$ROOT"/docs/DESIGN.md "$MRP/docs/"
cp "$ROOT"/bin/qwb-*.sh "$MRP/bin/"
cp "$ROOT"/qwb.config.sh "$MRP/"
mkdir -p "$MRP/qwbuddy"
printf 'QWB_GATE_FAST="fast-999"\nQWB_GATE_FULL="full-999"\n' > "$MRP/qwbuddy/config.sh"
lint_out="$(bash "$ROOT/bin/qwb-lint.sh" --project "$MRP" 2>&1)"; lrc=$?
{ [[ "$lrc" -ne 0 ]] && printf '%s' "$lint_out" | grep -q '质量门不一致' \
  && printf '%s' "$lint_out" | grep -q 'fast-999' && printf '%s' "$lint_out" | grep -q 'full-999' \
  && printf '%s' "$lint_out" | grep -q 'qwbuddy/config.sh=fast-999'; } \
  && ok "双配置门值不同 → lint FAIL 且打印两边的值" \
  || { bad "双配置守卫未按预期 FAIL（rc=${lrc}）"; printf '%s\n' "$lint_out" | tail -12; }
( . "$ROOT/qwb.config.sh"
  printf 'QWB_GATE_FAST=%s\nQWB_GATE_FULL=%s\n' "$(printf '%q' "$QWB_GATE_FAST")" "$(printf '%q' "$QWB_GATE_FULL")" ) > "$MRP/qwbuddy/config.sh"
lint_out="$(bash "$ROOT/bin/qwb-lint.sh" --project "$MRP" 2>&1)"; lrc=$?
{ [[ "$lrc" -eq 0 ]] && printf '%s' "$lint_out" | grep -q '质量门一致'; } \
  && ok "两份配置门改成相同 → lint PASS" \
  || { bad "同门应 PASS（rc=${lrc}）"; printf '%s\n' "$lint_out" | tail -12; }
rm "$MRP/qwbuddy/config.sh"
lint_out="$(bash "$ROOT/bin/qwb-lint.sh" --project "$MRP" 2>&1)"; lrc=$?
{ [[ "$lrc" -eq 0 ]] && ! printf '%s' "$lint_out" | grep -q '质量门不一致' \
  && ! printf '%s' "$lint_out" | grep -q '双配置'; } \
  && ok "只有一份配置 → 该项不报（其余项不误伤，LINT PASS）" \
  || { bad "单配置不应报双配置项（rc=${lrc}）"; printf '%s\n' "$lint_out" | tail -8; }

echo "== 69. 返工重派：复用既有工人 / 同名在干拒绝 / agent start 失败回滚 =="
RUP="$TMP/reuse"; mkdir -p "$RUP"; bash "$ROOT/bin/qwb-init.sh" "$RUP" >/dev/null
cat > "$RUP/tasks/2099-01-01-reuset.md" <<'EOF'
# reuset
state: blocked

## 1. 验收场景

### user_正常
Given 同名工人空闲
When  再派
Then  复用不新开窗口
### user_失败
Given 同名工人忙碌
When  再派
Then  拒绝且零副作用
EOF
mkdir -p "$RUP/dyn"
# 同名 idle 工人片场：真录 agent-get-cmd.json 改为本票真实 worker、物理 cwd 与 workspace。
ru_physical="$(cd "$RUP" && pwd -P)"
sed -e 's/wAB:p3/wX:p5/g' -e 's/wAB:t3/wX:t5/g' -e 's/wAB/wX/g' \
  -e "s|/private/tmp|$ru_physical|g" -e 's/"agent":"cmd"/"agent":"pi","name":"qwb-reuset"/' \
  "$FIXDIR/agent-get-cmd.json" | sed '/^#/d' > "$RUP/dyn/agent-get-qwbreuset.json"
sed -e 's/w8Z:pY/wX:p5/g' -e 's/w8Z:tR/wX:t5/g' -e 's/w8Z/wX/g' \
  -e "s|/private/tmp/qwb02probe/untrusted-dir|$ru_physical|g" \
  -e 's/"agent_status":"unknown"/"agent":"pi","agent_status":"idle"/' \
  "$FIXDIR/pane-get-shell.json" | sed '/^#/d' > "$RUP/dyn/get-wXp5.json"
printf '{"result":{"workspaces":[{"workspace_id":"wX","focused":true,"worktree":{"repo_root":"%s"}}]}}\n' \
  "$ru_physical" > "$RUP/dyn/workspace-list.json"
ru_task="$RUP/tasks/2099-01-01-reuset.md"
printf 'dispatch: historical worker=pi agent=qwb-reuset pane=wX:p5 dir=%s\n' "$ru_physical" >> "$ru_task"
# (a) idle → 复用：无 tab create、无 agent start、有 agent prompt，dispatch pane=现有 pane
: > "$STUBLOG"; rm -rf "$RUP/qwbuddy/.controller.lock"
ru_out="$( cd "$RUP" && PATH="$STUB:$PATH" HERDR_PANE_ID=wtest:ru HERDR_DYN_DIR="$RUP/dyn" \
  bash qwbuddy/bin/qwb-run.sh --task reuset --worker pi --here --accept-new-scenarios 2>&1 )"; ru_rc=$?
{ [[ "$ru_rc" -eq 0 ]] && ! grep -q 'tab create' "$STUBLOG" && ! grep -q 'agent start' "$STUBLOG" \
  && grep -q 'agent prompt qwb-reuset ' "$STUBLOG" \
  && grep -q '这是返工/续派' "$STUBLOG" \
  && printf '%s' "$ru_out" | grep -q '复用既有工人 qwb-reuset（pane wX:p5）' \
  && [[ "$(grep '^dispatch:' "$ru_task" | tail -1)" == *"agent=qwb-reuset pane=wX:p5 "* ]]; } \
  && ok "同名 idle 工人 → 复用（不建 tab、不 start，dispatch 落现有 pane，stdout 含「复用既有工人」）" \
  || { bad "复用路径不对（rc=${ru_rc}）"; printf '%s\n' "$ru_out"; cat "$STUBLOG"; }
# (b) 同名工人还在 working → 拒绝，无新 dispatch 行，无 prompt/start/tab create
perl -pi -e 's/"agent_status":"idle"/"agent_status":"working"/' "$RUP/dyn/agent-get-qwbreuset.json"
disp_before="$(grep -c '^dispatch:' "$ru_task")"
: > "$STUBLOG"; rm -rf "$RUP/qwbuddy/.controller.lock"
ru_out="$( cd "$RUP" && PATH="$STUB:$PATH" HERDR_PANE_ID=wtest:ru HERDR_DYN_DIR="$RUP/dyn" \
  bash qwbuddy/bin/qwb-run.sh --task reuset --worker pi --here 2>&1 )"; ru_rc=$?
{ [[ "$ru_rc" -ne 0 ]] && printf '%s' "$ru_out" | grep -q '还在 working' \
  && [[ "$(grep -c '^dispatch:' "$ru_task")" -eq "$disp_before" ]] \
  && ! grep -q 'agent prompt' "$STUBLOG" && ! grep -q 'agent start' "$STUBLOG" \
  && ! grep -q 'tab create' "$STUBLOG"; } \
  && ok "同名工人还在 working → 拒绝派发（无新 dispatch 行、零 herdr 副作用）" \
  || { bad "working 拒绝路径不对（rc=${ru_rc}）"; printf '%s\n' "$ru_out"; cat "$STUBLOG"; }
# (c) 无同名工人 + agent start 失败 → 关刚建 tab、回滚 dispatch 行、exit 1 上报原始错误
rm "$RUP/dyn/agent-get-qwbreuset.json"   # 回到无同名工人：走新开 tab 路径
cp "$FIXDIR/agent-get-error.json" "$RUP/dyn/agent-get-qwbrollback.err"
cat > "$RUP/tasks/2099-01-02-rollback.md" <<'EOF'
# rollback
state: blocked

## 1. 验收场景

### user_正常
Given 工人正常启动
When  派发
Then  正常记账
### user_失败
Given agent start 失败
When  派发
Then  回滚 tab 与 dispatch 行
EOF
rb_task="$RUP/tasks/2099-01-02-rollback.md"
rm -rf "$RUP/qwbuddy/.controller.lock"
( cd "$RUP" && PATH="$STUB:$PATH" HERDR_PANE_ID=wtest:ru HERDR_DYN_DIR="$RUP/dyn" \
  bash qwbuddy/bin/qwb-run.sh --task rollback --worker pi --here ) >/dev/null 2>&1; rb_rc1=$?
[[ "$rb_rc1" -eq 0 ]] || bad "回滚对照：首次正常派发竟失败（rc=${rb_rc1}）"
rb_before="$(wc -l < "$rb_task" | tr -d ' ')"
: > "$STUBLOG"; rm -rf "$RUP/qwbuddy/.controller.lock"
rb_out="$( cd "$RUP" && PATH="$STUB:$PATH" HERDR_PANE_ID=wtest:ru HERDR_DYN_DIR="$RUP/dyn" HERDR_FAIL=start \
  bash qwbuddy/bin/qwb-run.sh --task rollback --worker pi --here 2>&1 )"; rb_rc=$?
{ [[ "$rb_rc" -ne 0 ]] && printf '%s' "$rb_out" | grep -q 'agent_name_taken' \
  && printf '%s' "$rb_out" | grep -q 'agent start 失败' \
  && [[ "$(wc -l < "$rb_task" | tr -d ' ')" -eq "$((rb_before + 2))" ]] \
  && [[ "$(grep -c '^dispatch:' "$rb_task")" -eq 1 ]] \
  && [[ "$(grep -c '^not-sent:' "$rb_task")" -eq 1 ]] \
  && grep -q '^blocked: .*派发投递失败' "$rb_task" \
  && grep -q 'tab create' "$STUBLOG" && grep -q 'tab close w93:t7' "$STUBLOG" \
  && ! grep -q 'agent prompt' "$STUBLOG"; } \
  && ok "agent start 失败（agent_name_taken）→ 关本次 tab、历史 dispatch 保留、本次原位标记未投递、exit 1 原始错误上报" \
  || { bad "回滚路径不对（rc=${rb_rc}）"; printf '%s\n' "$rb_out"; cat "$STUBLOG"; }

echo "== 70. 开局点名改用 qwb-status.sh（省 token）=="
q1="$(awk '/^## 1\. 开局点名/{f=1;next} /^## 2\./{f=0} f' "$ROOT/templates/QWBUDDY.md")"
{ printf '%s' "$q1" | grep -q 'qwb-status.sh' && printf '%s' "$q1" | grep -q '只读未结项' \
  && ! printf '%s' "$q1" | grep -q '读每份头部'; } \
  && ok "QWBUDDY.md §1 含 qwb-status.sh 与「只读未结项」，不再含「读每份头部」" \
  || bad "§1 点名文案不对"
! grep -q '读每份头部' "$ROOT/templates/QWBUDDY.md" \
  && ok "QWBUDDY.md 全文不再有「读每份头部」旧文案" || bad "旧文案仍在"
for hf in claude-hook agents-hook; do
  h2="$(grep '^[0-9]\.' "$ROOT/templates/$hf.md" | sed -n 2p)"
  printf '%s' "$h2" | grep -q 'qwb-status.sh' \
    && ok "$hf.md 第 2 条含 qwb-status.sh" \
    || bad "$hf.md 第 2 条未改：$h2"
done
lint_out="$(bash "$ROOT/bin/qwb-lint.sh" --project "$ROOT" 2>&1)"; lrc=$?
{ [[ "$lrc" -eq 0 ]] && printf '%s' "$lint_out" | grep -q 'LINT PASS'; } \
  && ok "qwb-lint.sh 第 1 项仍 PASS（本仓 LINT PASS）" \
  || { bad "本仓 lint 不应受影响（rc=${lrc}）"; printf '%s\n' "$lint_out" | tail -8; }

echo "== 71. Pi 扩展单元测试（qwb-watch.ts 行为，不依赖 pi 进程）=="
run_pi_ext() {
  local probe_dir="$TMP/pi-ext-capability" probe_file runner=()
  mkdir -p "$probe_dir" || return 1
  probe_file="$probe_dir/probe.ts"
  printf 'export const qwbProbe: number = 1;\n' > "$probe_file" || return 1
  # 只探测 TS 加载能力，绝不以实际测试结果决定换运行器。
  local node_probe='import { pathToFileURL } from "node:url"; import(pathToFileURL(process.argv[1]).href).then(m => process.exit(m.qwbProbe === 1 ? 0 : 1), () => process.exit(1))'
  if command -v node >/dev/null 2>&1; then
    if node --input-type=module -e "$node_probe" "$probe_file" >/dev/null 2>&1; then
      runner=(node)
    elif node --experimental-strip-types --input-type=module -e "$node_probe" "$probe_file" >/dev/null 2>&1; then
      runner=(node --experimental-strip-types)
    fi
  fi
  if [[ "${#runner[@]}" -eq 0 ]] && command -v bun >/dev/null 2>&1 &&
    bun "$probe_file" >/dev/null 2>&1; then
    runner=(bun)
  fi
  if [[ "${#runner[@]}" -eq 0 ]]; then
    echo "pi-ext 测试缺少可加载 TypeScript 的 Node/Bun 执行器" >&2
    return 1
  fi
  "${runner[@]}" "$ROOT/tests/pi-ext.test.mjs" 2>&1
}
extout="$(run_pi_ext)"; extrc=$?
{ [[ $extrc -eq 0 ]] && printf '%s' "$extout" | grep -q 'pi-ext tests: 15 passed'; } \
  && ok "pi 扩展单元测试 15 项通过（锁主/晚获锁/退出交付/退避/清理）" \
  || { bad "pi 扩展单元测试失败（rc=$extrc）"; printf '%s\n' "$extout"; }
# TS 语法门（票 §2：tsc --noEmit 本机无 → 用 node type-stripping 转译检查，转译失败即门失败）
if command -v node >/dev/null 2>&1; then
  chk node -e 'const{pathToFileURL}=require("node:url");import(pathToFileURL(process.argv[1]).href).then(()=>process.exit(0),e=>{console.error(String((e&&e.message)||e));process.exit(1)})' "$ROOT/templates/pi-extensions/qwb-watch.ts" \
    || bad "qwb-watch.ts 无法被 node type-stripping 转译"
else
  echo "SKIP  本机无 node，跳过 TS 转译门"
fi

echo "== 72. qwb-init.sh 装 Pi 扩展：新建 / 幂等不重写 / 备份覆盖 =="
P3="$TMP/piext-proj"; mkdir -p "$P3"
DST="$P3/.pi/extensions/qwb-watch.ts"
out="$(bash "$ROOT/bin/qwb-init.sh" "$P3" 2>&1)"; rc=$?
{ [[ $rc -eq 0 ]] && [[ -f "$DST" ]] && printf '%s' "$out" | grep -q '重启 pi 或 /reload'; } \
  && ok "init 新建 .pi/extensions/qwb-watch.ts 并提示重启生效" \
  || { bad "init 新建扩展失败（rc=$rc）"; }
mt() { stat -f %m "$1" 2>/dev/null || stat -c %Y "$1"; }
m_before="$(mt "$DST")"; sleep 1
out="$(bash "$ROOT/bin/qwb-init.sh" "$P3" 2>&1)"; rc=$?
{ [[ $rc -eq 0 ]] && [[ "$(mt "$DST")" == "$m_before" ]] \
    && printf '%s' "$out" | grep -q '内容一致' && [[ ! -f "$DST.bak" ]]; } \
  && ok "init 幂等：同内容不重写（mtime 不变）、无备份" \
  || { bad "init 幂等不对（rc=$rc，mtime 前=$m_before 后=$(mt "$DST")）"; }
printf '\n// 项目本地改动\n' >> "$DST"
out="$(bash "$ROOT/bin/qwb-init.sh" "$P3" 2>&1)"; rc=$?
{ [[ $rc -eq 0 ]] && [[ -f "$DST.bak" ]] && grep -q '项目本地改动' "$DST.bak" \
    && ! grep -q '项目本地改动' "$DST" \
    && printf '%s' "$out" | grep -q '备份为 qwb-watch.ts.bak'; } \
  && ok "init 遇不同内容：备份 .bak 后覆盖、stdout 说明" \
  || { bad "init 备份覆盖不对（rc=$rc，out=$out）"; }

echo "== 73. status 值守第四态 pi-ext：pid 活 → pi-ext，pid 死 → 未运行 =="
DYN="$TMP/herdr-dyn-s69"; mkdir -p "$DYN"; rm -f "$TMP/qwbuddy/.watch"; rm -rf "$TMP/qwbuddy/.hook.lock"
stat69() { ( cd "$TMP" && PATH="$STUB:$PATH" HERDR_DYN_DIR="$DYN" HERDR_WORKSPACE_ID=wtestW \
    bash qwbuddy/bin/qwb-status.sh ); }
( exec sleep 30 ) & wpid=$!
printf 'kind=pi-ext pid=%s started=x cmd=y\n' "${wpid}" > "$TMP/qwbuddy/.watch"
out="$(stat69)"
printf '%s' "$out" | grep -q "值守：pi-ext（pid ${wpid}）" \
  && ok "status：.watch kind=pi-ext 活 pid → 值守：pi-ext（pid …）" \
  || { bad "status 未报 pi-ext"; printf '%s\n' "$out"; }
kill "${wpid}" 2>/dev/null; wait "${wpid}" 2>/dev/null
out="$(stat69)"
{ printf '%s' "$out" | grep -q '值守：未运行' && printf '%s' "$out" | grep -q 'pi-ext'; } \
  && ok "status：pi-ext pid 死 → 值守：未运行" \
  || { bad "status pid 死未报未运行"; printf '%s\n' "$out"; }
rm -f "$TMP/qwbuddy/.watch"; rm -rf "$DYN"

echo "== 74. 生产运行时返修定向负例 =="
runtime_out="$(bash "$ROOT/tests/runtime-readiness.sh" 2>&1)"; runtime_rc=$?
if [[ "$runtime_rc" -eq 0 ]] && printf '%s' "$runtime_out" | grep -q 'RUNTIME READINESS PASS' &&
  [[ "$(printf '%s\n' "$runtime_out" | grep -c '^PASS  ')" -eq 20 ]]; then
  ok "锁竞争/生命周期、投递失败与身份拒绝定向测试 20 项通过"
else
  bad "运行时定向测试失败（rc=$runtime_rc)"
  printf '%s\n' "$runtime_out"
fi

echo "== 75. 生产边界定向回归 =="
if bash "$ROOT/tests/boundary-readiness.sh" > "$TMP/boundary-readiness.log" 2>&1; then
  ok "生产边界定向回归通过"
else
  bad "生产边界定向回归失败"
  grep -E '^(FAIL|BOUNDARY)' "$TMP/boundary-readiness.log" >&2 || true
fi

echo "== 76. 生产生命周期定向回归 =="
if bash "$ROOT/tests/lifecycle-readiness.sh" > "$TMP/lifecycle-readiness.log" 2>&1; then
  ok "生产生命周期真实子进程与跨 workspace 定向回归通过"
else
  bad "生产生命周期定向回归失败"
  grep -E '^(FAIL|LIFECYCLE|Traceback|AssertionError)' "$TMP/lifecycle-readiness.log" >&2 || true
fi

echo "== 77. 工人配置 argv 与显式迁移定向回归 =="
if python3 "$ROOT/tests/worker-config.py" > "$TMP/worker-config.log" 2>&1; then
  ok "工人配置 argv、提前拒绝与显式迁移定向回归通过"
else
  bad "工人配置定向回归失败"
  cat "$TMP/worker-config.log"
fi


echo "== 78. 按需文档安装与失效路径 =="
if python3 "$ROOT/tests/on-demand-guide.py"; then
  ok "按需文档安装、链接及负例通过"
else
  bad "按需文档安装、链接及负例失败"
fi

echo "== 79. worktree Space 拒绝与部分收尾隔离回归 =="
if python3 "$ROOT/tests/worktree-space.py" > "$TMP/worktree-space.log" 2>&1; then
  ok "Space 登记、身份与收尾失败路径通过"
else
  bad "Space 失败路径回归失败"
  cat "$TMP/worktree-space.log"
fi

# 新节必须加在本行之前
echo
if [[ "$FAILS" -eq 0 ]]; then echo "SMOKE PASS"; exit 0; else echo "SMOKE FAIL（$FAILS 项）"; exit 1; fi
