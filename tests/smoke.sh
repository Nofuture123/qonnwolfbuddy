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
bash "$ROOT/bin/qwb-init.sh" "$TMP" >/dev/null || bad "qwb-init.sh 运行失败"

assert_file "$TMP/qwbuddy/QWBUDDY.md"
for r in 主控 审核者 执行者 咨询师; do assert_file "$TMP/qwbuddy/roles/$r.md"; done
assert_file "$TMP/qwbuddy/config.sh"
for s in init run wake status lock worktree; do assert_file "$TMP/qwbuddy/bin/qwb-$s.sh"; done
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
if ( . "$TMP/qwbuddy/config.sh"; [[ "$QWB_WORKERS" == "codex pi claude" && "$QWB_AGENT_START_MS" == "30000" && "$QWB_WAKE_INTERVAL_MS" == "120000" ]] ); then
  ok "config.sh source 后三个配置值正确"
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
mkdir -p "$STUB"
cat > "$STUB/herdr" <<EOF
#!/usr/bin/env bash
echo "herdr \$*" >> "$STUBLOG"
case "\${1:-} \${2:-}" in
  "pane run")   [[ "\${HERDR_FAIL:-}" == *run*  ]] && exit 1; printf '%s\n' '{"result":{"ok":true}}' ;;
  "agent wait") if [[ "\${HERDR_WAIT_SLEEP:-0}" -gt 0 ]]; then sleep "\$HERDR_WAIT_SLEEP"; exit 1; fi
                [[ "\${HERDR_FAIL:-}" == *wait* ]] && exit 1; printf '%s\n' '{"result":{"ok":true}}' ;;
  "tab create") printf '%s\n' '{"result":{"root_pane":{"pane_id":"wtest:p9"}}}' ;;
  *) printf '%s\n' '{"result":{"ok":true}}' ;;
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
printf '# 派发测试\nstate: blocked\n' > "$DISP"
( cd "$TMP" && PATH="$STUB:$PATH" bash qwbuddy/bin/qwb-run.sh --task disp --worker codex --worktree "$TMP" ) >/dev/null \
  && ok "qwb-run.sh 派发退出 0" || bad "qwb-run.sh 派发非 0"
grep -q '^state: running' "$DISP" && ok "任务书 state 变为 running" || bad "任务书 state 未变 running"
grep -q '^dispatch:' "$DISP" && ok "任务书末尾有 dispatch: 行" || bad "任务书无 dispatch: 行"
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

echo "== 12. F2 回归：dispatch pane 失效 → 按 interval 退化等待，无忙循环 =="
: > "$STUBLOG"
( cd "$TMP" && PATH="$STUB:$PATH" HERDR_FAIL=wait exec bash qwbuddy/bin/qwb-wake.sh --pane wtest:p9 --interval 1000 ) >/dev/null 2>&1 &
WPID=$!
sleep 4
kill "$WPID" 2>/dev/null; wait "$WPID" 2>/dev/null || true
n="$(grep -c 'agent wait' "$STUBLOG" || true)"
[[ "$n" -ge 2 && "$n" -le 8 ]] \
  && ok "4 秒内 ${n} 次 agent wait（≈1 秒/轮，无忙循环）" || bad "4 秒内 ${n} 次 agent wait（忙循环或未等待）"

echo "== 12b. G2：agent wait 超时路径不再重复 sleep（一轮 ≈1×interval）=="
: > "$STUBLOG"
( cd "$TMP" && PATH="$STUB:$PATH" HERDR_WAIT_SLEEP=1 exec bash qwbuddy/bin/qwb-wake.sh --pane wtest:p9 --interval 1000 ) >/dev/null 2>&1 &
WPID=$!
sleep 4
kill "$WPID" 2>/dev/null; wait "$WPID" 2>/dev/null || true
n="$(grep -c 'agent wait' "$STUBLOG" || true)"
[[ "$n" -ge 3 && "$n" -le 6 ]] \
  && ok "4 秒内 ${n} 次 agent wait（超时路径 ≈1 秒/轮 = 1×interval；旧实现会 sleep 两轮仅 ~2 次）" \
  || bad "4 秒内 ${n} 次 agent wait（超时路径仍重复 sleep 或退化成忙循环）"

