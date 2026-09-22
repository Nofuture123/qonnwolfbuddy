#!/usr/bin/env bash
# 生产边界定向回归；所有仓库、凭据与假命令仅存在临时目录。
# 断言字符串由 check 的 eval 执行，变量在 eval 时展开。
# shellcheck disable=SC2016,SC2034
set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
INIT="${QWB_BOUNDARY_INIT:-$ROOT/bin/qwb-init.sh}"
DISPATCH="${QWB_BOUNDARY_DISPATCH:-$ROOT/bin/qwb-dispatch.sh}"
WORKTREE="${QWB_BOUNDARY_WORKTREE:-$ROOT/bin/qwb-worktree.sh}"
TMP="$(mktemp -d)" || exit 2
trap 'rm -rf "$TMP"' EXIT
FAILS=0
check() { if eval "$2"; then echo "PASS  $1"; else echo "FAIL  $1"; FAILS=$((FAILS+1)); fi; }

P="$TMP/install"; mkdir -p "$P/.claude"; printf 'user-line\n# QW buddy 运行态（qwb-init.sh 写入，勿手改本段）\n.worktrees/\n' > "$P/.gitignore"
cp "$P/.gitignore" "$TMP/ignore.original"
git -C "$P" init -q; git -C "$P" config user.email test@example.invalid; git -C "$P" config user.name Test
git -C "$P" add .gitignore; git -C "$P" commit -qm initial
runtime_paths=(.worktrees/item qwbuddy/.controller.lock/owner qwbuddy/.watch qwbuddy/.watch.lock/owner qwbuddy/.hook.lock/owner qwbuddy/.hook.err qwbuddy/.pi-watch.err)
mkdir -p "$P/.worktrees" "$P/qwbuddy/.controller.lock" "$P/qwbuddy/.watch.lock" "$P/qwbuddy/.hook.lock"
for path in "${runtime_paths[@]}"; do printf 'runtime\n' > "$P/$path"; done
pre_status="$(git -C "$P" status --short --untracked-files=all -- "${runtime_paths[@]}")"
git -C "$P" check-ignore -q qwbuddy/.controller.lock/owner; pre_controller=$?
git -C "$P" check-ignore -q qwbuddy/.watch; pre_watch=$?
check '不完整旧段会污染 Git 状态' '[[ $pre_controller -ne 0 && $pre_watch -ne 0 ]] && [[ "$pre_status" == *"qwbuddy/.controller.lock/owner"* && "$pre_status" == *"qwbuddy/.watch"* ]]'
mkdir -p "$P/qwbuddy"; printf 'CUSTOM_SETTING=kept\n' > "$P/qwbuddy/config.sh"
cat > "$P/.claude/settings.json" <<'JSON'
{"custom": {"keep": true}, "hooks": {"Stop": [
  {"hooks": [{"type":"command","command":"echo qwb-hook-claude-stop.sh"}]},
  {"hooks": [{"type":"command","command":"# qwb-hook-claude-stop.sh"}]}
]}}
JSON
cp "$P/.claude/settings.json" "$TMP/settings.before"
printf 'custom config\n' > "$P/config.keep"
bash "$INIT" "$P" > "$TMP/init1.log" 2>&1; i1=$?
cp "$P/.gitignore" "$TMP/ignore.once"
head -c "$(wc -c < "$TMP/ignore.original")" "$P/.gitignore" > "$TMP/ignore.prefix"
ignored_all=0
for path in "${runtime_paths[@]}"; do git -C "$P" check-ignore -q "$path" || ignored_all=1; done
post_status="$(git -C "$P" status --short --untracked-files=all -- "${runtime_paths[@]}")"
bash "$INIT" "$P" > "$TMP/init2.log" 2>&1; i2=$?
check '旧忽略段逐项补齐且运行态不污染 Git' '[[ $i1 -eq 0 && $ignored_all -eq 0 && -z "$post_status" ]] && cmp -s "$TMP/ignore.original" "$TMP/ignore.prefix"'
check '重复安装 .gitignore 字节不变' '[[ $i2 -eq 0 ]] && cmp -s "$P/.gitignore" "$TMP/ignore.once"'
check '既有配置未覆盖' '[[ "$(cat "$P/qwbuddy/config.sh")" == CUSTOM_SETTING=kept ]]'
python3 - "$P/.claude/settings.json" "$TMP/settings.before" > "$TMP/hook-check.log" 2>&1 <<'PY'
import json,sys
new=json.load(open(sys.argv[1])); old=json.load(open(sys.argv[2])); stop=new["hooks"]["Stop"]
entry={"type":"command","command":'bash "$CLAUDE_PROJECT_DIR"/qwbuddy/bin/qwb-hook-claude-stop.sh',"asyncRewake":True,"timeout":7200}
assert stop[:2] == old["hooks"]["Stop"] and new["custom"] == old["custom"]
assert sum(h == entry for g in stop for h in g.get("hooks",[])) == 1
PY
hc=$?
check '伪 hook 保留并补规范入口' '[[ $hc -eq 0 ]]'

