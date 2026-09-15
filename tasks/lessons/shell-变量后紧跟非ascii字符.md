# shell 变量后紧跟非 ASCII 字符导致 unbound variable

**日期**：2026-09-15
**发现者**：主控独立验收（工人首轮自检未发现，`tests/smoke.sh` 当时未覆盖 `qwb-run.sh`）

## 现象

`qwb-run.sh` 派发任务时 100% 崩溃，崩在**发提示词**那一步：

```
qwb-run.sh: line 92: TASK_FILE?: unbound variable
```

后果：`herdr agent prompt` 没执行、`dispatch:` 行没写、`state: running` 没落 —— 派发看上去"跑了一半"，账本却是空的。

## 根因

脚本里中英混排，变量后紧跟全角字符：

```bash
herdr agent prompt "$NAME" "... 唯一规格来源：$TASK_FILE（先完整读它 ...）"
echo "错误：找不到 $CONF（先跑 qwb-init.sh）" >&2
```

bash 在 UTF-8 locale 下把非 ASCII 字节当作**变量名的合法字符**，于是 `$TASK_FILE（` 被解析成变量 `TASK_FILE<0xEF...>`（名字里带上了全角括号的首字节）。该变量不存在，`set -u` 直接终止脚本。

同类 4 处：`$TASK_FILE（`、`$DIR，`、`$TASK_FILE——`、`$CONF（`。

## 对策

1. **变量后紧跟非 ASCII 字符时一律用花括号**：`${TASK_FILE}（`、`${DIR}，`。
2. 门里加一条静态扫描（`tests/smoke.sh` 已加）：

```bash
python3 - <<'PY'
import re,glob,sys
pat=re.compile(r'\$[A-Za-z_][A-Za-z0-9_]*[^\x00-\x7F]')
bad=[f"{f}:{i}: {m.group()}" for f in glob.glob('bin/*.sh')
     for i,l in enumerate(open(f,encoding='utf-8'),1) for m in pat.finditer(l)]
print("\n".join(bad)); sys.exit(1 if bad else 0)
PY
```

注意 `grep -P` 在 macOS BSD grep 上不可用，别用。

## 教训

中英混排的 shell 脚本必须**跑真实执行路径**才验得出来——语法检查（`bash -n`）和 `shellcheck` 都发现不了它。这也是"门必须覆盖每个脚本"的直接理由：`qwb-run.sh` 当时完全没被冒烟测试碰过，所以两个致命 bug 一起漏网。

## 补充（2026-09-15，同一坑第二次）

**主控本人在一次性验收脚本里又踩了一次**：`echo "  finish --archive rc=$rc；archive/T → ..."` —— `$rc；` 中的变量名被吃成 `rc<全角分号首字节>`，报 `rc?: unbound variable`。

结论：这不是「执行者才会犯的错」，而是**中英混排 shell 的通用陷阱**。凡是 `$VAR` 后紧跟非 ASCII 字符（中文标点、全角括号、破折号），**一律写成 `${VAR}`**。写测试脚本、一次性脚本同样适用——不存在「反正只是临时脚本」的豁免。