echo "== 13. F1 回归：主控锁 =="
LOCKD="$TMP/qwbuddy/.controller.lock"
rm -rf "$LOCKD"
( cd "$TMP" && bash qwbuddy/bin/qwb-lock.sh acquire --owner wtest:p9 ) >/dev/null \
  && ok "acquire 成功" || bad "acquire 失败"
( cd "$TMP" && bash qwbuddy/bin/qwb-lock.sh acquire --owner wtest:p8 ) >/dev/null 2>&1 \
  && bad "第二次 acquire 竟成功" || ok "持锁时第二次 acquire 被拒"
( cd "$TMP" && bash qwbuddy/bin/qwb-lock.sh status ) | grep -q 'wtest:p9' \
  && ok "status 显示锁主" || bad "status 未显示锁主"
( cd "$TMP" && bash qwbuddy/bin/qwb-lock.sh release ) >/dev/null \
  && ok "release 成功" || bad "release 失败"
( cd "$TMP" && bash qwbuddy/bin/qwb-lock.sh acquire --owner wtest:p9 ) >/dev/null \
  && ok "release 后可再 acquire" || bad "release 后 acquire 失败"
( cd "$TMP" && PATH="$STUB:$PATH" HERDR_PANE_ID=wtest:p7 bash qwbuddy/bin/qwb-run.sh --task disp --worker codex --worktree "$TMP" ) >/dev/null 2>&1 \
  && bad "他人持锁时 qwb-run.sh 仍派发" || ok "他人持锁时 qwb-run.sh 拒绝派发"
( cd "$TMP" && PATH="$STUB:$PATH" HERDR_PANE_ID=wtest:p9 bash qwbuddy/bin/qwb-run.sh --task disp --worker codex --worktree "$TMP" ) >/dev/null \
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
printf '%s' "$r3out" | grep -q 'codex pi claude' && ok "报错列出全部合法工人名" || bad "报错未列出合法工人名"

echo "== 16. R4：非法 state 变可见 =="
ILF="$TMP/tasks/2099-01-06-illegal.md"
printf '# 非法状态\nstate: pending\n' > "$ILF"
out="$( cd "$TMP" && bash qwbuddy/bin/qwb-status.sh 2>&1 )"
printf '%s' "$out" | grep -q '非法' && ok "status 对 state=pending 显示非法标记" || bad "status 未标非法 state"
out="$( cd "$TMP" && bash qwbuddy/bin/qwb-wake.sh --dry-run --once 2>&1 )"
printf '%s' "$out" | grep -q 'state=pending 非法' && ok "wake 对 state=pending 发 stderr 警告" || bad "wake 未警告非法 state"
printf '%s' "$out" | grep -q '未结项（将叫醒）: 2099-01-06-illegal' \
  && bad "非法 state 被列为未结项" || ok "非法 state 不算未结项"

echo "== 17. R1：qwb-worktree.sh 端到端（临时 git 项目）=="
GP="$TMP/gitp"
mkdir -p "$GP/tasks" "$GP/.worktrees" "$GP/qwbuddy"
cp "$TMP/qwbuddy/config.sh" "$GP/qwbuddy/config.sh"
git -C "$GP" init -q
git -C "$GP" -c user.email=t@t.t -c user.name=t commit -qm init --allow-empty
WTB="$TMP/qwbuddy/bin/qwb-worktree.sh"

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
if bash "$WTB" finish "$WTID" --merged --project "$GP" >/dev/null 2>&1; then
  bad "--merged 对未合并分支竟放行"
else
  ok "--merged 对未合并分支拒绝"
fi
[[ -d "$GP/.worktrees/$WTID" ]] && ok "拒绝后 worktree 未动" || bad "拒绝后 worktree 被删"

# --keep：不动 git，只记账
bash "$WTB" finish "$WTID" --keep=等使用者裁决 --project "$GP" >/dev/null \
  && ok "finish --keep 退出 0" || bad "finish --keep 失败"
grep -q '^worktree: keep' "$WTF" && ok "任务书追加了 worktree: keep 行" || bad "任务书无 worktree: 行"
[[ -d "$GP/.worktrees/$WTID" ]] && ok "--keep 未删 worktree" || bad "--keep 删了 worktree"

