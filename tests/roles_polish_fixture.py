"""Only undo roles-polish changes in today's scripts; never pin a historic Git object."""
import re


def baseline(name, text):
    if name == 'qwb-ledger.sh':
        prefixes = ['工作包id/任务路径歧义', '启动授权/预算未明确',
                    '工人授权须显式配置名，不用auto', '候选/attempt/policy/环境非法',
                    '门/场景映射非法', '范围外场景', '关键场景缺失或降低full策略',
                    '候选不存在', '环境证据不存在']
        for prefix in prefixes:
            text, count = re.subn(r"fail\('" + re.escape(prefix) + r"；[^']*'\)",
                                 "fail('" + prefix + "')", text)
            assert count == 1, prefix
        start = '  my $b=strict_json($s);\n'
        end = "  fail('工人授权须显式配置名，不用auto')"
        block = text.split(start, 1)[1].split(end, 1)[0]
        assert 'eval { keys_only' in block
        text = text.replace(start + block, '  my $b=strict_json($s); keys_only($b,qw(candidate base attempt policy environment required workers));\n  keys_only($b->{workers},qw(review rework));\n', 1)
    elif name == 'qwb-worktree.sh':
        guard = '  land_writers_stopped || exit 1\n  qwb_ledger "$PROJECT_ROOT" "$TASK_FILE" land-prepare'
        assert text.count(guard) == 1
        text = text.replace(guard, '  qwb_ledger "$PROJECT_ROOT" "$TASK_FILE" land-prepare', 1)
        for label, variable in [('本票', 'pane'), ('land', 'pane_id')]:
            new = f'"拒绝：{label}写入者尚未退出（idle/done不等于已停）；窗口=${{{variable}}}；确认工人已停后 herdr pane close ${{{variable}}}，再用同一操作号重跑"'
            assert text.count(new) == 1
            text = text.replace(new, f"'拒绝：{label}写入者尚未退出（idle/done不等于已停）'")
        # Definitions can stay before land: only the new invocation changes behavior.
    elif name == 'qwb-status.sh':
        text = text.replace('        obligations="$(printf \'%s\' "$collab" | qwb_task_obligations_json)"\n        [[ -z "$obligations" ]] || mark="未结"',
                            '        [[ -z "$(printf \'%s\' "$collab" | qwb_task_obligations_json)" ]] || mark="未结"')
        text = text.replace('          my %pending=map { substr($_,8)=>1 } grep { /^handoff=/ } split / /,$ARGV[0];\n          my $history=0;\n', '')
        text = text.replace('            unless ($pending{$id}) { $history++; next }\n', '')
        text = text.replace('          print "       另有 $history 条已满足或纯进度的历史交接\\n" if $history;\n        \' "$obligations"', "        '")
    else:
        raise AssertionError(name)
    return text


def freeze_writer(text):
    return (text.replace("$event=unpack('H*',$bytes);", '$event=sprintf("%032x",$data->{seq});')
            .replace('int(time()*1000)', '1791158400000')
            .replace("at=>strftime('%Y-%m-%dT%H:%M:%SZ',gmtime)", "at=>'2026-10-05T00:00:00Z'"))


if __name__ == '__main__':
    from pathlib import Path
    import subprocess
    root = Path(__file__).resolve().parents[1]
    for name in ['qwb-ledger.sh', 'qwb-worktree.sh', 'qwb-status.sh']:
        text = (root / 'bin' / name).read_text()
        old = baseline(name, text)
        assert old != text, name
        subprocess.run(['/bin/bash', '-n'], input=old, text=True, check=True)
    print('PASS roles-polish 当前脚本只撤本票改动的三份基线兼容Bash 3.2语法')
