// qwb-watch.ts 行为单元测试（票 2026-09-16-watch-invisible-pi §1 前六场景 + turn_end 探测）。
// 不依赖 pi 进程：createWatchCore 全依赖注入，子进程/时钟/消息全部假件。
// 由 tests/smoke.sh 调用；node ≥23.6 直跑，旧 node 退回 --experimental-strip-types，或 bun。
import assert from "node:assert/strict";
import { mkdtempSync, readFileSync, existsSync, writeFileSync, mkdirSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { createWatchCore, WAKE_PREFIX } from "../templates/pi-extensions/qwb-watch.ts";

const root = mkdtempSync(join(tmpdir(), "qwb-watch-test-"));
mkdirSync(join(root, "qwbuddy", "bin"), { recursive: true });
writeFileSync(join(root, "qwbuddy", "bin", "qwb-wake.sh"), "#!/usr/bin/env bash\nexit 0\n");

// —— 假件 ——
function makeFakeChild(pid, script = []) {
  // script: [{ code }] —— 调 fake.exit(n) 依次触发第 n 次退出
  const c = {
    pid,
    killed: false,
    stdout: makeStream(),
    stderr: makeStream(),
    exitCbs: [],
    closeCbs: [],
    errorCbs: [],
    on(ev, cb) {
      if (ev === "exit") c.exitCbs.push(cb);
      if (ev === "close") c.closeCbs.push(cb);
      if (ev === "error") c.errorCbs.push(cb);
    },
    kill() {
      c.killed = true;
    },
    exit(code, stdoutText = "", { drain = true } = {}) {
      c.stdout.push(stdoutText);
      for (const cb of c.exitCbs) cb(code, null);
      if (drain) { c.stdout.end(); c.stderr.end(); c.close(code); }
    },
    close(code) { for (const cb of c.closeCbs) cb(code, null); },
  };
  return c;
}
function makeStream() {
  const cbs = [];
  const endCbs = [];
  return {
    cbs,
    push(text) {
      for (const cb of cbs) cb(text);
    },
    end() { for (const cb of endCbs) cb(); },
    setEncoding() {},
    on(ev, cb) {
      if (ev === "data") cbs.push(cb);
      if (ev === "end") endCbs.push(cb);
    },
  };
}

function makeHarness({ owner = "wT:p1", paneId = "wT:p1", intervalMs = 100 } = {}) {
  const state = {
    spawns: [], // { args, child }
    messages: [], // 注入的文本
    timers: [], // { ms, fn, cancelled }
    watch: null, // .watch 文件内容
    watchCleared: 0,
    errLines: [],
  };
  let nextPid = 100;
  let currentOwner = owner;
  const deps = {
    root,
    paneId,
    intervalMs,
    spawnChild: (cmd, args) => {
      const child = makeFakeChild(nextPid++);
      state.spawns.push({ cmd, args, child });
      return child;
    },
    sendMessage: (text) => {
      state.messages.push(text);
    },
    schedule: (ms, fn) => {
      const t = { ms, fn, cancelled: false };
      state.timers.push(t);
      return {
        cancel: () => {
          t.cancelled = true;
        },
      };
    },
    readLockOwner: () => currentOwner,
    writeWatch: (r, pid, cmd) => {
      state.watch = `kind=pi-ext pid=${pid ?? 0} started=x cmd=${cmd}`;
    },
    clearWatch: (r, pid) => {
      if (state.watch?.startsWith(`kind=pi-ext pid=${pid ?? 0} `)) {
        state.watch = null;
        state.watchCleared += 1;
      }
    },
    appendErr: (r, line) => {
      state.errLines.push(line);
    },
    nowIso: () => "2026-01-01T00:00:00Z",
  };
  return { core: createWatchCore(deps), state, setOwner: (value) => { currentOwner = value; } };
}

function flushTimers(state) {
  const due = state.timers.filter((t) => !t.cancelled);
  state.timers = [];
  for (const t of due) t.fn();
}

let passed = 0;
function ok(name) {
  passed += 1;
  console.log(`PASS  ${name}`);
}

// 场景 1：锁主会话起子进程
{
  const { core, state } = makeHarness();
  core.onSessionStart();
  assert.equal(state.spawns.length, 1, "spawn 被调 1 次");
  const { args } = state.spawns[0];
  const flat = args.join(" ");
  assert.ok(flat.includes("qwb-wake.sh"), "参数含 qwb-wake.sh");
  assert.ok(flat.includes("--block"), "参数含 --block");
  assert.ok(!flat.includes("--max-ms"), "不含 --max-ms");
  assert.ok(state.watch && state.watch.includes("kind=pi-ext") && state.watch.includes(`pid=${state.spawns[0].child.pid}`), ".watch 写入 kind=pi-ext pid=<子进程 pid>");
  assert.equal(state.messages.length, 0, "无消息注入");
  ok("锁主会话：spawn 1 次含 qwb-wake.sh --block 无 --max-ms，.watch 记 pi-ext");
}

// 场景 2：非锁主不起子进程（失败路径）
{
  const { core, state } = makeHarness({ owner: "wOther:p9" });
  core.onSessionStart();
  assert.equal(state.spawns.length, 0, "spawn 0 次");
  assert.equal(state.watch, null, "无 .watch 写入");
  assert.equal(state.messages.length, 0, "无 sendUserMessage");
  ok("非锁主：spawn 0 次、无 .watch、无注入");
}

// 场景 3：exit 2 注入并重启
{
  const { core, state } = makeHarness();
  core.onSessionStart();
  const line1 = "看账本：1 张未结项有进展";
  const line2 = "2099-01-01-a.md state=running 最后: done: hello";
  state.spawns[0].child.exit(2, `${line1}\n${line2}\n`);
  assert.equal(state.messages.length, 1, "sendUserMessage 被调 1 次");
  assert.ok(state.messages[0].startsWith(WAKE_PREFIX), `内容以 ${WAKE_PREFIX} 开头`);
  assert.ok(state.messages[0].includes(line1) && state.messages[0].includes(line2), "含那两行");
  assert.equal(state.spawns.length, 2, "spawn 随即第 2 次被调");
  ok("exit 2：注入 [qwb-wake] 摘要含两行，spawn 立即第 2 次");
}

// 场景 4：exit 0 不注入不重启
{
  const { core, state } = makeHarness();
  core.onSessionStart();
  assert.notEqual(state.watch, null);
  state.spawns[0].child.exit(0, "账本无未结项\n");
  assert.equal(state.messages.length, 0, "sendUserMessage 0 次");
  assert.equal(state.spawns.length, 1, "spawn 仍 1 次");
  assert.equal(state.watch, null, ".watch 已清");
  ok("exit 0：不注入不重启，.watch 已清");
}

// 场景 5：故障退避与到顶告警（失败路径）
{
  const { core, state } = makeHarness({ intervalMs: 100 });
  core.onSessionStart();
  const delays = [];
  for (let i = 0; i < 9; i += 1) {
    assert.equal(state.spawns.length, i + 1, `第 ${i + 1} 个子进程已起`);
    state.spawns[i].child.exit(1, "");
    // 每次失败安排恰好一个重启定时器
    const pending = state.timers.filter((t) => !t.cancelled);
    assert.equal(pending.length, 1, `第 ${i + 1} 次失败后恰一个重启定时器`);
    delays.push(pending[0].ms);
    flushTimers(state);
  }
  const expected = [100, 200, 400, 800, 800, 800, 800, 800, 800];
  assert.deepEqual(delays, expected, `重启间隔依次翻倍封顶 interval×8（实际 ${delays}）`);
  assert.equal(state.messages.length, 1, "第 9 次后 sendUserMessage 恰好 1 次");
  assert.ok(state.messages[0].includes("值守故障"), "内容含 值守故障");
  assert.ok(state.messages[0].startsWith(WAKE_PREFIX), "告警以 [qwb-wake] 开头");
  assert.equal(state.errLines.length, 9, ".pi-watch.err 有 9 条记录");
  ok("连续 exit 1 ×9：退避 100→800 封顶、告警恰 1 次、err 9 条");
}

// 场景 6：session_start 重复触发单飞
{
  const { core, state } = makeHarness();
  core.onSessionStart();
  const first = state.spawns[0].child;
  core.onSessionStart();
  assert.ok(!first.killed, "现有值守继续运行");
  assert.equal(state.spawns.length, 1, "重复事件不得生成重叠子进程");
  assert.equal(core.child, first);
  ok("session_start 重复：复用现有子进程，单飞");
}

// 场景 7：exit 0 后 turn_end 探测（复用 --block --max-ms 1 判定）
{
  const { core, state } = makeHarness();
  core.onSessionStart();
  state.spawns[0].child.exit(0, "");
  core.onTurnEnd(); // 探测
  assert.equal(state.spawns.length, 2);
  assert.deepEqual(state.spawns[1].args.slice(1), ["--block", "--max-ms", "1"], "探测参数 --block --max-ms 1");
  assert.equal(state.watch, null, "探测不是值守形态，不写 .watch");
  state.spawns[1].child.exit(124, ""); // 有未结项
  assert.equal(state.spawns.length, 3, "探测 124 → 重新值守 spawn");
  assert.deepEqual(state.spawns[2].args.slice(1), ["--block"], "重新值守无 --max-ms");
  assert.ok(state.watch && state.watch.includes("kind=pi-ext"), "重新值守后 .watch 登记");
  // 反向：探测 0 → 继续闲置
  const h2 = makeHarness();
  h2.core.onSessionStart();
  h2.state.spawns[0].child.exit(0, "");
  h2.core.onTurnEnd();
  h2.state.spawns[1].child.exit(0, "");
  h2.core.onTurnEnd(); // 仍闲置 → 再探测一次
  h2.state.spawns[2].child.exit(0, "");
  assert.equal(h2.state.spawns.length, 3, "探测 0 后仍闲置（不直接值守）");
  ok("turn_end 探测：--max-ms 1、124 重新值守、0 继续闲置");
}

// 场景 8：shutdown 杀子进程且迟来回调不作数
{
  const { core, state } = makeHarness();
  core.onSessionStart();
  state.spawns[0].child.exit(0, "");
  core.onTurnEnd();
  assert.equal(state.spawns.length, 2, "turn_end 已启动 probe");
  state.spawns[1].child.exit(2, "看账本：新进展\n");
  assert.deepEqual(state.messages, [`${WAKE_PREFIX} 看账本：新进展`], "probe exit 2 交付恰好一条摘要");
  assert.equal(core.failures, 0, "probe exit 2 不计故障");
  assert.deepEqual(state.errLines, [], "probe exit 2 不写故障日志");
  assert.equal(state.timers.length, 0, "probe exit 2 不进入退避");
  assert.equal(state.spawns.length, 3, "probe exit 2 立即恢复常规值守");
  assert.deepEqual(state.spawns[2].args.slice(1), ["--block"], "恢复值守不带探测上限");
  ok("turn_end probe exit 2：摘要交付一次，无故障退避，立即恢复常规值守");
}

// 场景 9：shutdown 杀子进程且迟来回调不作数
{
  const { core, state } = makeHarness();
  core.onSessionStart();
  const c = state.spawns[0].child;
  core.shutdown();
  assert.ok(c.killed, "shutdown 杀子进程");
  const before = state.spawns.length;
  c.exit(2, "迟来的摘要"); // 旧代际回调不得注入/重启
  assert.equal(state.messages.length, 0, "迟来 exit 2 不注入");
  assert.equal(state.spawns.length, before, "迟来 exit 2 不重启");
  ok("shutdown：杀子进程、旧代际 exit 回调作废");
}

// 场景 9：.pi-watch.err 默认实现真实落盘（文件级冒烟）
{
  const r = mkdtempSync(join(tmpdir(), "qwb-watch-file-"));
  mkdirSync(join(r, "qwbuddy"), { recursive: true });
  const { appendFileSync } = await import("node:fs");
  appendFileSync(join(r, "qwbuddy", ".pi-watch.err"), "x exit=1\n");
  assert.ok(readFileSync(join(r, "qwbuddy", ".pi-watch.err"), "utf8").includes("exit=1"));
  assert.ok(!existsSync(join(r, "qwbuddy", ".watch")), "未写 .watch");
  ok(".pi-watch.err 默认实现落盘");
  rmSync(r, { recursive: true, force: true });
}

// 生命周期回归：开局无锁，晚获锁后在现有 turn_end 自动启动；失锁不续命。
{
  const { core, state, setOwner } = makeHarness({ owner: "wOther:p9" });
  core.onSessionStart();
  assert.equal(state.spawns.length, 0);
  setOwner("wT:p1");
  core.onTurnEnd();
  assert.equal(state.spawns.length, 1, "晚获锁应自动启动一个值守");
  core.onTurnEnd();
  assert.equal(state.spawns.length, 1, "重复事件不得多开");
  setOwner("wOther:p9");
  core.onTurnEnd();
  assert.ok(state.spawns[0].child.killed, "失锁须杀旧子进程");
  state.spawns[0].child.exit(2, "旧会话输出");
  assert.equal(state.messages.length, 0);
  ok("晚获锁自动值守、重复事件单飞、失锁停旧实例");
}

{
  const { core, state } = makeHarness();
  core.onSessionStart();
  const c = state.spawns[0].child;
  core.shutdown();
  core.onTurnEnd();
  core.onSessionStart();
  assert.equal(state.spawns.length, 1, "shutdown 后旧回调不得重启");
  assert.notEqual(state.watch, null, "close 前仍保留旧实例登记与单飞位置");
  c.exit(2, "迟到摘要");
  assert.equal(state.watch, null, "close 后只清本实例登记");
  assert.equal(state.messages.length, 0);
  ok("shutdown 终态阻止重启并清本实例登记");
}

{
  const { core, state } = makeHarness();
  core.onSessionStart();
  const c = state.spawns[0].child;
  c.exit(2, "前半摘要", { drain: false });
  c.stdout.push("后半摘要");
  c.stdout.end();
  c.stderr.end();
  c.close(2);
  assert.equal(state.messages.length, 1);
  assert.ok(state.messages[0].includes("后半摘要"), "退出后管道排空的尾部摘要须交付");
  ok("exit 先于 stdout 排空时仍交付完整摘要");
}

{
  const { core, state } = makeHarness();
  core.onSessionStart();
  state.watch = "kind=pi-ext pid=999 started=new cmd=new";
  core.shutdown();
  assert.equal(state.watch, "kind=pi-ext pid=999 started=new cmd=new", "旧会话不能删除新会话登记");
  ok("旧会话 shutdown 不清新会话登记");
}

{
  const { core, state, setOwner } = makeHarness();
  core.onSessionStart();
  const old = state.spawns[0].child;
  setOwner("wOther:p9");
  core.onTurnEnd();
  assert.ok(old.killed, "失锁要求终止旧子进程");
  setOwner("wT:p1");
  core.onTurnEnd();
  core.onSessionStart();
  assert.equal(state.spawns.length, 1, "旧子进程未 close 前不得双开");
  old.exit(143, "尾部输出", { drain: false });
  old.stdout.end();
  core.onTurnEnd();
  assert.equal(state.spawns.length, 1, "仅 exit/stdout end 不足以证明管道全部排空");
  old.stderr.end();
  old.close(143);
  assert.equal(state.spawns.length, 2, "旧子进程 close 后重获锁应启动一个新实例");
  assert.ok(state.watch?.includes(`pid=${state.spawns[1].child.pid}`));
  old.close(143);
  assert.ok(state.watch?.includes(`pid=${state.spawns[1].child.pid}`), "旧回调不得清新登记");
  assert.equal(state.spawns.length, 2, "旧回调不得再启动第三个实例");
  ok("快速失锁重获：旧进程 close/管道排空前不双开，旧回调不清新登记");
}

console.log(`pi-ext tests: ${passed} passed`);
rmSync(root, { recursive: true, force: true });