# --archive：打 tag → 删 worktree → branch -D → 记账
bash "$WTB" finish "$WTID" --archive --project "$GP" >/dev/null \
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
if bash "$WTB" finish "$WTD" --archive --project "$GP" >/dev/null 2>&1; then
  bad "脏 worktree --archive 竟放行"
else
  ok "脏 worktree --archive 拒绝"
fi
[[ -d "$GP/.worktrees/$WTD" ]] && ok "拒绝后脏 worktree 未动" || bad "脏 worktree 被删"

# G4：--keep 不做脏检查——同一脏 worktree 上 --keep 退出 0 且记账
bash "$WTB" finish "$WTD" --keep=有冲突待解 --project "$GP" >/dev/null \
  && ok "脏 worktree --keep 退出 0（G4）" || bad "脏 worktree --keep 被拒（G4 未修）"
grep -q '^worktree: keep' "$WTDF" && ok "--keep 记账成功" || bad "--keep 未记账"
[[ -d "$GP/.worktrees/$WTD" ]] && ok "--keep 后脏 worktree 未动" || bad "--keep 动了 worktree"

# --merged 放行路径：分支合并进 HEAD 后正常收尾
WTM="wtmerged"; WTMF="$GP/tasks/2099-01-09-${WTM}.md"
printf '# merged\nstate: running\n' > "$WTMF"
git -C "$GP" worktree add -q -b "$WTM" "$GP/.worktrees/$WTM"
git -C "$GP/.worktrees/$WTM" -c user.email=t@t.t -c user.name=t commit -qm wip --allow-empty
git -C "$GP" -c user.email=t@t.t -c user.name=t merge -qm m "$WTM"
bash "$WTB" finish "$WTM" --merged --project "$GP" >/dev/null \
  && ok "已合并分支 --merged 放行" || bad "已合并分支 --merged 被拒"
[[ -d "$GP/.worktrees/$WTM" ]] && bad "merged 后 worktree 仍在" || ok "merged 后 worktree 已删"
git -C "$GP" show-ref --verify --quiet "refs/heads/$WTM" && bad "merged 后分支仍在" || ok "merged 后分支已删"

# qwb-run.sh --create-worktree：有残留 → 警告但不阻塞
printf '# new\nstate: running\n' > "$GP/tasks/2099-01-10-wtnew.md"
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
if bash "$WTB" finish "$WTG" --merged --project "$GP" >/dev/null 2>&1; then
  bad "detached 未合并 --merged 竟放行（G1 未修）"
else
  ok "detached 未合并 --merged 拒绝"
fi
[[ -d "$GP/.worktrees/$WTG" ]] && ok "拒绝后 detached worktree 未动" || bad "拒绝后 detached worktree 被删"

# --archive：tag 必须指向 B（实际 HEAD OID），且同名分支保留
bash "$WTB" finish "$WTG" --archive --project "$GP" >/dev/null \
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
if PATH="$GSTUB:$PATH" bash "$WTB" finish "$WTS" --archive --project "$GP" >/dev/null 2>&1; then
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
echo '{}' > "$MIG/qwbuddy/config.jso""n"
migout="$(bash "$ROOT/bin/qwb-init.sh" "$MIG" 2>&1)"
printf '%s' "$migout" | grep -q '旧版' && ok "init 对旧版 JSON 配置打迁移提示" || bad "init 未打迁移提示"
assert_file "$MIG/qwbuddy/config.sh"

echo "== 21. G3：bin/ tests/ templates/ 中旧配置文件名字面量零命中 =="
if grep -rn 'config\.json' "$ROOT/bin" "$ROOT/tests" "$ROOT/templates" >/dev/null 2>&1; then
  bad "bin/tests/templates 仍出现旧配置文件名"
  grep -rn 'config\.json' "$ROOT/bin" "$ROOT/tests" "$ROOT/templates" || true
else
  ok "旧配置文件名字面量零命中"
fi

echo
if [[ "$FAILS" -eq 0 ]]; then echo "SMOKE PASS"; exit 0; else echo "SMOKE FAIL（$FAILS 项）"; exit 1; fi