R="$TMP/route"; mkdir -p "$R/qwbuddy" "$TMP/fakebin"
printf '{"rules":[],"default":{"worker":"pi"}}\n' > "$R/qwbuddy/dispatch-rules.json"
printf 'brief\n' > "$R/brief.md"
cat > "$TMP/fakebin/curl" <<'SH'
#!/usr/bin/env bash
while [[ $# -gt 0 ]]; do case "$1" in -o) out="$2"; shift 2;; *) shift;; esac; done
cat >/dev/null
cat /dev/fd/3 > "$out"
printf 500
SH
chmod +x "$TMP/fakebin/curl"
key='boundary-secret-canary'
(cd "$R" && TYPESAFE_API_KEY="$key" PATH="$TMP/fakebin:$PATH" bash "$DISPATCH" brief.md) > "$TMP/route.out" 2> "$TMP/route.err"; rr=$?
check 'HTTP 错误不反射凭据且维持 error' '[[ $rr -eq 0 ]] && grep -q "status: error" "$TMP/route.out" && grep -q "http 500" "$TMP/route.out" && ! grep -q "$key" "$TMP/route.out" "$TMP/route.err"'

W="$TMP/work"; mkdir -p "$W/tasks/foo" "$W/.worktrees/foo"; git -C "$W" init -q
git -C "$W" config user.email test@example.invalid; git -C "$W" config user.name Test
printf 'base\n' > "$W/base"; git -C "$W" add base; git -C "$W" commit -qm base
printf 'state: done\n' > "$W/tasks/2099-01-01-foo.md"
printf 'state: done\n' > "$W/other.md"
git -C "$W" worktree add -q -b other "$W/other" HEAD
git -C "$W" worktree add -q -b good "$W/.worktrees/good" HEAD
printf 'state: done\n' > "$W/tasks/2099-01-03-good.md"
cp "$W/other.md" "$TMP/other.before"
bash "$WORKTREE" finish 'foo/../../other' --merged --project "$W" > "$TMP/path.log" 2>&1; pr=$?
check '路径型 ID 前置拒绝且其他 worktree 完好' '[[ $pr -ne 0 ]] && [[ -d "$W/other" ]] && git -C "$W" show-ref --verify -q refs/heads/other && cmp -s "$W/other.md" "$TMP/other.before"'
ln -s "$W/other" "$W/.worktrees/link"; printf 'state: done\n' > "$W/tasks/2099-01-04-link.md"
bash "$WORKTREE" finish link --merged --project "$W" > "$TMP/link.log" 2>&1; lr=$?
check '目标符号链接拒绝' '[[ $lr -ne 0 ]] && [[ -d "$W/other" ]] && git -C "$W" show-ref --verify -q refs/heads/other'
ln -s "$W/other.md" "$W/tasks/2099-01-05-borrow.md"
git -C "$W" worktree add -q -b borrow "$W/.worktrees/borrow" HEAD
bash "$WORKTREE" finish borrow --keep --project "$W" > "$TMP/borrow.log" 2>&1; br=$?
check '账本符号链接拒绝' '[[ $br -ne 0 ]] && cmp -s "$W/other.md" "$TMP/other.before"'
git -C "$W" worktree add -q -b name "$W/.worktrees/name" HEAD
printf 'state: done\n' > "$W/tasks/2099-01-08-name-suffix.md"
bash "$WORKTREE" finish name --keep --project "$W" > "$TMP/name.log" 2>&1; nr=$?
check '相似任务名不可借账本' '[[ $nr -ne 0 ]] && ! grep -q "^worktree:" "$W/tasks/2099-01-08-name-suffix.md"'
X="$TMP/foreign"; mkdir -p "$X"; git -C "$X" init -q
git -C "$X" config user.email test@example.invalid; git -C "$X" config user.name Test
git -C "$X" commit -qm base --allow-empty
git -C "$X" worktree add -q -b foreign "$W/.worktrees/foreign" HEAD
printf 'state: done\n' > "$W/tasks/2099-01-07-foreign.md"
bash "$WORKTREE" finish foreign --keep --project "$W" > "$TMP/foreign.log" 2>&1; fr=$?
check '其他仓登记的 worktree 拒绝' '[[ $fr -ne 0 ]] && [[ -d "$W/.worktrees/foreign" ]] && ! grep -q "^worktree:" "$W/tasks/2099-01-07-foreign.md"'
bash "$WORKTREE" finish good --merged --project "$W" > "$TMP/good.log" 2>&1; gr=$?
check '合法已合入 worktree 收尾' '[[ $gr -eq 0 ]] && [[ ! -e "$W/.worktrees/good" ]] && grep -q "^worktree: merged" "$W/tasks/2099-01-03-good.md"'
git -C "$W" worktree add -q -b unmerged "$W/.worktrees/unmerged" HEAD
printf 'state: done\n' > "$W/tasks/2099-01-09-unmerged.md"
git -C "$W/.worktrees/unmerged" commit -qm new --allow-empty
bash "$WORKTREE" finish unmerged --merged --project "$W" > "$TMP/unmerged.log" 2>&1; ur=$?
check '未合入提交拒绝收尾' '[[ $ur -ne 0 ]] && [[ -d "$W/.worktrees/unmerged" ]] && git -C "$W" show-ref --verify -q refs/heads/unmerged && ! grep -q "^worktree:" "$W/tasks/2099-01-09-unmerged.md"'
bash "$WORKTREE" finish unmerged --archive --project "$W" > "$TMP/archive.log" 2>&1; ar=$?
check '明确归档保留提交引用' '[[ $ar -eq 0 ]] && [[ ! -e "$W/.worktrees/unmerged" ]] && git -C "$W" show-ref --verify -q refs/tags/archive/unmerged && grep -q "^worktree: archive" "$W/tasks/2099-01-09-unmerged.md"'
git -C "$W" worktree add -q -b '中文-任务' "$W/.worktrees/中文-任务" HEAD
printf 'state: done\n' > "$W/tasks/2099-01-06-中文-任务.md"
bash "$WORKTREE" finish '中文-任务' --keep=保留 --project "$W" > "$TMP/chinese.log" 2>&1; cr=$?
check '中文任务 ID 合法保留' '[[ $cr -eq 0 ]] && [[ -d "$W/.worktrees/中文-任务" ]] && grep -q "^worktree: keep" "$W/tasks/2099-01-06-中文-任务.md"'

if [[ $FAILS -eq 0 ]]; then echo 'BOUNDARY PASS'; exit 0; else echo "BOUNDARY FAIL ($FAILS)"; exit 1; fi
