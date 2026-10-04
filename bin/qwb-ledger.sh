#!/usr/bin/env bash
# 同一票的唯一运行时 writer；Perl 核心模块，无数据库。未迁票不启用 rename 协议。
set -euo pipefail
if [[ "${1:-}" == --help || "${1:-}" == -h ]]; then
  cat <<'EOF'
用法: qwb-ledger.sh <read|metrics|append|prepare|revise|revise-scenarios|state|claim|release|recover-claim|wake-check|wake|dispatch|not-sent|question|answer|resume|migrate> --project <根> --task <路径> [--expect <rev>] [--event-id <id>] [--legacy] -- <参数...>
new: request JSON（request_id/package_id/packages/source_task/source_event/intent/spec/constraints/scenarios/paths/needs）；同request/package幂等，source来自03持久交接。
plan-assign: 主控授权02规划actor + JSON（request_id/source_event/packages/paths/workers/permissions/evidence/budget）；预算为首次dispatch次数，不是猜测费用。
plan-authorize: 主控显式启动授权JSON（workers/permissions/evidence/budget）；plan-needs: CAS依赖JSON；plan-ready/start-check: 就绪事件/首次派工门。
plan-artifact: 主控核可用产物JSON（name/version/ref）；plan-land: 主控登记实际落地证据，不自动合并。
plan-revision: CAS修订JSON（source_task/source_event/spec/scenarios/constraints/needs）；gate持claim时仅登记请求；gate交出revision-handoff op后以revise应用。
revision-handoff: gate本人的claim op + 理由；不删除旧证据；已accepted/verified历史只允许后续票。
gate-assign: 现主控授权已登记门禁actor + JSON（candidate/base/attempt/policy/environment/required/workers），冻结命名场景。
gate-context: 本人claim op；gate-diff: op [精确reviewed head] [直接上下文路径...]，只读差异包。
gate-review: op JSON（context/implementer/reviewer/standards/spec/covered/findings）；保原意见，当前仅Pi原生JSONL身份。
gate-verdict: op accepted，或op rework 根因 新证据；accepted仍待land/cleanup，同根因3轮无新证据转技术重诊。
gate-candidate: op 新attempt 原候选目录 base；gate-receipt: op 候选外JSON，由qwb-test生成，不自动验收。
gate-dispatch: op child review|rework 主控已授权工人；长门在独立命令/op下运行，不持writer锁等待。
land-authorize: 本人claim op auth_ref main 明确授权依据 [精确受控MD路径...]；仅现主控，非自动授予。
已prepared/landed且精确本地C存在时，新auth_ref（不带MD参数）只重新明确授权剩余收尾；先对账claim，不重开merge。
land-prepare/land-apply/land-proof/land-close: op auth_ref；固定候选本地main短锁/现实恢复，不运行测试。
gate-candidate: 原四参后可加integration；仅主控在旧M拒绝后登记已在原隔离副本更新的候选/当前main，须新attempt证据和新land授权。
gate-reuse: op fast|full；只读匹配当前可信成功收据，不自动验收。票test-policy引用qwbuddy/test-policy/<版本>.md。
test-request: op request-id 测试actor new-behavior|policy-gap|complex-failure|rediagnose 场景；同spec只咨询一次。
test-reply: request-id JSON（task/request_id/context/validation/tests）；02本代测试身份、03接手/prepared后受限建议，不能验收。
ci-assign: 现主控授权CI actor + qwb-ci-source-v1 JSON（当前候选/命令/环境/限定本地日志）。
ci-report: 按需CI本人提交qwb-ci-diagnosis-v1 JSON；有限提案回原票03交接，不执行正文或替代04收据。
handoff-* 为03兼容扩展，请用 qwb-send.sh --help 查看投递/received/accept/activity/prepared/handled/reconcile；仅合法主控通道，不迁旧票。
身份取 HERDR_PANE_ID（否则 pid:调用进程），不按正文或自声明角色授权。
append: 一条 working:/done:/blocked:/needs-decision: 行；仅主控可写运行时行或 spec-resolved。
prepare: 场景指纹 [常驻附页正文]；revise: 旧指纹 新指纹 原因；state: 五值之一。
revise-scenarios: 新场景块 原因（主控持版本 --expect，保留场景外原字节）。
claim/release: op_id；dispatch: op_id pane 完整dispatch行；not-sent: op_id blocked失败行。
question/answer/resume: key 内容；普通进展不解除问题。answer 必须是真实答复证据。
recover-claim: op_id 对账JSON文件（task_sha256/op_id/previous_owner/reconciled）；必须--expect、现主控和旧owner真实死亡；移交不清claim。
wake-check/wake: 主控目标 state fp；独立值守须主控ensure登记及原生进程核验，仅能写wake。
migrate: 停写确认JSON文件（task_sha256；confirm对象含run/wake/worktree/worker/controller/old-fds/external-actions的证据字符串）。
仅主控确认、lsof无写FD、全部调用者/模板齐备且原字节未变才切一票；不自动迁历史票。
read 输出版本JSON；metrics 输出真实事件时间，旧缺项 unknown。--legacy 只供已接线运行时兼容未迁票；不提供工人裸追加替代权限。
mode-enter --project <根> -- quiet|away <原auth_ref> <原话> <限制>；仅主控，模式不是新授权。
mode-exit --project <根> -- user|explicit <真实输入>；user仅退出away，quiet须explicit；系统门铃不得调用。
mode-status / mode-summary --project <根>：读回完整模式历史/逐票事实，损坏不删不猜。
EOF
  exit 0
fi
CMD="${1:-}"; shift || true
ROOT=""; TASK=""; EXPECT=""; EVENT=""; LEGACY=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    --project) ROOT="$2"; shift 2 ;;
    --task) TASK="$2"; shift 2 ;;
    --expect) EXPECT="$2"; shift 2 ;;
    --event-id) EVENT="$2"; shift 2 ;;
    --legacy) LEGACY=1; shift ;;
    --) shift; break ;;
    *) echo "错误：未知账本参数 $1" >&2; exit 2 ;;
  esac
done
if [[ "$CMD" == mode-* ]]; then
  [[ -z "$TASK" && "$LEGACY" -eq 0 ]] || { echo '错误：mode为项目记录，不接受task/legacy' >&2; exit 2; }
  TASK='qwbuddy/.posture.md'
fi
[[ -n "$CMD" && -n "$ROOT" && -n "$TASK" ]] || { echo '错误：需要命令/project/task' >&2; exit 2; }
ACTOR="${HERDR_PANE_ID:-pid:$PPID}"
BINDIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
IDENTITY='{}'
if [[ "$CMD" != read && "$CMD" != metrics && "$CMD" != mode-* ]]; then
  # shellcheck source=/dev/null
  . "$BINDIR/qwb-lib.sh"
  if [[ "$CMD" == ci-assign || "$CMD" == ci-report ]]; then
    CI_ACTOR=""; [[ "$CMD" != ci-assign ]] || CI_ACTOR="${1:-}"
    IDENTITY="$(qwb_gate_identity "$ROOT" "$CI_ACTOR" CI)" || exit 1
  elif [[ "$CMD" == gate-assign ]]; then
    IDENTITY="$(qwb_gate_identity "$ROOT" "${1:-}")" || exit 1
  elif [[ "$CMD" == plan-assign ]]; then
    IDENTITY="$(qwb_planner_identity "$ROOT" "${1:-}")" || exit 1
  elif [[ "$CMD" == test-request ]]; then
    IDENTITY="$(qwb_gate_identity "$ROOT")" || exit 1
  elif [[ "$CMD" == test-reply ]]; then
    IDENTITY="$(qwb_gate_identity "$ROOT" '' '测试体系')" || exit 1
  elif [[ "$CMD" == handoff-* ]]; then
    IDENTITY="$(qwb_planner_identity "$ROOT")" || exit 1
    if [[ "$IDENTITY" == '{}' ]]; then IDENTITY="$(qwb_gate_identity "$ROOT" '' '门禁|测试体系')" || exit 1; fi
  elif [[ -d "$ROOT/qwbuddy/.roles" ]]; then
    IDENTITY="$(qwb_planner_identity "$ROOT")" || exit 1
    if [[ "$IDENTITY" == '{}' ]]; then IDENTITY="$(qwb_gate_identity "$ROOT")" || exit 1; fi
  fi
fi
TEST_IDENTITY='{}'
if [[ "$CMD" == test-request ]]; then
  TEST_IDENTITY="$(qwb_gate_identity "$ROOT" "${3:-}" '测试体系')" || exit 1
fi
exec perl - "$CMD" "$ROOT" "$TASK" "$ACTOR" "$EXPECT" "$EVENT" "$LEGACY" "$BINDIR" "$IDENTITY" "$TEST_IDENTITY" "$@" <<'PERL'
use strict;
use warnings;
use utf8;
use Fcntl qw(:DEFAULT :flock :mode O_NOFOLLOW F_GETFD F_SETFD FD_CLOEXEC);
use Cwd qw(realpath);
use File::Basename qw(dirname basename);
use File::Temp qw(tempfile);
use Digest::SHA qw(sha1_hex sha256_hex);
use JSON::PP;
use Encode qw(decode encode FB_CROAK);
use POSIX qw(strftime);
use IO::Handle;
use Time::HiRes qw(time);
use Errno qw(ESRCH);
binmode STDERR, ':encoding(UTF-8)';
my ($cmd,$root,$file,$actor,$expect,$event,$legacy,$bindir,$identity_raw,$test_identity_raw,@args)=@ARGV;
sub fail { die "账本拒绝：$_[0]\n" }
sub text { my $v=shift; return decode('UTF-8',$v,FB_CROAK) }
@args=map { text($_) } @args;
$actor=text($actor);
my $posture=$cmd =~ /\Amode-/;
$root=realpath($root) // fail('项目根不存在');
$file="$root/$file" unless $file =~ m{^/};
my $original_parent=dirname($file);
fail('tasks符号链接非法') if -l $original_parent;
my $parent=realpath($original_parent) // fail('tasks目录不存在');
$file="$parent/".basename($file);
fail('tasks/路径或符号链接非法') unless $parent eq ($posture ? "$root/qwbuddy" : "$root/tasks") && !-l $parent && -d $parent && realpath($parent) eq $parent;
fail('任务路径非法') unless basename($file) =~ /\.md\z/ && basename($file) !~ /[\x00-\x1f]/;
sub safe_open {
  my ($path,$flags)=@_;
  sysopen(my $fh,$path,$flags|O_NOFOLLOW,0600) or fail("打开 $path: $!");
  my @s=stat($fh); my @l=lstat($path);
  fail("路径非本人常规单链接文件 $path") unless @s && @l && S_ISREG($s[2]) && $s[3]==1 && $s[4]==$< && $s[0]==$l[0] && $s[1]==$l[1];
  binmode $fh; return $fh;
}
sub read_file {
  my ($path,$close_error)=@_; my $fh=safe_open($path,O_RDONLY);
  my $s=do { local $/; <$fh> }; my $closed=close $fh;
  fail($close_error) if defined($close_error) && !$closed;
  return $s;
}
# Lock order: controller directory -> posture. Task writers already hold controller
# before their read-only posture probe; never invert that order in mode mutations.
my $posture_controller_guard;
if ($posture && $cmd =~ /\Amode-(enter|exit)\z/) {
  open $posture_controller_guard,'<',$parent or fail('主控目录不可读');
  flock($posture_controller_guard,LOCK_EX) or fail('主控目录flock失败');
  inherit_guard($posture_controller_guard);
}
# 稳定 sidecar 永不 unlink/rename。锁后才打开最新票，长工具/推理不在本进程内。
# ponytail: 每次复制整票O(n)，超大历史由后续存储迁移处理；本切片不截断事件。
my $guard=safe_open("$file.qwb-lock",O_RDWR|O_CREAT);
flock($guard,LOCK_EX) or fail("flock: $!");
my @guard_stat=stat($guard); my @guard_path=lstat("$file.qwb-lock");
fail('稳定guard已被替换，停止写入') unless @guard_path && $guard_stat[0]==$guard_path[0] && $guard_stat[1]==$guard_path[1];
# 发布子程序仍继承同一FD：父进程终止不能让下一writer越过尚未完成的发布。
sub inherit_guard {
  my $fh=shift; my $flags=fcntl($fh,F_GETFD,0);
  defined($flags) && fcntl($fh,F_SETFD,$flags & ~FD_CLOEXEC) or fail('guard FD继承失败');
}
inherit_guard($guard);
my $creating=$cmd eq 'new' && !-e $file;
my $absent=($posture || $creating) && !-e $file && !-l $file;
my $raw='';
unless ($absent) {
  $raw=read_file($file,'读关闭失败');
  fail('票为空') unless defined($raw) && length($raw);
}
my $byte_legacy=0;
my $body=eval { text($raw) };
if ($@) {
  # 旧运行时仍须能叫醒损坏旧票；仅legacy未迁票按字节保留，绝不修复/吞坏字节。
  # 迁移及协作区始终严格UTF-8，新协议不能经legacy开关降级。
  fail('UTF-8非法') unless $legacy && $cmd ne 'migrate' && index($raw,'<!-- qwb-collab-')<0;
  $byte_legacy=1; $body=decode('ISO-8859-1',$raw);
  @args=map { decode('ISO-8859-1',encode('UTF-8',$_)) } @args;
}
my $json=JSON::PP->new->canonical->utf8;
sub strict_json {
  my $s=shift;
  my $obj=eval { $json->decode($s) }; fail("JSON非法 $@") if $@;
  # JSON::PP默认吞重复key；先解码保证语法，再扫描每个对象的真实键（包括转义同名键）。
  my @stack;
  while ($s =~ /("(?:\\.|[^"\\])*"\s*:?)|([{}\[\]])/g) {
    my ($str,$delim)=($1,$2);
    if (defined $str && $str =~ s/\s*:\z//) {
      fail('JSON键不在对象中') unless @stack && ref($stack[-1]) eq 'HASH';
      my $key=$json->decode($str); fail("重复JSON键 $key") if $stack[-1]{$key}++;
    } elsif (defined $delim) {
      if ($delim eq '{') { push @stack,{} }
      elsif ($delim eq '[') { push @stack,[] }
      else { pop @stack }
    }
  }
  return $obj;
}
sub keys_only {
  my ($h,@keys)=@_; fail('schema对象非法') unless ref($h) eq 'HASH';
  my %ok=map { $_=>1 } @keys; my @unknown=grep { !$ok{$_} } keys %$h;
  fail('schema未知键 '.join(',',@unknown)) if @unknown;
  my @missing=grep { !exists $h->{$_} } @keys; fail('schema缺键 '.join(',',@missing)) if @missing;
}
sub id_ok { defined($_[0]) && !ref($_[0]) && $_[0] =~ /\A[A-Za-z0-9_.:-]{1,160}\z/ }
sub string_ok { defined($_[0]) && !ref($_[0]) && $_[0] !~ /[\x00-\x1f]/ }
sub identity_keys { qw(actor pane incarnation owner_fp controller session_id actual_model actual_effort) }
sub ci_source_fields { qw(repo source_run_id attempt source_head_sha candidate_attempt gate command_sha256 environment_sha256 log_sha256) }
sub ci_key { my $s=shift; return 'ci:'.sha256_hex($json->encode([@{$s}{qw(repo source_run_id attempt source_head_sha)}])) }
sub ci_source_ok {
  my $s=shift;
  keys_only($s,'schema',ci_source_fields(),qw(log_ref source_kind));
  fail('CI来源版本/身份/路径非法') unless $s->{schema} eq 'qwb-ci-source-v1' && $s->{repo} eq text($root) && id_ok($s->{source_run_id}) && id_ok($s->{attempt}) && id_ok($s->{candidate_attempt}) && $s->{gate}=~/\A(fast|full)\z/ && string_ok($s->{log_ref}) && $s->{log_ref}=~m{\A/} && $s->{source_kind}=~/\A(fixture|downloaded-receipt)\z/;
  fail('CI来源摘要非法') unless $s->{source_head_sha}=~/\A[0-9a-f]{40,64}\z/ && !grep { !defined($s->{$_}) || ref($s->{$_}) || $s->{$_}!~/\A[0-9a-f]{64}\z/ } qw(command_sha256 environment_sha256 log_sha256);
}
sub ci_report_ok {
  my ($r,$s)=@_;
  keys_only($r,'schema',ci_source_fields(),qw(classification evidence hypotheses next_step tokens));
  fail('CI提案版本/来源不匹配') unless $r->{schema} eq 'qwb-ci-diagnosis-v1' && !grep { !string_ok($r->{$_}) || $r->{$_} ne $s->{$_} } ci_source_fields();
  fail('CI提案分类/成本非法') unless $r->{classification}=~/\A(superseded|timeout|failure|retry-green)\z/ && defined($r->{tokens}) && !ref($r->{tokens}) && $r->{tokens}=~/\A(unknown|[0-9]+)\z/;
  for my $key (qw(evidence hypotheses)) {
    fail('CI依据/假设非法') unless ref($r->{$key}) eq 'ARRAY' && @{$r->{$key}}<=16 && ($key ne 'evidence' || @{$r->{$key}});
    fail('CI依据/假设文本非法') if grep { !string_ok($_) || $_ eq '' || length(encode('UTF-8',$_))>4096 } @{$r->{$key}};
  }
  fail('CI最小下一步非法') unless string_ok($r->{next_step}) && $r->{next_step} ne '' && length(encode('UTF-8',$r->{next_step}))<=4096;
}
# Same safe FD, stable sidecar, latest-byte check and atomic publisher for tasks and posture.
sub publish {
  my ($out,$atomic)=@_;
  if ($absent) { fail('模式记录在锁内被外部创建') if -e $file || -l $file }
  else {
    my $check=safe_open($file,O_RDONLY); my $latest=do { local $/; <$check> }; close $check;
    fail('票在锁内被旧writer改动，停新动作并对账') unless $latest eq $raw;
  }
  if (!$atomic) {
    my $w=safe_open($file,O_RDWR); seek($w,0,0) or fail('legacy seek失败');
    print {$w} $out or fail('legacy写失败'); truncate($w,length($out)) or fail('legacy truncate失败'); close $w or fail('legacy close失败');
  } else {
    my ($w,$tmp)=tempfile('.qwb-publish-XXXXXXXX',DIR=>$parent,UNLINK=>0);
    my $ok=eval {
      binmode $w;
      my $mode=$absent ? 0600 : (stat($file))[2]&0777;
      chmod($mode,$tmp) or fail('candidate chmod失败');
      print {$w} $out or fail('candidate写失败'); $w->sync or fail('candidate sync失败'); close $w or fail('candidate close失败');
      if ($creating) {
        link($tmp,$file) or fail('新票不覆盖原子发布失败'); unlink($tmp) or fail('新票临时路径回收失败');
      } else { system('mv','-f','--',$tmp,$file)==0 or fail('候选发布失败') }
      1;
    };
    if (!$ok) { my $error=$@; close $w; unlink $tmp; die $error }
  }
}
if ($posture) {
  fail('mode命令/参数非法') unless $cmd =~ /\Amode-(enter|exit|status|summary)\z/ && $expect eq '' && $event eq '';
  my $p={schema=>1,rev=>0,mode=>'online',events=>[]};
  unless ($absent) {
    fail('模式记录格式损坏，保留现场') unless $body =~ /\A# QW buddy 项目模式\n\n<!-- qwb-posture-v1\n([^\n]+)\n-->\n\z/;
    $p=strict_json(encode('UTF-8',$1));
  }
  keys_only($p,qw(schema rev mode events));
  fail('模式schema损坏') unless $p->{schema} eq '1' && ref($p->{events}) eq 'ARRAY' && $p->{rev}=~/\A[0-9]+\z/ && $p->{rev}==@{$p->{events}};
  my ($current,$seq,$auth,$limits)=('online',0,'','');
  for my $e (@{$p->{events}}) {
    keys_only($e,qw(seq at kind from to actor words auth_ref limits));
    fail('模式事件损坏') unless defined($e->{seq}) && !ref($e->{seq}) && $e->{seq}=~/\A[1-9][0-9]*\z/ && $e->{seq}==++$seq && $e->{at}=~/\A[1-9][0-9]*\z/ && string_ok($e->{actor}) && $e->{actor} ne '' && $e->{from} eq $current;
    for (qw(words limits)) { fail('模式原话/限制损坏') unless defined($e->{$_}) && !ref($e->{$_}) && $e->{$_} !~ /\x00/ && length(encode('UTF-8',$e->{$_}))<=65536 }
    fail('模式原话缺失') if $e->{words} eq '';
    if ($e->{kind} eq 'enter') {
      fail('模式/原授权引用损坏') unless $current eq 'online' && $e->{to}=~/\A(quiet|away)\z/ && id_ok($e->{auth_ref});
      ($auth,$limits)=@{$e}{qw(auth_ref limits)};
    } else {
      fail('模式退出规则损坏') unless $current ne 'online' && $e->{kind}=~/\A(user|explicit)\z/ && $e->{to} eq ($e->{kind} eq 'explicit' || $current eq 'away' ? 'online' : 'quiet') && $e->{auth_ref} eq $auth && $e->{limits} eq $limits;
    }
    $current=$e->{to};
  }
  fail('模式快照与历史不符') unless $p->{mode} eq $current;
  if ($cmd eq 'mode-enter' || $cmd eq 'mode-exit') {
    # Match the ledger's existing controller owner, with the same directory lock.
    fail('主控锁符号链接非法') if -l "$parent/.controller.lock";
    my $owner_raw=read_file("$parent/.controller.lock/owner");
    my ($owner)=$owner_raw =~ /^\S+\s+(\S+)\s*\z/;
    fail('模式变更仅现有主控；同UID防误用，不是OS沙箱') unless defined($owner) && $owner eq $actor;
    my ($kind,$to,$words);
    if ($cmd eq 'mode-enter') {
      fail('enter需quiet|away、原auth_ref、原话、限制；先显式退出旧模式') unless @args==4 && $current eq 'online' && $args[0]=~/\A(quiet|away)\z/ && id_ok($args[1]);
      ($to,$auth,$words,$limits)=@args; $kind='enter';
    } else {
      fail('exit仅接受真实user返回或explicit退出，系统门铃不是返回') unless @args==2 && $current ne 'online' && $args[0]=~/\A(user|explicit)\z/;
      ($kind,$words)=@args; $to=$kind eq 'explicit' || $current eq 'away' ? 'online' : 'quiet';
    }
    for ($words,$limits) { fail('原话/限制非法') unless defined($_) && !ref($_) && !/\x00/ && length(encode('UTF-8',$_))<=65536 }
    fail('原话不能为空') if $words eq '';
    push @{$p->{events}},{seq=>++$p->{rev},at=>int(time()*1000),kind=>$kind,from=>$current,to=>$to,actor=>$actor,words=>$words,auth_ref=>$auth,limits=>$limits};
    $p->{mode}=$to;
    publish(encode('UTF-8',"# QW buddy 项目模式\n\n<!-- qwb-posture-v1\n").$json->encode($p)."\n-->\n",1);
  } else { fail('status/summary不接受参数') if @args }
  if ($cmd eq 'mode-summary') {
    # Never hold posture while taking task locks: land reads posture under task lock.
    flock($guard,LOCK_UN) or fail('模式读锁释放失败');
    my @tasks;
    fail('summary tasks目录非法') if -l "$root/tasks";
    opendir my $tasks,"$root/tasks" or fail('summary tasks目录不可读');
    my @names=sort grep { /\.md\z/ } readdir $tasks; closedir $tasks;
    for my $name (@names) {
      my $t="$root/tasks/$name";
      my $row={task=>text($t)};
      my $ok=eval {
        my $s=read_file($t);
        if ($s !~ /^state:/m) { $row->{non_task}=1 } else {
        my $pid=open(my $probe,'-|'); defined($pid) or fail('无法启动逐票reader');
        if (!$pid) { exec('bash',"$bindir/qwb-ledger.sh",'read','--project',$root,'--task',$t) or exit 255 }
        my $out=do { local $/; <$probe> }; close $probe or fail('逐票协议损坏/不可读');
        my $d=strict_json($out);
        $row->{phase}=$d->{phase}; $row->{legacy}=$d->{schema} eq '0' ? 1 : 0;
        $row->{verdict}=$d->{gate} ? $d->{gate}{verdict} : 'unknown';
        $row->{failed_checks}=[grep { $_->{receipt}{rc}!=0 } @{$d->{gate}{receipts} // []}];
        $row->{findings}=$d->{gate}{findings} // {};
        $row->{land}=$d->{land};
        $row->{delivery}=$d->{land} && $d->{land}{stage}=~/\A(landed|closed)\z/ ? 'landed' : 'not-proven';
        $row->{cleanup}=$d->{land} ? ($d->{land}{stage} eq 'closed' ? 'closed' : 'pending') : 'unknown';
        $row->{implementation_done}=[grep { $_->{kind} eq 'done' } @{$d->{events}}];
        $row->{failures}=[grep { $_->{kind}=~/\A(blocked|not-sent)\z/ } @{$d->{events}}];
        $row->{decisions}={map { $_=>$d->{questions}{$_} } grep { $d->{questions}{$_}{resumed} eq '' } keys %{$d->{questions} // {}}};
        $row->{handoffs}=[grep { !$_->{handled} } values %{$d->{handoffs} // {}}];
        $row->{claim}=$d->{claim};
        }
        1;
      };
      next if $row->{non_task};
      $row->{error}=text(encode('UTF-8',$@)) unless $ok;
      push @tasks,$row;
    }
    print $json->encode({posture=>$p,tasks=>\@tasks}),"\n";
  } else { print $json->encode($p),"\n" }
  exit;
}
my $has_protocol=index($body,'<!-- qwb-collab-')>=0;
my $data;
if ($body =~ /\n<!-- qwb-collab-v1\n([^\n]+)\n-->\n?\z/) {
  $data=strict_json(encode('UTF-8',$1));
  $body=substr($body,0,$-[0]);
} elsif (index($body,'<!-- qwb-collab-')>=0) { fail('协作区格式非法') }
sub state_of { my ($s)=$_[0]=~/^state:[ \t]*(\S+)[ \t]*$/m; return $s // '' }
sub fp_of { my ($s)=$_[0]=~/^scenarios-fp:[ \t]*([0-9a-f]{40})[ \t]*$/m; return $s // '' }
sub scenario {
  my $s=shift; my $block=''; my $on=0;
  my $heading=$byte_legacy ? decode('ISO-8859-1',encode('UTF-8','验收场景')) : '验收场景';
  for my $l (split /\n/,$s,-1) {
    if (!$on && $l =~ /^\#{1,6}[^#]*\Q$heading\E/) { $on=1; $block.="$l\n"; next }
    $on=0 if $on && ($l =~ /^\#{1,2}[^#]/ || $l =~ /^(working|done|blocked|needs-decision|dispatch|not-sent|wake|worktree|worktree-space|scenarios-fp):/);
    $block.="$l\n" if $on;
  }
  $block =~ s/\n+\z//; return $block;
}
sub scenarios_ok {
  my ($s,$heading)=@_; $heading //= qr/\A## 验收场景\n/;
  return $s =~ $heading && $s =~ /Given/ && $s =~ /When/ && $s =~ /Then/ && $s =~ /失败|拒绝|fail|error/i && index($s,'<!-- qwb-collab-')<0;
}
sub scen_fp { sha1_hex(encode($byte_legacy ? 'ISO-8859-1' : 'UTF-8',scenario($_[0]))) }
sub list_ok {
  my ($v,$label)=@_; fail("$label 非法") unless ref($v) eq 'ARRAY';
  fail("$label 字段非法") if grep { !string_ok($_) || $_ eq '' } @$v;
  my %seen; fail("$label 重复") if grep { $seen{$_}++ } @$v;
}
sub packages_ok {
  my $p=shift; fail('packages非法') unless ref($p) eq 'HASH' && keys(%$p) && keys(%$p)<=64;
  my %seen;
  for my $id (keys %$p) { fail('工作包id/任务路径歧义') unless id_ok($id) && string_ok($p->{$id}) && $p->{$id}=~/\A[A-Za-z0-9_.-]+\.md\z/ && !$seen{$p->{$id}}++ }
}
sub needs_ok {
  my $n=shift; keys_only($n,qw(start accept land));
  for my $phase (qw(start accept land)) {
    fail('依赖集合非法') unless ref($n->{$phase}) eq 'ARRAY'; my %seen;
    for my $edge (@{$n->{$phase}}) {
      keys_only($edge,qw(task artifact version spec_rev condition));
      fail('依赖键/版本/条件非法或歧义') unless string_ok($edge->{task}) && $edge->{task}=~/\A[A-Za-z0-9_.-]+\.md\z/ && id_ok($edge->{artifact}) && id_ok($edge->{version}) && defined($edge->{spec_rev}) && !ref($edge->{spec_rev}) && $edge->{spec_rev}=~/\A[0-9]+\z/ && $edge->{condition}=~/\A(available|accepted|landed)\z/ && !$seen{"$edge->{task}\0$edge->{artifact}"}++;
    }
  }
}
sub authorization_ok {
  my $a=shift; keys_only($a,qw(workers permissions evidence budget profiles workers_sha256));
  list_ok($a->{workers},'workers'); list_ok($a->{permissions},'permissions');
  fail('启动授权/预算未明确') unless @{$a->{workers}} && string_ok($a->{evidence}) && $a->{evidence} ne '' && defined($a->{budget}) && !ref($a->{budget}) && $a->{budget}=~/\A[1-9][0-9]*\z/ && $a->{budget}<=64 && $a->{workers_sha256}=~/\A[0-9a-f]{64}\z/ && ref($a->{profiles}) eq 'HASH';
  fail('工人型号缺失') unless keys(%{$a->{profiles}})==@{$a->{workers}};
  for my $w (@{$a->{workers}}) { keys_only($a->{profiles}{$w},qw(model provider effort)); fail('工人型号未知') if grep { !string_ok($_) || $_ eq '' } values %{$a->{profiles}{$w}} }
}
sub authority_validate {
  my $a=shift; keys_only($a,qw(identity request_id source_event packages paths authorization));
  fail('规划身份非法') unless ref($a->{identity}) eq 'HASH' && ($a->{identity}{role} // '') eq '规划' && id_ok($a->{request_id}) && id_ok($a->{source_event});
  packages_ok($a->{packages}); list_ok($a->{paths},'paths'); authorization_ok($a->{authorization});
}
sub planning_validate {
  my $p=shift; keys_only($p,qw(request_id package_id packages source intent spec constraints paths needs authority authorization creation_sha256 artifacts ready revisions pending_revision revision_handoff landed));
  fail('规划request/版本非法') unless id_ok($p->{request_id}) && id_ok($p->{package_id}) && $p->{creation_sha256}=~/\A[0-9a-f]{64}\z/;
  packages_ok($p->{packages}); keys_only($p->{source},qw(task event text));
  fail('source非法') unless string_ok($p->{source}{task}) && id_ok($p->{source}{event}) && string_ok($p->{source}{text}) && $p->{source}{text} ne '';
  for (qw(intent spec constraints)) { fail('规划正文非法') unless defined($p->{$_}) && !ref($p->{$_}) && $p->{$_} ne '' && index($p->{$_},'<!-- qwb-collab-')<0 }
  list_ok($p->{paths},'paths'); needs_ok($p->{needs});
  authority_validate($p->{authority}) if defined $p->{authority}; authorization_ok($p->{authorization}) if defined $p->{authorization};
  fail('规划历史/产物非法') unless ref($p->{artifacts}) eq 'HASH' && ref($p->{ready}) eq 'HASH' && ref($p->{revisions}) eq 'ARRAY';
  for my $name (keys %{$p->{artifacts}}) {
    my $a=$p->{artifacts}{$name}; keys_only($a,qw(version spec_rev ref sha256));
    fail('产物非法') unless id_ok($name) && id_ok($a->{version}) && $a->{spec_rev}=~/\A[0-9]+\z/ && string_ok($a->{ref}) && $a->{sha256}=~/\A[0-9a-f]{64}\z/;
  }
}
sub validate {
  # 协议存在与JSON值真假无关；null/false/0必须拒绝，不能剥标记降级legacy。
  return unless $has_protocol || defined($data);
  my @optional_keys=grep { exists $data->{$_} } qw(handoffs gate land land_history planning planning_authority test_requests ci);
  keys_only($data,qw(schema rev seq spec_rev phase claim workers questions events ops migration),@optional_keys);
  fail('schema版本非法') unless defined($data->{schema}) && !ref($data->{schema}) && $data->{schema} eq '1';
  for (qw(rev seq spec_rev)) { fail("${_}非法") unless defined($data->{$_}) && !ref($data->{$_}) && $data->{$_} =~ /\A[0-9]+\z/ }
  fail('phase/state非法') unless $data->{phase} eq state_of($body) && $data->{phase} =~ /\A(running|blocked|needs-decision|done|verified)\z/;
  fail('重复头部键') if (()=$body =~ /^state:/mg)>1 || (()=$body =~ /^scenarios-fp:/mg)>1;
  fail('events非法') unless ref($data->{events}) eq 'ARRAY';
  fail('版本/事件计数不一致') unless $data->{seq}==@{$data->{events}} && $data->{rev}==$data->{seq};
  my (%seen,$seq); $seq=0;
  for my $e (@{$data->{events}}) {
    keys_only($e,qw(event_id seq at kind actor op_id spec_rev line));
    fail('event非法/重复/乱序') unless id_ok($e->{event_id}) && !$seen{$e->{event_id}}++ && $e->{seq}==++$seq && string_ok($e->{actor}) && string_ok($e->{line}) && id_ok($e->{kind}) && ($e->{op_id} eq '' || id_ok($e->{op_id})) && $e->{spec_rev}=~/\A[0-9]+\z/ && $e->{spec_rev}<=$data->{spec_rev} && $e->{at}=~/\A\d{4}-\d\d-\d\dT\d\d:\d\d:\d\dZ\z/;
  }
  if (exists $data->{handoffs}) {
    fail('handoffs非法') unless ref($data->{handoffs}) eq 'HASH';
    my %corr;
    for my $id (keys %{$data->{handoffs}}) {
      my $h=$data->{handoffs}{$id};
      keys_only($h,qw(event_id corr attempt recipient source_event source_seq source_actor payload transport_count transport_at received accepted owner_fp op_id activity_at wait_until wait_reason prepared handled result_ref result_sha256));
      fail('handoff身份非法') unless id_ok($id) && $id eq $h->{event_id} && id_ok($h->{corr}) && id_ok($h->{attempt}) && $h->{recipient} eq 'controller' && $seen{$h->{source_event}} && $h->{source_seq} > 0 && $h->{source_seq} <= $seq;
      fail('handoff关联重复') if $corr{"$h->{corr}\0$h->{attempt}"}++;
      my ($source)=grep { $_->{event_id} eq $h->{source_event} } @{$data->{events}};
      fail('handoff来源不一致') unless $source->{seq} == $h->{source_seq} && $source->{actor} eq $h->{source_actor};
      for (qw(source_actor payload received accepted owner_fp op_id wait_reason result_ref result_sha256)) { fail('handoff字段非法') unless string_ok($h->{$_}) }
      for (qw(transport_count transport_at activity_at wait_until prepared handled)) { fail('handoff数值非法') unless defined($h->{$_}) && !ref($h->{$_}) && $h->{$_} =~ /\A[0-9]+\z/ }
      fail('handoff状态非法') unless $h->{transport_count}<=3 && $h->{prepared}<=1 && $h->{handled}<=1 && ($h->{op_id} eq '' || id_ok($h->{op_id})) && ($h->{accepted} eq '' ? $h->{op_id} eq '' && $h->{owner_fp} eq '' && !$h->{prepared} && !$h->{handled} : $h->{received} ne '' && $h->{op_id} ne '' && $h->{owner_fp}=~/\A[0-9a-f]{64}\z/) && (!$h->{handled} || $h->{prepared} && $h->{result_ref} ne '' && $h->{result_sha256}=~/\A[0-9a-f]{64}\z/);
    }
  }
  if (exists $data->{gate}) {
    keys_only($data->{gate},qw(identity binding receipts reviews findings verdict rounds dispatches));
    my $g=$data->{gate};
    fail('gate集合非法') unless ref($g->{receipts}) eq 'ARRAY' && ref($g->{reviews}) eq 'ARRAY' && ref($g->{findings}) eq 'HASH' && ref($g->{dispatches}) eq 'HASH' && ref($g->{rounds}) eq 'ARRAY';
    keys_only($g->{identity},identity_keys());
    fail('gate身份非法') unless id_ok($g->{identity}{actor}) && string_ok($g->{identity}{pane}) && $g->{identity}{pane} ne '' && $g->{identity}{incarnation}=~/\A[1-9][0-9]*\z/ && $g->{identity}{owner_fp}=~/\A[0-9a-f]{64}\z/;
    my $b=$g->{binding}; keys_only($b,qw(candidate base attempt policy environment required workers spec_rev scenarios_fp spec_sha256 head tree workers_sha256 worker_profiles), exists($b->{test_policy_sha256}) ? 'test_policy_sha256' : ());
    fail('gate绑定非法') unless id_ok($b->{attempt}) && id_ok($b->{policy}) && $b->{candidate}=~m{\A/} && $b->{environment}=~m{\A/} && $b->{spec_rev}=~/\A[0-9]+\z/ && $b->{scenarios_fp}=~/\A[0-9a-f]{40}\z/ && $b->{spec_sha256}=~/\A[0-9a-f]{64}\z/ && ref($b->{required}) eq 'HASH' && exists($b->{required}{full});
    fail('gate策略摘要非法') if exists($b->{test_policy_sha256}) && $b->{test_policy_sha256}!~/\A[0-9a-f]{64}\z/;
    fail('gate候选OID非法') for grep { !defined($_) || !/\A[0-9a-f]{40,64}\z/ } @{$b}{qw(base head tree)};
    for my $name (keys %{$b->{required}}) { fail('gate场景映射非法') unless $name=~/\A(fast|full)\z/ && ref($b->{required}{$name}) eq 'ARRAY' && @{$b->{required}{$name}} }
    keys_only($b->{workers},qw(review rework)); keys_only($b->{worker_profiles},qw(review rework));
    for my $p (values %{$b->{worker_profiles}}) { keys_only($p,qw(model provider effort)); fail('gate型号配置非法') if grep { !string_ok($_) || $_ eq '' } values %$p }
    for my $id (keys %{$g->{dispatches}}) { fail('gate child op非法') unless exists($data->{ops}{$id}) && $g->{dispatches}{$id}=~/\A(review|rework)\z/ }
    fail('gate verdict非法') unless $data->{gate}{verdict}=~/\A(pending|rework|rediagnose|accepted)\z/;
  }
  fail('land_history非法') if exists($data->{land_history}) && ref($data->{land_history}) ne 'ARRAY';
  if (exists $data->{land}) {
    my $l=$data->{land}; keys_only($l,qw(op_id auth_ref reason caller owner_fp main before after context md stage branch prepared_at landed_at closed_at));
    fail('land授权/阶段非法') unless id_ok($l->{op_id}) && id_ok($l->{auth_ref}) && string_ok($l->{reason}) && $l->{reason} ne '' && $l->{caller} ne '' && $l->{owner_fp}=~/\A[0-9a-f]{64}\z/ && $l->{main} eq 'refs/heads/main' && $l->{stage}=~/\A(authorized|prepared|landed|closed)\z/ && ref($l->{md}) eq 'ARRAY' && ref($l->{context}) eq 'HASH';
    fail('land OID非法') unless $l->{before}=~/\A[0-9a-f]{40,64}\z/ && $l->{after} eq $l->{context}{head};
  }
  planning_validate($data->{planning}) if exists $data->{planning};
  authority_validate($data->{planning_authority}) if exists $data->{planning_authority};
  if (exists $data->{test_requests}) {
    fail('test_requests非法') unless ref($data->{test_requests}) eq 'HASH';
    for my $id (keys %{$data->{test_requests}}) {
      my $r=$data->{test_requests}{$id};
      keys_only($r,qw(event_id identity reason scenario context reply reply_sha256));
      keys_only($r->{identity},identity_keys());
      fail('test请求非法') unless id_ok($id) && $seen{$r->{event_id}} && $r->{reason}=~/\A(new-behavior|policy-gap|complex-failure|rediagnose)\z/ && string_ok($r->{scenario}) && ref($r->{context}) eq 'HASH' && ref($r->{reply}) eq 'HASH' && defined($r->{reply_sha256}) && $r->{reply_sha256}=~/\A(?:[0-9a-f]{64})?\z/;
      fail('test身份非法') unless id_ok($r->{identity}{actor}) && string_ok($r->{identity}{pane}) && $r->{identity}{pane} ne '' && $r->{identity}{incarnation}=~/\A[1-9][0-9]*\z/ && $r->{identity}{owner_fp}=~/\A[0-9a-f]{64}\z/;
      keys_only($r->{reply},qw(task request_id context validation tests)) if $r->{reply_sha256} ne '';
    }
  }
  if (exists $data->{ci}) {
    keys_only($data->{ci},qw(requests reports));
    fail('CI集合非法') unless ref($data->{ci}{requests}) eq 'HASH' && ref($data->{ci}{reports}) eq 'HASH';
    for my $key (keys %{$data->{ci}{requests}}) {
      my $q=$data->{ci}{requests}{$key}; keys_only($q,qw(identity source context));
      keys_only($q->{identity},identity_keys());
      ci_source_ok($q->{source}); fail('CI关联/上下文非法') unless $key eq ci_key($q->{source}) && ref($q->{context}) eq 'HASH';
    }
    for my $key (keys %{$data->{ci}{reports}}) {
      my $q=$data->{ci}{requests}{$key} // fail('CI报告缺授权来源'); my $r=$data->{ci}{reports}{$key};
      keys_only($r,qw(report sha256 ref event_id)); ci_report_ok($r->{report},$q->{source});
      fail('CI报告来源/交接非法') unless $r->{sha256}=~/\A[0-9a-f]{64}\z/ && string_ok($r->{ref}) && $r->{ref}=~m{\A/} && exists($data->{handoffs}{$r->{event_id}}) && $data->{handoffs}{$r->{event_id}}{corr} eq $key && $data->{handoffs}{$r->{event_id}}{payload} eq text($json->encode($r->{report}));
    }
  }
  keys_only($data->{migration},qw(task_sha256 confirm installed));
  fail('migration摘要非法') unless $data->{migration}{task_sha256}=~/\A[0-9a-f]{64}\z/;
  keys_only($data->{migration}{confirm},qw(run wake worktree worker controller old-fds external-actions));
  fail('migration确认非法') for grep { !string_ok($_) || $_ eq '' } values %{$data->{migration}{confirm}};
  fail('安装清单非法') unless ref($data->{migration}{installed}) eq 'HASH' && keys(%{$data->{migration}{installed}})==7;
  fail('安装摘要非法') for grep { !defined($_) || ref($_) || !/\A[0-9a-f]{64}\z/ } values %{$data->{migration}{installed}};
  for (qw(workers questions ops)) { fail("${_}对象非法") unless ref($data->{$_}) eq 'HASH' }
  if (defined $data->{claim}) {
    keys_only($data->{claim},qw(owner op_id));
    fail('claim非法') unless string_ok($data->{claim}{owner}) && id_ok($data->{claim}{op_id});
  }
  for my $p (keys %{$data->{workers}}) { fail('worker非法') unless string_ok($p) && id_ok($data->{workers}{$p}) && exists $data->{ops}{$data->{workers}{$p}} }
  for my $k (keys %{$data->{ops}}) {
    keys_only($data->{ops}{$k},qw(owner pane status));
    fail('op非法') unless id_ok($k) && string_ok($data->{ops}{$k}{owner}) && string_ok($data->{ops}{$k}{pane}) && $data->{ops}{$k}{status}=~/\A(claimed|dispatch|not-sent|sent|released)\z/;
  }
  for my $k (keys %{$data->{questions}}) {
    keys_only($data->{questions}{$k},qw(opened answer resumed));
    fail('question非法') unless id_ok($k) && string_ok($data->{questions}{$k}{opened}) && string_ok($data->{questions}{$k}{answer}) && string_ok($data->{questions}{$k}{resumed});
  }
}
validate();
if ($cmd eq 'read') {
  print $json->encode($data // {schema=>0,phase=>state_of($body),events=>[],time=>'unknown'}),"\n"; exit;
}
if ($cmd eq 'metrics') {
  my @events=$data ? @{$data->{events}} : ();
  my @done=grep { $_->{kind} eq 'done' } @events;
  my $land=$data ? $data->{land} : undef; my ($ready,$duration)=('unknown','unknown');
  if ($land) {
    my @ready=grep { $_->{kind} eq 'gate-verdict' && $_->{line}=~/\bverdict=accepted\b/ && $_->{line}=~/\bhead=\Q$land->{after}\E\b/ } @events;
    if (@ready) {
      $ready=$ready[-1]{at}; my @t=$ready=~/\A(\d{4})-(\d\d)-(\d\d)T(\d\d):(\d\d):(\d\d)Z\z/;
      require Time::Local;
      $duration=$land->{landed_at}/1000-Time::Local::timegm($t[5],$t[4],$t[3],$t[2],$t[1]-1,$t[0]) if $land->{landed_at};
    }
  }
  print $json->encode({events=>\@events,done_at=>@done ? $done[-1]{at} : 'unknown',legacy_times=>'unknown',land=>$land,ready_at=>$ready,ready_to_land_seconds=>$duration,tokens=>'unknown'}),"\n"; exit;
}
my $dir="$root/qwbuddy";
my ($controller_guard,$land_guard);
# 同目录锁与qwb-lock共用，只包权限复核/短发布，不包外部动作。
if (-d $dir && !-l $dir && realpath($dir) eq $dir) {
  open $controller_guard,'<',$dir or fail('主控目录不可读');
  flock($controller_guard,LOCK_EX) or fail('主控目录flock失败');
  inherit_guard($controller_guard);
} else { fail('主控目录非法') unless !$data && $legacy && !-e $dir && !-l $dir }
my ($owner,$owner_raw)=('','');
if (-e "$dir/.controller.lock/owner") {
  fail('主控锁符号链接非法') if -l "$dir/.controller.lock" || -l "$dir/.controller.lock/owner";
  my $own=safe_open("$dir/.controller.lock/owner",O_RDONLY);
  $owner_raw=<$own> // ''; close $own;
  ($owner)=$owner_raw =~ /^\S+\s+(\S+)\s*\z/; $owner //='';
}
my $owner_fp=sha256_hex($owner_raw);
my $controller=$owner ne '' && $owner eq $actor;
my $worker=$data && exists $data->{workers}{$actor};
my $identity=strict_json($identity_raw);
my $planner_native=($identity->{role} // '') eq '规划' && ($identity->{pane} // '') eq $actor && ($identity->{owner_fp} // '') eq $owner_fp;
my $planning_grant=$data ? ($data->{planning_authority} // ($data->{planning} ? $data->{planning}{authority} : undef)) : undef;
my $planner=$planner_native && $planning_grant && $json->encode($identity) eq $json->encode($planning_grant->{identity});
my $test=$data && $identity->{pane} && grep { $json->encode($_->{identity}) eq $json->encode($identity) && $identity->{pane} eq $actor && $identity->{owner_fp} eq $owner_fp } values %{$data->{test_requests} // {}};
my $gate=$data && $data->{gate} && $identity->{pane} && $identity->{pane} eq $actor && $json->encode($identity) eq $json->encode($data->{gate}{identity}) && $identity->{owner_fp} eq $owner_fp;
sub native_reply {
  # Herdr失败JSON在stderr；合并后严格解析整份回复，混入诊断/第二份JSON仍拒绝。
  my $pid=open(my $probe,'-|'); defined($pid) or fail('原生身份探针无法启动');
  if (!$pid) {
    open STDERR,'>&',STDOUT or exit 255;
    exec('herdr',@_) or exit 255;
  }
  my $s=do { local $/; <$probe> } // ''; close $probe; my $rc=$?;
  my $j=strict_json($s); fail('原生身份回复不是对象') unless ref($j) eq 'HASH';
  return ($j,$rc);
}
my $wake_cmd=$cmd eq 'wake' || $cmd eq 'wake-check';
my $handoff_watch=$cmd eq 'handoff-pending' || $cmd eq 'handoff-transport';
my $watcher=0;
if ($data && ($wake_cmd || $handoff_watch || $cmd eq 'plan-ready') && !$controller && !$gate && !$planner) {
  # .watch由主控ensure在同一目录锁内登记，绑定原owner文件代次；换主控自动失效。
  my $w=safe_open("$dir/.watch",O_RDONLY); my $s=<$w> // ''; close $w;
  my ($pane,$target,$generation)=$s =~ /\Apane=(\S+) workspace=\S+ pid=\S* started=\S+ controller=(\S+) owner-fp=([0-9a-f]{64}) cmd=/;
  fail('值守未获本代主控wake授权') unless defined($pane) && $pane eq $actor && $target eq $owner && ($args[0] // '') eq $owner && $generation eq $owner_fp;
  my ($j,$rc)=native_reply('pane','process-info','--pane',$actor);
  fail('值守原生进程身份未知') if $rc;
  my $pi=$j->{result}{process_info}; fail('值守进程信息非法') unless ref($pi) eq 'HASH' && ref($pi->{foreground_processes}) eq 'ARRAY';
  for my $p (@{$pi->{foreground_processes}}) {
    next unless ($p->{pid} // '') eq getppid() && ref($p->{argv}) eq 'ARRAY';
    my @a=@{$p->{argv}};
    next unless @a>=2 && $a[0]=~m{(?:^|/)(?:bash|sh|zsh)\z};
    my $script=-f $a[1] ? realpath($a[1]) : undef;
    next unless defined($script) && -f "$bindir/qwb-wake.sh" && $script eq (realpath("$bindir/qwb-wake.sh") // '');
    my ($project,$dest);
    for (my $i=2;$i<@a;$i++) {
      $project=$a[$i+1] if $a[$i] eq '--project';
      $dest=$a[$i+1] if $a[$i] eq '--pane';
    }
    next if grep { /\A--(?:ensure|check|dry-run|block)\z/ } @a;
    $watcher=1 if defined($project) && (realpath($project) // '') eq $root && defined($dest) && $dest eq $owner;
  }
  fail('调用者不是登记pane的真实值守进程') unless $watcher;
}
if (!$data && $legacy && $cmd ne 'migrate' && $cmd ne 'new') {
  # expand期保留旧票格式与原inode；不能假称裸追加旧会话受新协议保护。
  # 仅已接线运行时可用；公开工人入口必须先受控迁票。
  fail('旧票仅支持运行时兼容动作') unless $cmd =~ /\A(check|start-check|wake-check|wake|append|prepare|revise|dispatch|not-sent)\z/;
} elsif ($cmd ne 'migrate' && $cmd ne 'new') { fail('旧票只读；先停写/对账/确认迁移') unless $data }
my $ci_actor=$cmd eq 'ci-report' && $identity->{pane} && $identity->{pane} eq $actor && $identity->{owner_fp} eq $owner_fp;
my $gate_allowed=$cmd =~ /\A(claim|release|check|append|dispatch|not-sent|gate-context|gate-reuse|test-request|gate-receipt|gate-review|gate-verdict|gate-candidate|gate-diff|gate-dispatch|revision-handoff|handoff-pending|handoff-received|handoff-accept|handoff-activity|handoff-prepared|handoff-handled)\z/;
my $planner_allowed=$cmd =~ /\A(start-check|plan-ready|plan-needs|plan-revision|revise|revise-scenarios|start-claim|claim|release|prepare|append|dispatch|not-sent|handoff-send|handoff-pending|handoff-received|handoff-accept|handoff-activity|handoff-prepared|handoff-handled)\z/;
fail('角色未授权（主控/绑定工人/本代门禁/范围内规划）') unless $controller || $watcher || $ci_actor || ($test && $cmd=~/\A(test-reply|handoff-received|handoff-accept|handoff-activity|handoff-prepared|handoff-handled)\z/) || ($gate && $gate_allowed) || ($planner && $planner_allowed) || ($planner_native && $cmd eq 'new') || ($worker && $cmd =~ /\A(append|question|handoff-send)\z/) || (!$data && $legacy && $cmd ne 'migrate' && $cmd ne 'new');
exit 0 if $cmd eq 'check';
if ($wake_cmd) {
  fail('wake参数非法') unless @args==3 && string_ok($args[0]) && $args[0] ne '' && $args[1]=~/\A(running|blocked|needs-decision)\z/ && $args[2]=~/\A[0-9a-f]{40}\z/;
  fail('wake目标不是当前主控') if $data && $args[0] ne $owner;
  exit 0 if $cmd eq 'wake-check';
}
fail('expect版本不是整数') if $expect ne '' && $expect !~ /\A[0-9]+\z/;
fail('期望版本冲突') if $data && $expect ne '' && $expect != $data->{rev};
fail('event_id非法') if $event ne '' && !id_ok($event);
if ($event ne '' && $data && grep { $_->{event_id} eq $event } @{$data->{events}}) { fail('event_id已存在，拒绝重放') }
fail('门禁只能处理本人持久claim的票') if $gate && $cmd ne 'claim' && (!$data->{claim} || $data->{claim}{owner} ne $actor);
my ($kind,$line,$op)=($cmd,'','');
my $now=int(time()*1000);
my $pending_output;
my $pending_exit=0;
my $handoff_return;
sub source_id { my $id=shift; return 'source:'.(length($id)<=153 ? $id : sha256_hex($id)) }
sub new_handoff {
  my ($id,$corr,$attempt,$source,$payload)=@_;
  return {event_id=>$id,corr=>$corr,attempt=>$attempt,recipient=>'controller',source_event=>$source->{event_id},source_seq=>$source->{seq},source_actor=>$source->{actor},payload=>$payload,transport_count=>0,transport_at=>0,received=>'',accepted=>'',owner_fp=>'',op_id=>'',activity_at=>0,wait_until=>0,wait_reason=>'',prepared=>0,handled=>0,result_ref=>'',result_sha256=>''};
}
sub handoff_due {
  my ($h,$retry)=@_;
  return 0 if $h->{handled} || $h->{transport_count}>=3;
  # 回复迟到不是失活；工具活动或有界合理wait保住本代claim。
  if ($h->{accepted} ne '' && $h->{owner_fp} eq $owner_fp) {
    return 0 if $now < $h->{wait_until} || $now-$h->{activity_at} < $retry;
  }
  return !$h->{transport_at} || $now-$h->{transport_at} >= $retry;
}
sub append_body { $body =~ s/\n?\z/\n/; $body.="$_[0]\n" }
sub field {
  my ($key,$val)=@_;
  my $n=()=$body =~ /^\Q$key\E:/mg; fail("重复$key") if $n>1;
  if ($n) { $body =~ s/^\Q$key\E:[^\n]*/$key: $val/m }
  else { $body="$key: $val\n$body" }
}
sub child_in_flight {
  my $id=shift; my $status=$data->{ops}{$id}{status};
  return $status=~/\A(claimed|dispatch)\z/ || ($status eq 'sent' && !grep { $_->{op_id} eq $id && $_->{kind} eq 'done' } @{$data->{events}});
}
sub require_claim {
  my $id=shift; fail('op_id非法') unless id_ok($id);
  if ($data) {
    fail('无本人持久claim/op') unless $data->{claim} && $data->{claim}{owner} eq $actor && ($data->{claim}{op_id} eq $id || ($gate && exists($data->{gate}{dispatches}{$id}) && $data->{ops}{$id}{owner} eq $actor));
  }
}
sub capture {
  my @cmd=@_; my $pid=open(my $fh,'-|'); defined($pid) or fail('无法启动对象探针');
  if (!$pid) { exec @cmd or exit 255 }
  my $s=do { local $/; <$fh> } // ''; close $fh or fail('对象探针失败: '.join(' ',@cmd[0..1]));
  $s=~s/\n\z//; return $s;
}
sub json_file {
  my $s=read_file(encode('UTF-8',$_[0]));
  return (strict_json($s),sha256_hex($s));
}
sub ci_bytes {
  my $path=encode('UTF-8',shift);
  fail('CI本地来源路径须绝对且无符号链接重定向') unless $path=~m{\A/} && (realpath($path) // '') eq $path;
  my $fh=safe_open($path,O_RDONLY); my $s='';
  my $n=read($fh,$s,65537); close $fh;
  fail('CI来源为空/过大/读取失败（最多65536字节）') unless defined($n) && $n>0 && $n<=65536;
  return $s;
}
sub receipt_interval_ok {
  my $r=shift;
  return 0 if grep { !defined($r->{$_}) || ref($r->{$_}) || $r->{$_}!~/\A[0-9]+\z/ } qw(started_at ended_at elapsed_seconds);
  return $r->{ended_at}>=$r->{started_at} && $r->{elapsed_seconds}==$r->{ended_at}-$r->{started_at};
}
sub test_policy {
  my $rev=shift;
  fail('策略版本非法') unless $rev=~/\A[A-Za-z0-9_-]{1,80}\z/;
  my $path="$root/qwbuddy/test-policy/$rev.md";
  fail('策略目录非法') unless -d dirname($path) && !-l dirname($path) && realpath(dirname($path)) eq dirname($path);
  my $raw=read_file($path);
  my $s=text($raw);
  my %expected=(schema=>'qwb-test-policy-v1',policy_rev=>$rev,risks=>'normal high','required-gates'=>'full');
  for my $key (keys %expected) {
    my @values=$s=~/^\Q$key\E:[ \t]*(.*)$/mg;
    fail('策略契约重复/非法/降低full') unless @values==1 && $values[0] eq $expected{$key};
  }
  return sha256_hex($raw);
}
sub reusable_receipts {
  my ($c,$name)=@_;
  fail('门未授权') unless exists($c->{required}{$name});
  return () unless $c->{status} eq 'clean';
  my @matching=grep { $_->{receipt}{gate} eq $name && $json->encode($_->{receipt}{before}) eq $json->encode($c) && $json->encode($_->{receipt}{after}) eq $json->encode($c) } @{$data->{gate}{receipts}};
  return () if grep { !receipt_interval_ok($_->{receipt}) } @matching;
  my @failed=grep { $_->{receipt}{rc}!=0 } @matching;
  return grep { my $r=$_->{receipt}; $r->{rc}==0 && !grep { $r->{started_at}<=$_->{receipt}{ended_at} } @failed } @matching;
}
sub spec_body {
  my $s=shift; $s=~s/^(?:state|scenarios-fp|working|done|blocked|needs-decision|dispatch|not-sent|wake|worktree|worktree-space):[^\n]*\n?//mg;
  return $s;
}
sub gate_context {
  my $observe=shift // 0;
  my $g=$data->{gate} // fail('未授权门禁'); my $b=$g->{binding};
  fail('规格/场景已变；原收据失效，交主控重授权') unless $observe || $data->{spec_rev}==$b->{spec_rev} && scen_fp($body) eq $b->{scenarios_fp};
  my $spec=spec_body($body);
  fail('规格正文已变') unless $observe || sha256_hex(encode('UTF-8',$spec)) eq $b->{spec_sha256};
  my $c=encode('UTF-8',$b->{candidate});
  fail('候选路径变化') unless (realpath($c) // '') eq $c && capture('git','-C',$c,'rev-parse','--show-toplevel') eq $c;
  fail('候选非本项目副本') unless capture('git','-C',$c,'rev-parse','--path-format=absolute','--git-common-dir') eq capture('git','-C',$root,'rev-parse','--path-format=absolute','--git-common-dir');
  my $conf=-f "$c/qwbuddy/config.sh" ? "$c/qwbuddy/config.sh" : "$c/qwb.config.sh";
  my $cfg=read_file($conf);
  my $worker_config=read_file("$root/qwbuddy/workers.sh");
  fail('工人型号/effort配置已变，交主控重授权') unless $observe || sha256_hex($worker_config) eq $b->{workers_sha256};
  my $envbody=read_file(encode('UTF-8',$b->{environment}));
  my %commands;
  for my $name (keys %{$b->{required}}) {
    my $cmd=capture('bash','-c','. "$1" >&2; v="QWB_GATE_${2}"; printf "%s" "${!v}"','gate',$conf,uc($name));
    fail('必需门未配置') if $cmd eq '';
    $commands{$name}=sha256_hex($cmd);
  }
  my %environment=map { $_=>($ENV{$_} // '') } qw(PATH LANG LC_ALL LC_CTYPE CI NODE_ENV BASH_ENV SHELLOPTS);
  $environment{dependency}=sha256_hex($envbody);
  fail('相关工具环境无法绑定相对/空PATH目录') if grep { !m{\A/} } split /:/,($ENV{PATH} // ''),-1;
  for my $tool (qw(git bash perl python3 shellcheck herdr date ps shasum)) {
    my ($path)=grep { -f $_ && -x $_ } map { "$_/$tool" } split /:/,($ENV{PATH} // '');
    if (defined $path) {
      $path=realpath($path) // fail("环境工具路径未知: $tool");
      open my $binary,'<',$path or fail("环境工具不可读: $tool"); binmode $binary;
      my $digest=Digest::SHA->new(256); $digest->addfile($binary); close $binary;
      $environment{"tool:$tool"}=$digest->hexdigest;
    } else { $environment{"tool:$tool"}='missing' }
  }
  $environment{git}=capture('git','--version');
  $environment{bash}=capture('bash','--version'); $environment{system}=capture('uname','-sm');
  # 配置是可信shell，但采样放在source之后，不能把配置副作用之前的HEAD冒充当前对象。
  my $head=capture('git','-C',$c,'rev-parse','HEAD'); my $tree=capture('git','-C',$c,'rev-parse','HEAD^{tree}');
  fail('候选已变但未登记新attempt') unless $observe || ($head eq $b->{head} && $tree eq $b->{tree});
  my $dirty=capture('git','-C',$c,'status','--porcelain=v1','--untracked-files=all');
  capture('git','-C',$c,'merge-base','--is-ancestor',$b->{base},$head);
  my %policy;
  if (exists $b->{test_policy_sha256}) {
    my @refs=$body=~/^test-policy:[ \t]*(\S+)[ \t]*$/mg;
    fail('票策略引用变化') unless @refs==1 && $refs[0] eq $b->{policy};
    $policy{test_policy_sha256}=test_policy($b->{policy});
    fail('策略内容已变；保留旧版，显式修订后重授权') unless $observe || $policy{test_policy_sha256} eq $b->{test_policy_sha256};
  }
  return {%policy,task=>text($file),project=>text($root),candidate=>$b->{candidate},attempt=>$b->{attempt},base=>$b->{base},workers=>$b->{workers},worker_profiles=>$b->{worker_profiles},workers_sha256=>sha256_hex($worker_config),head=>$head,tree=>$tree,status=>$dirty eq '' ? 'clean' : 'dirty',dirty_sha256=>sha256_hex($dirty),spec_rev=>$data->{spec_rev},spec_sha256=>sha256_hex(encode('UTF-8',$spec)),scenarios_fp=>scen_fp($body),policy=>$b->{policy},required=>$b->{required},config=>text($conf),config_sha256=>sha256_hex($cfg),commands=>\%commands,environment_sha256=>sha256_hex($json->encode(\%environment))};
}
# land复用已accept的04证据；不授门禁新权限，不在main锁里跑门/审核。
sub last_spec_event {
  my $s=shift; my $spev='';
  while ($s =~ /^(blocked:\s*spec-defect:.*|working:\s*spec-resolved:.*)$/mg) { $spev=$1 }
  return $spev;
}
sub land_ready {
  my $c=gate_context(); my $g=$data->{gate};
  fail('未验收或验收条件已变') unless $g->{verdict} eq 'accepted' && $c->{status} eq 'clean' && @{$g->{reviews}} && $json->encode($g->{reviews}[-1]{review}{context}) eq $json->encode($c);
  for my $id (keys %{$g->{dispatches}}) {
    fail('仍有在途审核/返修') if child_in_flight($id);
  }
  fail('成立缺陷/安全意见未结') if grep { $_->{history}[-1]{classification}=~/\A(must-fix|unresolved)\z/ } values %{$g->{findings}};
  for my $q (values %{$data->{questions}}) { fail('相关问题未恢复') if $q->{resumed} eq '' }
  my $spev=last_spec_event($body);
  fail('规格疑点未决') if $spev =~ /^blocked:/;
  return $c;
}
sub land_identity {
  my $l=$data->{land} // fail('缺明确land授权');
  fail('land仅现主控本人claim；门禁未新增自主权限') unless $controller && @args==2 && $args[0] eq $l->{op_id} && $args[1] eq $l->{auth_ref} && $l->{caller} eq $actor && $l->{owner_fp} eq $owner_fp;
  require_claim($args[0]) unless $cmd eq 'land-close' && $l->{stage} eq 'closed'; return $l;
}
sub land_main {
  my $l=shift;
  fail('目标不是精确main主副本') unless capture('git','-C',$root,'rev-parse','--show-toplevel') eq $root && capture('git','-C',$root,'symbolic-ref','HEAD') eq $l->{main} && capture('git','-C',$root,'rev-parse','--path-format=absolute','--git-dir') eq capture('git','-C',$root,'rev-parse','--path-format=absolute','--git-common-dir');
  my $common=capture('git','-C',$root,'rev-parse','--path-format=absolute','--git-common-dir');
  for my $state (qw(MERGE_HEAD CHERRY_PICK_HEAD REVERT_HEAD rebase-merge rebase-apply)) { fail('main有未完Git操作') if -e "$common/$state" }
  return capture('git','-C',$root,'rev-parse',$l->{main});
}
sub land_md_snapshot {
  my $l=shift; my %allowed=map { encode('UTF-8',$_)=>1 } @{$l->{md}}; my %snapshot;
  for my $path (keys %allowed) {
    fail('受控MD路径须精确tasks/*.md') unless $path=~m{\Atasks/[^/]+\.md\z} && $path !~ /[\x00-\x1f]/;
    fail('受控MD或目录是symlink') if -l "$root/tasks" || -l "$root/$path";
    my $f=safe_open("$root/$path",O_RDONLY); my $s=do { local $/; <$f> }; my @st=stat($f); close $f;
    $snapshot{$path}=sha256_hex($s).':'.($st[2]&07777);
  }
  capture('git','-C',$root,'diff','--cached','--quiet');
  for my $entry (split /\0/,capture('git','-C',$root,'ls-files','-v','-z')) {
    fail('索引有assume-unchanged/skip-worktree，无法证明现场干净') if $entry=~/\A[a-zS] /;
  }
  for my $path (split /\0/,capture('git','-C',$root,'ls-files','--others','--ignored','--exclude-standard','-z','--','tasks/*.md')) {
    fail('被忽略的MD未精确登记，不忽略tasks') unless $allowed{$path};
  }
  my $dirty=capture('git','-C',$root,'status','--porcelain=v1','-z','--untracked-files=all');
  for my $row (split /\0/,$dirty) {
    my ($state,$path)=(substr($row,0,2),substr($row,3));
    fail('索引/产品或未登记路径dirty，拒绝land') unless ($state eq ' M' || $state eq '??') && $allowed{$path};
  }
  for my $path (split /\0/,capture('git','-C',$root,'diff','--name-only','-z',$l->{before},$l->{after},'--')) {
    fail('候选触碰受控MD相关目录，拒绝覆盖') if keys(%allowed) && ($path eq 'tasks' || $path =~ m{\Atasks/});
  }
  return $json->encode(\%snapshot);
}
sub ticket_snapshot {
  my $name=shift; fail('依赖票路径非法/歧义') unless defined($name) && $name=~/\A[A-Za-z0-9_.-]+\.md\z/;
  my $path="$parent/$name"; my $s=read_file($path);
  my $t=text($s); fail("缺少已迁真实票 $name") unless $t=~/\n<!-- qwb-collab-v1\n([^\n]+)\n-->\n?\z/;
  my $d=strict_json(encode('UTF-8',$1)); fail('依赖票schema未知') unless ref($d) eq 'HASH' && ($d->{schema} // '') eq '1';
  planning_validate($d->{planning}) if exists $d->{planning}; return $d;
}
sub durable_source {
  my ($task,$event)=@_; my $d=ticket_snapshot($task); my $h=$d->{handoffs}{$event // ''} // fail('原话没有03持久source');
  fail('source已失配') unless id_ok($event) && string_ok($h->{payload}) && $h->{payload} ne '' && grep { $_->{event_id} eq $h->{source_event} } @{$d->{events}};
  return {task=>$task,event=>$event,text=>$h->{payload}};
}
sub authorization {
  my $a=shift; keys_only($a,qw(workers permissions evidence budget));
  $a->{profiles}={};
  for my $w (@{$a->{workers} // []}) {
    fail('授权须具名工人，不用auto') unless id_ok($w) && $w ne 'auto';
    $a->{profiles}{$w}=strict_json(capture('bash','-c','. "$1"; qwb_gate_profile "$2" "$3"','plan',"$bindir/qwb-lib.sh",$root,$w));
  }
  my $s=read_file("$root/qwbuddy/workers.sh");
  $a->{workers_sha256}=sha256_hex($s); authorization_ok($a); return $a;
}
sub graph_check {
  my ($phase,$resolve)=@_; my $p=$data->{planning} // fail('未登记依赖/启动授权');
  my $name=basename($file); my %tickets=($name=>$data); my (%active,%visited); my @evidence;
  my $visit; $visit=sub {
    my $id=shift; fail("自依赖/依赖环 $id") if $active{$id}; return if $visited{$id};
    $active{$id}=1; my $d=$tickets{$id} //= ticket_snapshot($id);
    if (my $plan=$d->{planning}) {
      for my $stage (qw(start accept land)) { for my $e (@{$plan->{needs}{$stage}}) { $visit->($e->{task}) } }
    }
    delete $active{$id}; $visited{$id}=1;
  }; $visit->($name);
  return [] unless $resolve;
  for my $e (@{$p->{needs}{$phase}}) {
    my $d=$tickets{$e->{task}}; my $plan=$d->{planning} // fail("前置票未登记产物 $e->{task}");
    my $a=$plan->{artifacts}{$e->{artifact}} // fail("缺少指定产物 $e->{task}/$e->{artifact}");
    fail('旧版本产物/旧spec不能解除依赖') unless $a->{version} eq $e->{version} && $a->{spec_rev}==$e->{spec_rev} && $d->{spec_rev}==$e->{spec_rev} && !$plan->{pending_revision};
    my $s=read_file(encode('UTF-8',$a->{ref}));
    fail('产物解除证据变化') unless sha256_hex($s) eq $a->{sha256};
    if ($e->{condition} ne 'available') {
      fail('接口可用不等于accepted') unless $d->{gate} && $d->{gate}{verdict} eq 'accepted' && $d->{gate}{binding}{spec_rev}==$d->{spec_rev};
    }
    fail('尚无实际落地解除证据') if $e->{condition} eq 'landed' && (!defined($plan->{landed}) || $plan->{landed}{spec_rev}!=$d->{spec_rev});
    push @evidence,{%$e,ref=>$a->{ref},sha256=>$a->{sha256}};
  }
  return \@evidence;
}
sub accepted_history { $data->{phase} eq 'verified' || ($data->{gate} && $data->{gate}{verdict} eq 'accepted') }
sub ready_fingerprint {
  my ($p,$e)=@_; return sha256_hex($json->encode([$data->{spec_rev},$p->{needs},$e,$p->{authorization}]));
}
sub start_check {
  my $selected=shift; fail('用户专属问题未解除') if $data && grep { $_->{resumed} eq '' } values %{$data->{questions}};
  if (!$data || !$data->{planning}) {
    # 未迁旧票不会自动获得新协议；显式头部授权是一次启动授权，running/default不是证据。
    fail('首次启动无明确实施授权/预算') unless $body=~/^implementation-authorized:[ \t]*\S[^\n]*$/m && $body=~/^dispatch-budget:[ \t]*([1-9][0-9]*)[ \t]*$/m;
    my $limit=$1; my $used=()=$body=~/^dispatch:/mg; fail('启动预算已耗尽，先显式重授权') if $used >= $limit; return [];
  }
  my $p=$data->{planning}; my $a=$p->{authorization} // fail('首次启动无明确实施授权/预算');
  fail('修订尚待handoff，不启动旧规格') if $p->{pending_revision};
  fail('已验收历史不重复派工') if accepted_history();
  fail('工人/权限未授权，不可用default兜底') if defined($selected) && $selected ne 'auto' && !grep { $_ eq $selected } @{$a->{workers}};
  fail('本代规划授权已失效') if $planner_native && !$planner;
  my $s=read_file("$root/qwbuddy/workers.sh");
  fail('指定工人型号/effort配置已变化') unless sha256_hex($s) eq $a->{workers_sha256};
  my $used=grep { $_->{kind} eq 'dispatch' && $_->{spec_rev}==$data->{spec_rev} && !($data->{gate} && exists($data->{gate}{dispatches}{$_->{op_id}})) } @{$data->{events}};
  fail('启动预算已耗尽/事件已派，不重复派发') if $used >= $a->{budget};
  return graph_check('start',1);
}
sub spec_replace {
  my ($spec,$constraints,$scenarios)=@_;
  fail('工程规格格式不支持安全修订') unless $body=~/^## 工程规格\n.*?^## 必要约束\n.*?^## 验收场景/ms;
  $body=~s/^## 工程规格\n.*?^## 必要约束\n.*?(?=^## 验收场景)/"## 工程规格\n$spec\n## 必要约束\n$constraints\n"/ems;
  my $old=scenario($body); $body=~s/\Q$old\E/$scenarios/; field('scenarios-fp',scen_fp($body));
}
# Posture never grants/revokes authority. Corrupt history only refuses affected land actions.
if ($cmd =~ /\Aland-(authorize|prepare|apply|close)\z/ && (-e "$root/qwbuddy/.posture.md" || -l "$root/qwbuddy/.posture.md")) {
  capture('bash',"$bindir/qwb-ledger.sh",'mode-status','--project',$root);
}
if ($cmd eq 'land-authorize') {
  fail('明确本地主控授权参数非法') unless $controller && @args>=4 && id_ok($args[1]) && $args[2] eq 'main' && string_ok($args[3]) && $args[3] ne '';
  require_claim($args[0]);
  if (my $l=$data->{land}) {
    # 接班须先按01对账claim；新授权仅续已发生的固定本地C，不重开merge权限。
    fail('恢复授权仅限已landed同op、精确本地C、新auth_ref；不覆盖原授权') unless @args==4 && $l->{stage}=~/\A(prepared|landed)\z/ && $l->{op_id} eq $args[0] && $l->{auth_ref} ne $args[1] && land_main($l) eq $l->{after};
    fail('旧auth_ref不能重复授权') if grep { $_->{auth_ref} eq $args[1] } @{$data->{land_history} // []};
    push @{$data->{land_history}},{%$l};
    @{$l}{qw(auth_ref reason caller owner_fp)}=($args[1],$args[3],$actor,$owner_fp);
    if ($l->{stage} eq 'prepared') { $l->{stage}='landed'; $l->{landed_at}=int(time()*1000); $kind='land-apply' }
    $op=$args[0]; $line="working: land-reauthorized op_id=$op auth_ref=$l->{auth_ref} main=$l->{main} before=$l->{before} after=$l->{after} remaining-cleanup-only"; append_body($line);
  } else {
  my $c=land_ready();
  fail('旧auth_ref不能授权新候选') if grep { $_->{auth_ref} eq $args[1] } @{$data->{land_history} // []};
  my $task_id=basename($file); $task_id=~s/^[0-9][0-9-]*-//; $task_id=~s/\.md$//;
  fail('本票land只收标准独立候选目录') unless $c->{candidate} eq text("$root/.worktrees/$task_id");
  my $branch=capture('git','-C',encode('UTF-8',$c->{candidate}),'symbolic-ref','--short','HEAD');
  $data->{land}={op_id=>$args[0],auth_ref=>$args[1],reason=>$args[3],caller=>$actor,owner_fp=>$owner_fp,main=>'refs/heads/main',before=>$c->{base},after=>$c->{head},context=>$c,md=>[@args[4..$#args]],stage=>'authorized',branch=>$branch,prepared_at=>0,landed_at=>0,closed_at=>0};
  my $l=$data->{land}; fail('main旧基线；退出交隔离candidate有界整合并新验收') unless land_main($l) eq $l->{before};
  land_md_snapshot($l); $op=$args[0]; $line="working: land-authorized op_id=$op auth_ref=$l->{auth_ref} main=$l->{main} before=$l->{before} after=$l->{after}"; append_body($line);
  }
} elsif ($cmd =~ /\Aland-(prepare|apply|proof|close)\z/) {
  my $l=land_identity(); $op=$l->{op_id};
  if ($cmd eq 'land-prepare') {
    if ($l->{stage} ne 'authorized') { print "$l->{stage}\n"; exit }
    my $c=land_ready(); fail('land候选/验收条件已变') unless $json->encode($c) eq $json->encode($l->{context});
    fail('main旧基线；退出交隔离candidate有界整合并新验收') unless land_main($l) eq $l->{before};
    land_md_snapshot($l); $l->{stage}='prepared'; $l->{prepared_at}=int(time()*1000);
  } elsif ($cmd eq 'land-apply') {
    fail('须先prepared') unless $l->{stage}=~/\A(prepared|landed)\z/;
    # 重采环境/命令在main锁外；锁内只复核固定OID、工作现场、owner和执行ff。
    my $c=land_ready(); fail('land候选/验收条件已变') unless $json->encode($c) eq $json->encode($l->{context});
    my $common=capture('git','-C',$root,'rev-parse','--path-format=absolute','--git-common-dir');
    $land_guard=safe_open("$common/qwb-land-main.lock",O_RDWR|O_CREAT);
    flock($land_guard,LOCK_EX|LOCK_NB) or fail('repo+main短锁忙；保留候选，稍后同op重试'); inherit_guard($land_guard);
    my $actual=land_main($l);
    fail('main旧基线/恢复现实不明；退出锁交隔离candidate有界整合，不重merge') unless $actual eq $l->{before} || $actual eq $l->{after};
    my $md=land_md_snapshot($l);
    fail('锁内候选已变') unless capture('git','-C',encode('UTF-8',$c->{candidate}),'rev-parse','HEAD') eq $l->{after} && capture('git','-C',encode('UTF-8',$c->{candidate}),'status','--porcelain=v1','--untracked-files=all') eq '';
    my $own=safe_open("$dir/.controller.lock/owner",O_RDONLY); my $current=<$own> // ''; close $own;
    fail('锁内授权owner已变') unless $current eq $owner_raw;
    if ($actual eq $l->{before}) {
      fail('已landed不能重merge') if $l->{stage} eq 'landed';
      capture('git','-C',$root,'merge','--ff-only','--no-edit','--no-overwrite-ignore',$l->{after});
    }
    fail('main读回不是固定C') unless land_main($l) eq $l->{after};
    fail('受控MD字节/模式未保留，现实已变须对账') unless land_md_snapshot($l) eq $md;
    if ($l->{stage} eq 'landed') { print "$l->{after}\n"; exit }
    $l->{stage}='landed'; $l->{landed_at}=int(time()*1000);
    # main_guard保持到短发布结束；发布失败仍留prepared，下次只核精确本地C补记。
  } else {
    if ($cmd eq 'land-close' && $l->{stage} eq 'closed') {
      fail('已关闭收据与本地main不符') unless land_main($l) eq $l->{after}; print "$l->{after}\n"; exit;
    }
    fail('无精确本地main land收据') unless $l->{stage} eq 'landed' && land_main($l) eq $l->{after};
    if ($cmd eq 'land-proof') { print $json->encode($l),"\n"; exit }
    my $c=encode('UTF-8',$l->{context}{candidate});
    fail('收尾未完成；候选或分支还在') if -e $c || -l $c || capture('git','-C',$root,'for-each-ref','--format=%(refname)',"refs/heads/$l->{branch}") ne '';
    my $listing=capture('git','-C',$root,'worktree','list','--porcelain');
    fail('候选worktree元数据仍在') if $listing =~ /^worktree \Q$c\E$/m || $listing =~ /^branch refs\/heads\/\Q$l->{branch}\E$/m;
    my @spaces=$body=~/^worktree-space: id=(\S+) root-tab=\S+ path=[^\n]+$/mg; my $space=@spaces ? $spaces[-1] : '';
    my ($native,$rc)=native_reply('workspace','list');
    fail('收尾端点未知') if $rc || ref($native->{result}{workspaces}) ne 'ARRAY';
    for my $w (@{$native->{result}{workspaces}}) {
      fail('收尾Space身份未知') unless ref($w) eq 'HASH' && string_ok($w->{workspace_id}) && $w->{workspace_id} ne '';
      fail('本票Space仍存在，不能verified') if $space ne '' && $w->{workspace_id} eq $space;
      my $wt=$w->{worktree}; next unless ref($wt) eq 'HASH' && $wt->{is_linked_worktree};
      my $path=$wt->{checkout_path}; fail('linked Space路径未知') unless string_ok($path) && $path=~m{\A/};
      my $physical=realpath(encode('UTF-8',$path));
      if (!defined $physical) { my $parent=realpath(dirname(encode('UTF-8',$path))); $physical="$parent/".basename(encode('UTF-8',$path)) if defined $parent }
      fail('候选Space仍存在，不能verified') if defined($physical) && $physical eq $c;
    }
    fail('收尾义务/用户问题仍未结') if grep { !$_->{handled} } values %{$data->{handoffs} // {}};
    fail('收尾问题未恢复') if grep { $_->{resumed} eq '' } values %{$data->{questions}};
    $l->{stage}='closed'; $l->{closed_at}=int(time()*1000); $data->{claim}=undef; $data->{ops}{$op}{status}='released'; field('state','verified');
  }
  $line="working: $cmd op_id=$op auth_ref=$l->{auth_ref} main=$l->{main} before=$l->{before} after=$l->{after} stage=$l->{stage} tokens=unknown"; append_body($line);
} elsif ($cmd eq 'new') {
  fail('new参数非法') unless @args==1;
  my ($r)=json_file($args[0]); keys_only($r,qw(request_id package_id packages source_task source_event intent spec constraints scenarios paths needs));
  packages_ok($r->{packages}); needs_ok($r->{needs}); list_ok($r->{paths},'paths');
  fail('request/package路径不符') unless id_ok($r->{request_id}) && id_ok($r->{package_id}) && ($r->{packages}{$r->{package_id}} // '') eq basename($file);
  my $source=durable_source($r->{source_task},$r->{source_event}); my $intake=ticket_snapshot($r->{source_task});
  my $grant=$intake->{planning_authority};
  if (!$controller) {
    authority_validate($grant);
    fail('规划source/request/任务包超出主控授权') unless $planner_native && $json->encode($grant->{identity}) eq $json->encode($identity) && $grant->{request_id} eq $r->{request_id} && $grant->{source_event} eq $r->{source_event} && $json->encode($grant->{packages}) eq $json->encode($r->{packages});
    my %paths=map { $_=>1 } @{$grant->{paths}}; fail('规划文件范围扩权') if grep { !$paths{$_} } @{$r->{paths}};
  }
  my $sha=sha256_hex($json->encode($r));
  if ($data) {
    fail('request重放冲突，必须先对账') unless $data->{planning} && $data->{planning}{creation_sha256} eq $sha;
    print $json->encode($data),"\n"; exit;
  }
  fail('不覆盖既有未迁票') unless $creating;
  for my $path (glob("$parent/*.md")) {
    next if $path eq $file; my $s=read_file($path);
    next unless $s=~/\n<!-- qwb-collab-v1\n([^\n]+)\n-->\n?\z/;
    my $d=strict_json($1); next unless $d->{planning} && $d->{planning}{request_id} eq $r->{request_id};
    fail('request映射已存在且不一致，未知中断先对账') unless $json->encode($d->{planning}{packages}) eq $json->encode($r->{packages}) && $json->encode($d->{planning}{source}) eq $json->encode($source);
    fail('request/package已有不同票') if $d->{planning}{package_id} eq $r->{package_id};
  }
  my %installed;
  for my $path (map { "$bindir/qwb-$_.sh" } qw(lib run wake worktree ledger send role)) { my $s=read_file($path); $installed{$path}=sha256_hex($s) }
  $data={schema=>1,rev=>0,seq=>0,spec_rev=>0,phase=>'blocked',claim=>undef,workers=>{},questions=>{},events=>[],ops=>{},migration=>{task_sha256=>sha256_hex(''),confirm=>{map { $_=>'new ticket: no previous writers' } qw(run wake worktree worker controller old-fds external-actions)},installed=>\%installed}};
  fail('新票必须自带可验证场景') unless defined($r->{scenarios}) && scenarios_ok($r->{scenarios});
  $body="# 任务书：$r->{package_id}\nstate: blocked\n## 原始意图\n$source->{text}\n## 工程规格\n$r->{spec}\n## 必要约束\n$r->{constraints}\n$r->{scenarios}\n";
  $data->{planning}={request_id=>$r->{request_id},package_id=>$r->{package_id},packages=>$r->{packages},source=>$source,intent=>$r->{intent},spec=>$r->{spec},constraints=>$r->{constraints},paths=>$r->{paths},needs=>$r->{needs},authority=>$controller ? undef : $grant,authorization=>$controller ? undef : $grant->{authorization},creation_sha256=>$sha,artifacts=>{},ready=>{},revisions=>[],pending_revision=>undef,revision_handoff=>undef,landed=>undef};
  graph_check('start',0);
  field('scenarios-fp',scen_fp($body)); $line="working: planned request=$r->{request_id} package=$r->{package_id} source=$r->{source_event}"; append_body($line);
} elsif ($cmd eq 'plan-assign') {
  fail('仅主控授权已迁入口票') unless $controller && $data && @args==2 && !$data->{planning_authority} && ($identity->{role} // '') eq '规划' && $identity->{actor} eq $args[0];
  my ($r)=json_file($args[1]); keys_only($r,qw(request_id source_event packages paths workers permissions evidence budget));
  durable_source(basename($file),$r->{source_event});
  my $a=authorization({map { $_=>$r->{$_} } qw(workers permissions evidence budget)});
  $data->{planning_authority}={identity=>$identity,request_id=>$r->{request_id},source_event=>$r->{source_event},packages=>$r->{packages},paths=>$r->{paths},authorization=>$a}; authority_validate($data->{planning_authority});
  $line="working: planner-authorized actor=$args[0] request=$r->{request_id}"; append_body($line);
} elsif ($cmd eq 'plan-authorize') {
  fail('仅主控明确启动授权') unless $controller && @args==1;
  my ($a)=json_file($args[0]); $a=authorization($a);
  my $p=$data->{planning} // fail('先以new登记本票规划'); fail('claim在途/已验收历史不改') if $data->{claim} || accepted_history();
  $p->{authorization}=$a; $p->{ready}={}; $line="working: implementation-authorized spec_rev=$data->{spec_rev} budget=$a->{budget}"; append_body($line);
} elsif ($cmd eq 'start-check') {
  start_check($args[0]); print "ready\n"; exit;
} elsif ($cmd eq 'plan-ready') {
  my $p=$data->{planning} // fail('无规划票');
  my $e=eval { start_check() }; my $reason=$@;
  if ($reason ne '') {
    $reason=~s/[\r\n]+/ /g;
    my $fp=sha256_hex($json->encode([$data->{spec_rev},$p->{needs},$p->{authorization},$reason]));
    $pending_output=$json->encode({status=>'blocked',reason=>$reason}); $pending_exit=1;
    if (($p->{ready}{fingerprint} // '') eq $fp) { print "$pending_output\n"; exit 1 }
    $p->{ready}={fingerprint=>$fp,spec_rev=>$data->{spec_rev},status=>'blocked',reason=>$reason};
    $line="blocked: planner-not-ready spec_rev=$data->{spec_rev} reason=$reason";
  } else {
    my $fp=ready_fingerprint($p,$e);
    if (($p->{ready}{fingerprint} // '') eq $fp) { print "ready\n"; exit }
    $p->{ready}={fingerprint=>$fp,spec_rev=>$data->{spec_rev},status=>'ready',evidence=>$e};
    $line="working: planner-ready spec_rev=$data->{spec_rev} fingerprint=$fp dependencies-resolved";
  }
  append_body($line);
} elsif ($cmd eq 'plan-needs') {
  fail('依赖修订须CAS且无claim/gate；在验收中走plan-revision') if $expect eq '' || $data->{claim} || $data->{gate} || $data->{phase} eq 'verified';
  my ($n)=json_file($args[0]); needs_ok($n); my $p=$data->{planning} // fail('无规划票'); $p->{needs}=$n; graph_check('start',0); $p->{ready}={};
  $line='working: dependencies-revised'; append_body($line);
} elsif ($cmd eq 'plan-artifact') {
  fail('仅主控核可用接口证据') unless $controller && @args==1;
  my ($a)=json_file($args[0]); keys_only($a,qw(name version ref)); fail('产物名/版本非法') unless id_ok($a->{name}) && id_ok($a->{version});
  my $p=$data->{planning} // fail('无规划票'); fail('需求修订未交接，不能解除旧依赖') if $p->{pending_revision};
  my $path=realpath(encode('UTF-8',$a->{ref})) // fail('产物不存在');
  my $s=read_file(encode('UTF-8',$a->{ref}));
  fail('已核旧产物不能覆盖；修订spec后重新登记') if $p->{artifacts}{$a->{name}} && $p->{artifacts}{$a->{name}}{spec_rev}==$data->{spec_rev};
  $p->{artifacts}{$a->{name}}={version=>$a->{version},spec_rev=>$data->{spec_rev},ref=>text($path),sha256=>sha256_hex($s)};
  $line="working: artifact-available name=$a->{name} version=$a->{version} spec_rev=$data->{spec_rev} evidence=".sha256_hex($s); append_body($line);
} elsif ($cmd eq 'plan-land') {
  fail('仅主控登记真实落地，不自动执行') unless $controller && @args==1 && string_ok($args[0]) && $args[0] ne '' && $data->{gate} && $data->{gate}{verdict} eq 'accepted' && $data->{gate}{binding}{spec_rev}==$data->{spec_rev};
  my $e=graph_check('land',1); $data->{planning}{landed}={spec_rev=>$data->{spec_rev},evidence=>$args[0],dependencies=>$e}; $line="working: landed-evidence $args[0]"; append_body($line);
} elsif ($cmd eq 'plan-revision') {
  fail('修订请求必须CAS') if $expect eq ''; my $p=$data->{planning} // fail('无规划票');
  fail('已验收历史不改，新需求另开后续票') if accepted_history();
  my ($r)=json_file($args[0]); keys_only($r,qw(source_task source_event spec constraints scenarios needs)); needs_ok($r->{needs}); $r->{source}=durable_source(delete($r->{source_task}),delete($r->{source_event}));
  fail('修订request在途，先对账') if $p->{pending_revision};
  fail('新场景缺少正常/拒绝行为') unless scenarios_ok($r->{scenarios});
  $p->{pending_revision}={%$r,spec_rev=>$data->{spec_rev}}; $p->{ready}={};
  $line="working: revision-requested source=$r->{source}{event} handoff-required"; append_body($line);
} elsif ($cmd eq 'revision-handoff') {
  fail('交接需gate本人claim和待修订请求') unless $gate && @args==2 && string_ok($args[1]) && $args[1] ne '' && $data->{planning}{pending_revision}; require_claim($args[0]);
  for my $child (keys %{$data->{gate}{dispatches}}) {
    fail('gate子任务在途，不能交出验收标准') if child_in_flight($child);
  }
  $data->{planning}{revision_handoff}={spec_rev=>$data->{spec_rev},op_id=>$args[0],owner=>$actor,reason=>$args[1]};
  $data->{claim}=undef; $data->{ops}{$args[0]}{status}='released'; $line="working: revision-handoff op=$args[0] $args[1]"; append_body($line);
} elsif ($cmd eq 'test-request') {
  fail('请求参数非法') unless @args==5 && id_ok($args[1]); require_claim($args[0]);
  my ($idop,$id,$recipient,$reason,$scenario)=@args; my $c=gate_context();
  fail('只有版本化策略的真实缺口/新行为/复杂失败/技术重诊才请求') unless exists($c->{test_policy_sha256}) && $reason=~/\A(new-behavior|policy-gap|complex-failure|rediagnose)\z/;
  fail('重诊须同因三轮停止线') if $reason eq 'rediagnose' && $data->{gate}{verdict} ne 'rediagnose';
  fail('场景不在原票') unless grep { $_ eq $scenario } map { @$_ } values %{$c->{required}};
  my $ti=strict_json($test_identity_raw);
  fail('测试负责人身份/代次未知') unless ($ti->{actor} // '') eq $recipient && $ti->{owner_fp} eq $owner_fp;
  $data->{test_requests} //= {};
  if (my $old=$data->{test_requests}{$id}) {
    fail('请求重放内容/spec冲突') unless $old->{reason} eq $reason && $old->{scenario} eq $scenario && $json->encode($old->{identity}) eq $json->encode($ti) && $json->encode($old->{context}) eq $json->encode($c);
    print "$old->{event_id}\n"; exit;
  }
  fail('同spec已有一次有效咨询；不逐票重复回签') if grep { $_->{context}{spec_sha256} eq $c->{spec_sha256} } values %{$data->{test_requests}};
  $event='test-request:'.sha256_hex(encode('UTF-8',$id));
  $data->{test_requests}{$id}={event_id=>$event,identity=>$ti,reason=>$reason,scenario=>$scenario,context=>$c,reply=>{},reply_sha256=>''};
  $data->{gate}{verdict}='pending';
  $line="working: test-request id=$id actor=$recipient reason=$reason scenario=$scenario spec=$c->{spec_rev} policy=$c->{policy}"; append_body($line);
} elsif ($cmd eq 'test-reply') {
  fail('reply参数非法/非测试负责人') unless @args==2 && $test;
  my $request=$data->{test_requests}{$args[0]} // fail('请求不存在');
  fail('不是请求绑定的本代测试负责人') unless $json->encode($request->{identity}) eq $json->encode($identity);
  my ($reply,$sha)=json_file($args[1]); keys_only($reply,qw(task request_id context validation tests));
  my $c=gate_context();
  fail('回复不匹配原票/spec/对象/策略') unless $reply->{task} eq text($file) && $reply->{request_id} eq $args[0] && $json->encode($reply->{context}) eq $json->encode($request->{context}) && $json->encode($reply->{context}) eq $json->encode($c);
  fail('只能给最小验证/受限补测建议') unless ref($reply->{validation}) eq 'ARRAY' && @{$reply->{validation}} && ref($reply->{tests}) eq 'ARRAY' && !grep { !string_ok($_) || $_ eq '' } (@{$reply->{validation}},@{$reply->{tests}});
  my $h=$data->{handoffs}{source_id($request->{event_id})} // fail('先读03持久请求');
  fail('先通过03接手并prepared，不能替作者自证') unless $h->{accepted} eq $actor && $h->{prepared} && $h->{owner_fp} eq $owner_fp;
  if ($request->{reply_sha256} ne '') {
    fail('有效reply不可覆盖') unless $json->encode($request->{reply}) eq $json->encode($reply);
    print "$request->{reply_sha256}\n"; exit;
  }
  $request->{reply}=$reply; $request->{reply_sha256}=$sha;
  $line="working: test-reply id=$args[0] spec=$c->{spec_rev} policy=$c->{policy} advice-only author-writes-tests gate-assesses tokens=unknown"; append_body($line);
} elsif ($cmd eq 'gate-context' || $cmd eq 'gate-diff') {
  require_claim($args[0]);
  fail('context参数非法') if $cmd eq 'gate-context' && (@args>2 || (@args==2 && $args[1] ne 'observe'));
  my $c=gate_context($cmd eq 'gate-context' && ($args[1] // '') eq 'observe');
  if ($cmd eq 'gate-diff') {
    my $reviewed=$args[1] // '';
    if (@{$data->{gate}{reviews}}) {
      my $previous=$data->{gate}{reviews}[-1]{review}{context}{head};
      fail('上轮reviewed head与原收据不符') if $reviewed ne '' && $reviewed ne $previous;
      $reviewed=$previous;
    }
    fail('上轮reviewed head必须精确OID') unless $reviewed eq '' || $reviewed=~/\A[0-9a-f]{40,64}\z/;
    my %contexts;
    for my $path (@args[2..$#args]) {
      fail('上下文路径非法') unless string_ok($path) && $path !~ m{\A/|(?:\A|/)\.\.(?:/|\z)};
      $contexts{$path}=text(capture('git','-C',encode('UTF-8',$c->{candidate}),'show',"$c->{head}:$path"));
    }
    $c->{reviewed_head}=$reviewed;
    $c->{diff}=text(capture('git','-C',encode('UTF-8',$c->{candidate}),'diff',$c->{base},$c->{head},'--'));
    $c->{reviewed_diff}=$reviewed eq '' ? '' : text(capture('git','-C',encode('UTF-8',$c->{candidate}),'diff',$reviewed,$c->{head},'--'));
    $c->{contexts}=\%contexts;
  }
  print $json->encode($c),"\n"; exit;
} elsif ($cmd eq 'gate-reuse') {
  fail('reuse参数非法') unless @args==2 && $args[1]=~/\A(fast|full)\z/;
  require_claim($args[0]); my $c=gate_context();
  fail('旧票未显式引用版本化test-policy，不改变既有执行行为') unless exists $c->{test_policy_sha256};
  my @r=reusable_receipts($c,$args[1]);
  fail('无同对象/条件可信成功收据') unless @r;
  print $json->encode({reused=>1,sha256=>$r[-1]{sha256},ref=>$r[-1]{ref},gate=>$args[1],elapsed_seconds=>$r[-1]{receipt}{elapsed_seconds},tokens=>'unknown',basis=>$c}),"\n"; exit;
} elsif ($cmd eq 'ci-assign') {
  fail('CI授权仅现主控+已迁原票') unless $controller && $data && @args==2 && $identity->{actor} eq $args[0];
  my $s=strict_json(ci_bytes($args[1])); ci_source_ok($s);
  my $c=gate_context();
  fail('CI来源不是当前clean候选/命令/环境') unless $c->{status} eq 'clean' && $s->{source_head_sha} eq $c->{head} && $s->{candidate_attempt} eq $c->{attempt} && exists($c->{commands}{$s->{gate}}) && $s->{command_sha256} eq $c->{commands}{$s->{gate}} && $s->{environment_sha256} eq $c->{environment_sha256};
  fail('CI限定日志摘要损坏') unless sha256_hex(ci_bytes($s->{log_ref})) eq $s->{log_sha256};
  my $key=ci_key($s); $data->{ci} //= {requests=>{},reports=>{}};
  my $q={identity=>$identity,source=>$s,context=>$c};
  if (my $old=$data->{ci}{requests}{$key}) {
    fail('CI同来源授权冲突') unless $json->encode($old) eq $json->encode($q);
    print "$key\n"; exit;
  }
  $data->{ci}{requests}{$key}=$q; $data->{gate}{verdict}='pending';
  $pending_output=$key; $line="working: ci-request corr=$key source_run_id=$s->{source_run_id} attempt=$s->{attempt} head=$s->{source_head_sha} log_sha256=$s->{log_sha256} tokens=unknown"; append_body($line);
} elsif ($cmd eq 'ci-report') {
  fail('CI报告仅登记本人（主控不得冒充）') unless $ci_actor && @args==1;
  my $raw_report=ci_bytes($args[0]); my $r=strict_json($raw_report); my $key=ci_key($r);
  my $q=$data->{ci}{requests}{$key} // fail('CI报告缺授权来源'); ci_report_ok($r,$q->{source});
  fail('CI报告角色/代次越权') unless $json->encode($identity) eq $json->encode($q->{identity});
  my $c=gate_context(); fail('CI报告已过期/对象条件改变，仅可参考不能导入验收') unless $c->{status} eq 'clean' && $json->encode($c) eq $json->encode($q->{context});
  fail('CI授权日志被改写') unless sha256_hex(ci_bytes($q->{source}{log_ref})) eq $q->{source}{log_sha256};
  if (my $old=$data->{ci}{reports}{$key}) {
    fail('CI同S/A/C报告冲突') unless $json->encode($old->{report}) eq $json->encode($r);
    print "$old->{event_id}\n"; exit;
  }
  $event='send:'.sha256_hex(encode('UTF-8',"$key\0$r->{attempt}"));
  $data->{ci}{reports}{$key}={report=>$r,sha256=>sha256_hex($raw_report),ref=>$args[0],event_id=>$event};
  $handoff_return=[$key,$r->{attempt},text($json->encode($r))];
  $line="working: ci-proposal corr=$key source_run_id=$r->{source_run_id} attempt=$r->{attempt} head=$r->{source_head_sha} classification=$r->{classification} report=$args[0] tokens=$r->{tokens} proposal-only"; append_body($line);
} elsif ($cmd eq 'gate-receipt') {
  fail('receipt参数非法') unless @args==2; require_claim($args[0]);
  my ($r,$sha)=json_file($args[1]); keys_only($r,qw(schema before after gate command_sha256 rc started_at ended_at elapsed_seconds executor));
  my $c=gate_context();
  my $resolved=realpath(encode('UTF-8',$args[1])) // fail('报告不存在');
  fail('报告必须在候选之外') if $resolved eq encode('UTF-8',$c->{candidate}) || index($resolved,encode('UTF-8',$c->{candidate}).'/')==0;
  fail('收据对象/规格/策略/命令/配置/环境不匹配') unless $r->{schema} eq 'qwb-candidate-receipt-v1' && $json->encode($r->{before}) eq $json->encode($c) && $json->encode($r->{after}) eq $json->encode($c) && exists($c->{commands}{$r->{gate}}) && $r->{command_sha256} eq $c->{commands}{$r->{gate}} && $r->{executor} eq $actor && $r->{rc}=~/\A[0-9]+\z/ && $r->{elapsed_seconds}>=0;
  fail('dirty候选不能记可信收据') unless $c->{status} eq 'clean';
  fail('收据执行时间非法') unless receipt_interval_ok($r);
  # 同一执行内容重复导入幂等；路径/排版不构成新执行，不改历史、verdict或事件顺序。
  for my $old (@{$data->{gate}{receipts}}) {
    if ($json->encode($old->{receipt}) eq $json->encode($r)) { print "$old->{sha256}\n"; exit }
  }
  # 复制精确结果到同票协议；外部报告可读回，后续改写不改变已登记收据。
  push @{$data->{gate}{receipts}},{receipt=>$r,sha256=>$sha,ref=>text($resolved)};
  $data->{gate}{verdict}='pending';
  $line="working: gate-receipt attempt=$c->{attempt} head=$c->{head} gate=$r->{gate} rc=$r->{rc} elapsed=$r->{elapsed_seconds} tokens=unknown"; append_body($line);
} elsif ($cmd eq 'gate-review') {
  fail('review参数非法') unless @args==2; require_claim($args[0]);
  my ($r,$sha)=json_file($args[1]); keys_only($r,qw(context implementer reviewer standards spec covered findings), exists($r->{authorization}) ? 'authorization' : ());
  my $c=gate_context();
  fail('审核不是当前精确对象') unless $c->{status} eq 'clean' && $json->encode($r->{context}) eq $json->encode($c);
  for my $kind (qw(implementer reviewer)) {
    my $id=$r->{$kind}; keys_only($id,qw(model family session evidence));
    fail('审核身份unknown/字段不全') if grep { !string_ok($_) || $_ eq '' || lc($_) eq 'unknown' } values %$id;
    my $fh=safe_open(encode('UTF-8',$id->{evidence}),O_RDONLY); my @records;
    while (my $s=<$fh>) { push @records,strict_json($s) } close $fh;
    my $profile=$c->{worker_profiles}{$kind eq 'reviewer' ? 'review' : 'rework'};
    fail('审核/实现型号不是主控准确授权配置') unless $id->{model} eq $profile->{model};
    my $header=$records[0]; my @models=grep { ($_->{type} // '') eq 'model_change' } @records;
    my @efforts=grep { ($_->{type} // '') eq 'thinking_level_change' } @records;
    fail('原生session/model证据不匹配（当前仅Pi JSONL）') unless $header && $header->{type} eq 'session' && $header->{id} eq $id->{session} && @models && $models[-1]{modelId} eq $id->{model} && $models[-1]{provider} eq $profile->{provider} && @efforts && $efforts[-1]{thinkingLevel} eq $profile->{effort};
    fail('会话目录不是候选/本项目') unless ($header->{cwd} // '') eq $c->{candidate} || ($header->{cwd} // '') eq $c->{project};
    # 仅本切片已知固定原生provider/model；不从昵称、CLI或model前缀猜family。
    my %known_family=('openai-codex/gpt-6.1-sol'=>'gpt','openai-codex/gpt-6-astra'=>'gpt','anthropic/claude-opus-4-6'=>'claude');
    my $family=$known_family{"$models[-1]{provider}/$models[-1]{modelId}"} // 'unknown';
    fail('原生模型family未可靠确认') unless $family ne 'unknown' && $id->{family} eq $family;
    $id->{evidence_sha256}=sha256_hex(join('',map { $json->encode($_) } @records));
  }
  fail('同原生会话审核冲突；保留现有身份门') if $r->{implementer}{session} eq $r->{reviewer}{session} || $r->{reviewer}{session} eq $data->{gate}{identity}{session_id};
  my $authorized=0;
  if (exists $r->{authorization}) {
    fail('审核授权key非法') unless id_ok($r->{authorization});
    my $q=$data->{questions}{$r->{authorization}} // fail('审核无本票用户授权');
    fail('审核批准尚未答复/恢复') unless $q->{answer} ne '' && $q->{resumed} ne '';
    my $a=strict_json(encode('UTF-8',$q->{answer}));
    keys_only($a,qw(schema context implementer_session reviewer_session owner_fp approval));
    fail('审核批准范围/对象/身份不匹配') unless $a->{schema} eq 'qwb-sol-astra-review-v1' && $json->encode($a->{context}) eq $json->encode($c) && $a->{implementer_session} eq $r->{implementer}{session} && $a->{reviewer_session} eq $r->{reviewer}{session} && $a->{owner_fp} eq $owner_fp && string_ok($a->{approval}) && $a->{approval} ne '' && $r->{implementer}{model} eq 'gpt-6.1-sol' && $r->{reviewer}{model} eq 'gpt-6-astra';
    $authorized=1;
  }
  fail('同family审核冲突；保留现有身份门') if $r->{implementer}{family} eq $r->{reviewer}{family} && !$authorized;
  fail('审核两轴/场景/意见非法') unless $r->{standards}=~/\A(pass|fail)\z/ && $r->{spec}=~/\A(pass|fail)\z/ && ref($r->{covered}) eq 'ARRAY' && ref($r->{findings}) eq 'ARRAY';
  my %seen;
  for my $f (@{$r->{findings}}) {
    keys_only($f,qw(id original classification root evidence));
    fail('finding字段/分类非法') unless id_ok($f->{id}) && !$seen{$f->{id}}++ && id_ok($f->{root}) && string_ok($f->{original}) && $f->{original} ne '' && string_ok($f->{evidence}) && $f->{evidence} ne '' && $f->{classification}=~/\A(must-fix|suggestion|not-founded|unresolved)\z/;
    my $old=$data->{gate}{findings}{$f->{id}};
    fail('不能覆盖原意见/根因') if $old && ($old->{original} ne $f->{original} || $old->{root} ne $f->{root});
    fail('成立缺陷/安全未决不能降成偏好；须修复复核或附反证') if $old && $old->{history}[-1]{classification}=~/\A(must-fix|unresolved)\z/ && $f->{classification} eq 'suggestion';
    $old //= $data->{gate}{findings}{$f->{id}}={original=>$f->{original},root=>$f->{root},history=>[]};
    push @{$old->{history}},{classification=>$f->{classification},evidence=>$f->{evidence},attempt=>$c->{attempt},head=>$c->{head},review_sha256=>$sha};
  }
  push @{$data->{gate}{reviews}},{review=>$r,sha256=>$sha,at=>$now}; $data->{gate}{verdict}='pending';
  $line="working: gate-review attempt=$c->{attempt} head=$c->{head} standards=$r->{standards} spec=$r->{spec} evidence_sha256=$sha"; append_body($line);
} elsif ($cmd eq 'gate-verdict') {
  my ($id,$verdict,$rootcause,$evidence)=@args; require_claim($id);
  fail('verdict非法') unless $verdict=~/\A(accepted|rework)\z/;
  my $g=$data->{gate}; my $c=gate_context();
  if ($verdict eq 'accepted') {
    fail('accepted参数非法') unless @args==2;
    $data->{planning}{ready}{accept_evidence}=graph_check('accept',1) if $data->{planning};
    fail('修订未交接，不接受旧规格') if $data->{planning} && $data->{planning}{pending_revision};
    for my $r (values %{$data->{test_requests} // {}}) {
      my $h=$data->{handoffs}{source_id($r->{event_id})};
      fail('已请求的测试补充尚未回复/读回交接；不是每票额外回签') unless $r->{reply_sha256} ne '' && $h && $h->{handled};
    }
    my $ci=$data->{ci} // {requests=>{},reports=>{}};
    for my $key (keys %{$ci->{requests}}) {
      my $q=$ci->{requests}{$key}; next unless $json->encode($q->{context}) eq $json->encode($c);
      my $r=$ci->{reports}{$key};
      fail('当前CI诊断缺证或未办理；提案不是成功收据') unless $r && $data->{handoffs}{$r->{event_id}}{handled};
    }
    fail('dirty或无独立审核') unless $c->{status} eq 'clean' && @{$g->{reviews}};
    for my $id (keys %{$g->{dispatches}}) {
      fail('派出的审核/返修仍在途，不能ready') if child_in_flight($id);
    }
    my $r=$g->{reviews}[-1]{review};
    fail('缺当前两轴通过审核') unless $json->encode($r->{context}) eq $json->encode($c) && $r->{standards} eq 'pass' && $r->{spec} eq 'pass';
    my %covered=map { $_=>1 } @{$r->{covered}};
    for my $name (keys %{$c->{required}}) {
      fail("关键场景未覆盖: $name") if grep { !$covered{$_} } @{$c->{required}{$name}};
      my @matching=grep { $_->{receipt}{gate} eq $name && $json->encode($_->{receipt}{after}) eq $json->encode($c) } @{$g->{receipts}};
      fail("同对象收据执行时间不明: $name") if grep { !receipt_interval_ok($_->{receipt}) } @matching;
      my @failed=grep { $_->{receipt}{rc}!=0 } @matching;
      # 导入顺序不是执行顺序。秒级并列/重叠保守拒绝，须明确晚于所有失败的新成功。
      my @successful=grep {
        my $r=$_->{receipt};
        $r->{rc}==0 && !grep { $r->{started_at}<=$_->{receipt}{ended_at} } @failed
      } @matching;
      fail("无同对象/条件明确晚于所有失败的可信成功收据: $name") unless @successful;
    }
    for my $f (values %{$g->{findings}}) { fail('成立缺陷/安全意见未决') if $f->{history}[-1]{classification}=~/\A(must-fix|unresolved)\z/ }
    for my $q (values %{$data->{questions}}) { fail('用户专属问题尚未恢复') unless $q->{resumed} ne '' }
    my $spev=last_spec_event($body);
    fail('规格疑点未决') if $spev =~ /^blocked:/;
    # accepted只记verdict，保留claim/待land/cleanup，不扩五值state。
  } else {
    fail('返修需当前对象独立复核') unless @{$g->{reviews}} && $json->encode($g->{reviews}[-1]{review}{context}) eq $json->encode($c);
    fail('原范围返修需要成立意见/根因/证据') unless @args==4 && id_ok($rootcause) && string_ok($evidence) && $evidence ne '' && grep { $_->{root} eq $rootcause && $_->{history}[-1]{classification} eq 'must-fix' } values %{$g->{findings}};
    my @proof=sort map { $_->{history}[-1]{evidence} } grep { $_->{root} eq $rootcause } values %{$g->{findings}};
    my $evidence_sha=sha256_hex($json->encode([$evidence,@proof]));
    if (@{$g->{rounds}} && $g->{rounds}[-1]{attempt} eq $c->{attempt}) {
      fail('同attempt返修结论冲突；新轮须新attempt') unless $g->{rounds}[-1]{root} eq $rootcause && $g->{rounds}[-1]{evidence_sha256} eq $evidence_sha;
      if ($g->{verdict}=~/\A(rework|rediagnose)\z/) { print "$g->{verdict}\n"; exit }
    } else {
      push @{$g->{rounds}},{root=>$rootcause,evidence_sha256=>$evidence_sha,attempt=>$c->{attempt},at=>$now};
    }
    my @r=@{$g->{rounds}};
    $verdict='rediagnose' if @r>=3 && $r[-1]{root} eq $r[-2]{root} && $r[-1]{root} eq $r[-3]{root} && $r[-1]{evidence_sha256} eq $r[-2]{evidence_sha256} && $r[-1]{evidence_sha256} eq $r[-3]{evidence_sha256};
  }
  $g->{verdict}=$verdict;
  $line="working: gate-verdict verdict=$verdict attempt=$c->{attempt} head=$c->{head} tokens=unknown";
  $line.=' technical-owner=controller no-user-question' if $verdict eq 'rediagnose'; append_body($line);
} elsif ($cmd eq 'gate-candidate') {
  my $integration=@args==5 && $args[4] eq 'integration';
  fail('candidate参数非法') unless @args==4 || $integration; require_claim($args[0]);
  my ($id,$attempt,$candidate,$base)=@args; my $g=$data->{gate};
  if ($integration) {
    my $l=$data->{land} // fail('集成更新须有被旧M挡住的land授权');
    fail('仅主控在旧M拒绝后登记原副本集成；不在main上merge/rebase') unless $controller && $l->{op_id} eq $id && $l->{stage}=~/\A(authorized|prepared)\z/ && $l->{caller} eq $actor && $l->{owner_fp} eq $owner_fp && land_main($l) ne $l->{before} && $base eq land_main($l);
    push @{$data->{land_history}},$l; delete $data->{land};
  }
  fail('只能提交合规新attempt/base') unless id_ok($attempt) && $attempt ne $g->{binding}{attempt} && ($integration || $g->{verdict} eq 'rework' && $base eq $g->{binding}{base});
  fail('不能切到未授权副本') unless $candidate eq $g->{binding}{candidate};
  for my $id (grep { $g->{dispatches}{$_} eq 'rework' } keys %{$g->{dispatches}}) {
    fail('返修工人尚未交回，不能切candidate') if child_in_flight($id);
  }
  $g->{binding}{attempt}=$attempt; $g->{binding}{base}=$base;
  $g->{binding}{head}=capture('git','-C',encode('UTF-8',$candidate),'rev-parse','HEAD');
  $g->{binding}{tree}=capture('git','-C',encode('UTF-8',$candidate),'rev-parse','HEAD^{tree}');
  $g->{verdict}='pending';
  my $c=gate_context(); fail('新候选dirty') unless $c->{status} eq 'clean';
  $line="working: gate-candidate attempt=$attempt head=$c->{head} previous-evidence-retained"; append_body($line);
} elsif ($cmd eq 'gate-dispatch') {
  fail('dispatch参数非法') unless @args==4; require_claim($args[0]);
  my ($claim,$child,$purpose,$workername)=@args; my $g=$data->{gate};
  fail('不在主控授权工人配置内') unless ($g->{binding}{workers}{$purpose} // '') eq $workername;
  fail('只能派独立review或原范围rework') unless $purpose=~/\A(review|rework)\z/ && id_ok($child) && !exists($data->{ops}{$child}) && !grep { $_->{op_id} eq $child } values %{$data->{handoffs} // {}};
  fail('返修无成立意见或已触发技术重诊') if $purpose eq 'rework' && $g->{verdict} ne 'rework';
  fail('已有同类在途派工') if grep {
    my $id=$_;
    $g->{dispatches}{$id} eq $purpose && child_in_flight($id)
  } keys %{$g->{dispatches}};
  $g->{dispatches}{$child}=$purpose; $data->{ops}{$child}={owner=>$actor,pane=>'',status=>'claimed'};
  $op=$child; $line="working: gate-dispatch purpose=$purpose acceptance-op=$claim child=$child original-scope"; append_body($line);
} elsif ($cmd eq 'gate-assign') {
  fail('授权仅现主控且票必须已迁/无在途claim') unless $controller && $data && !$data->{claim};
  fail('门禁身份未证实或已授权（不覆盖历史）') unless @args==2 && $identity->{actor} eq $args[0] && !$data->{gate};
  my $s=read_file(encode('UTF-8',$args[1]));
  my $b=strict_json($s); keys_only($b,qw(candidate base attempt policy environment required workers));
  keys_only($b->{workers},qw(review rework));
  fail('工人授权须显式配置名，不用auto') if grep { !id_ok($_) || $_ eq 'auto' } values %{$b->{workers}};
  fail('候选/attempt/policy/环境非法') unless id_ok($b->{attempt}) && id_ok($b->{policy}) && string_ok($b->{candidate}) && string_ok($b->{environment}) && $b->{base}=~/\A[0-9a-f]{40,64}\z/ && ref($b->{required}) eq 'HASH' && keys(%{$b->{required}});
  my $scenarios=scenario($body);
  my @scenarios=$scenarios =~ /^###\s+(user_[^\s]+)\s*$/mg;
  fail('需要冻结的命名场景') unless @scenarios;
  my %covered;
  for my $g (keys %{$b->{required}}) {
    fail('门/场景映射非法') unless $g=~/\A(fast|full)\z/ && ref($b->{required}{$g}) eq 'ARRAY' && @{$b->{required}{$g}};
    for my $s (@{$b->{required}{$g}}) { fail('范围外场景') unless grep { $_ eq $s } @scenarios; $covered{$s}=1 }
  }
  fail('关键场景缺失或降低full策略') unless exists($b->{required}{full}) && !grep { !$covered{$_} } @scenarios;
  $b->{candidate}=text(realpath(encode('UTF-8',$b->{candidate})) // fail('候选不存在'));
  $b->{environment}=text(realpath(encode('UTF-8',$b->{environment})) // fail('环境证据不存在'));
  $b->{spec_rev}=$data->{spec_rev}; $b->{scenarios_fp}=scen_fp($body);
  # 绑定规格正文，不绑定会不断增长的运行时账本正文。
  my $spec=spec_body($body);
  $b->{spec_sha256}=sha256_hex(encode('UTF-8',$spec));
  my @policy_refs=$body=~/^test-policy:[ \t]*(\S+)[ \t]*$/mg;
  if (@policy_refs) {
    fail('票策略版本不唯一/与授权不符') unless @policy_refs==1 && $policy_refs[0] eq $b->{policy};
    $b->{test_policy_sha256}=test_policy($b->{policy});
    my @risks=$body=~/^risk:[ \t]*(\S+)[ \t]*$/mg;
    fail('策略票须唯一normal/high风险') unless @risks==1 && $risks[0]=~/\A(normal|high)\z/;
  }
  my $worker_config=read_file("$root/qwbuddy/workers.sh");
  $b->{workers_sha256}=sha256_hex($worker_config);
  $b->{worker_profiles}={};
  for my $purpose (qw(review rework)) {
    $b->{worker_profiles}{$purpose}=strict_json(capture('bash','-c','. "$1"; qwb_gate_profile "$2" "$3"','gate',"$bindir/qwb-lib.sh",$root,$b->{workers}{$purpose}));
  }
  $b->{head}=capture('git','-C',encode('UTF-8',$b->{candidate}),'rev-parse','HEAD');
  $b->{tree}=capture('git','-C',encode('UTF-8',$b->{candidate}),'rev-parse','HEAD^{tree}');
  $data->{gate}={identity=>$identity,binding=>$b,receipts=>[],reviews=>[],findings=>{},verdict=>'pending',rounds=>[],dispatches=>{}};
  my $c=gate_context(); fail('授权候选必须clean') unless $c->{status} eq 'clean';
  $line="working: gate-authorized actor=$identity->{actor} candidate=$b->{candidate} attempt=$b->{attempt}"; append_body($line);
} elsif ($cmd =~ /\Ahandoff-/) {
  fail('交接仅支持已迁票') unless $data;
  $data->{handoffs} //= {};
  if ($handoff_watch) {
    fail('交接目标不是现主控') unless ($args[0] // '') eq $owner;
  }
  if ($cmd eq 'handoff-pending') {
    my ($target,$retry,$mode)=@args;
    fail('pending参数非法') unless @args==3 && $retry=~/\A[1-9][0-9]*\z/ && $retry<=86400000 && $mode=~/\A(all|due)\z/;
    # 接班扫描完整事件序列，不沿用旧wake指纹或有空洞的最后seq游标。
    my $added=0;
    for my $e (@{$data->{events}}) {
      # 真实状态正文包括answer/resume、失败补偿与恢复/规格处置；排除自身收据，避免通知自激。
      next unless $e->{kind} eq 'migrate' || ($e->{kind} !~ /\A(?:handoff-|ci-|gate-(?!verdict))/ && $e->{line}=~/\A(working|done|blocked|needs-decision):/);
      my $id=source_id($e->{event_id});
      next if exists $data->{handoffs}{$id};
      my $payload=$e->{kind} eq 'migrate' ? "接班核查迁入前正文与旧义务；state=$data->{phase}" : $e->{line};
      $data->{handoffs}{$id}=new_handoff($id,$id,'1',$e,$payload); $added++;
    }
    my @p=map { +{%$_,due=>handoff_due($_,$retry) ? 1 : 0,reconcile=>$_->{prepared} && !$_->{handled} ? 1 : 0} }
      sort { $a->{source_seq}<=>$b->{source_seq} } grep { !$_->{handled} && ($mode eq 'all' || handoff_due($_,$retry)) } values %{$data->{handoffs}};
    $pending_output=$json->encode(\@p);
    if (!$added) { print "$pending_output\n"; exit }
  } elsif ($cmd eq 'handoff-send') {
    my ($to,$corr,$attempt,$payload)=@args;
    fail('收件人/corr/attempt/正文非法') unless @args==4 && $to eq 'controller' && id_ok($corr) && id_ok($attempt) && string_ok($payload) && $payload ne '' && length(encode('UTF-8',$payload))<=65536;
    fail('corr的source:前缀保留给自动来源') if $corr =~ /\Asource:/;
    if ($worker && !$controller) { fail('失败派发工人不能投递') if $data->{ops}{$data->{workers}{$actor}}{status} eq 'not-sent' }
    my ($old)=grep { $_->{corr} eq $corr && $_->{attempt} eq $attempt } values %{$data->{handoffs}};
    if ($old) {
      fail('corr重投内容或来源冲突') unless $old->{payload} eq $payload && $old->{source_actor} eq $actor;
      print "$old->{event_id}\n"; exit;
    }
    $event='send:'.sha256_hex(encode('UTF-8',"$corr\0$attempt"));
    $line="working: handoff corr=$corr attempt=$attempt recipient=controller";
    $handoff_return=[$corr,$attempt,$payload];
  } else {
    my $id=$cmd eq 'handoff-transport' ? $args[1] : $args[0];
    my $h=$data->{handoffs}{$id // ''} // fail('handoff event不存在');
    if ($cmd eq 'handoff-transport') {
      fail('transport参数非法') unless @args==2;
      # prepared先于传输；传输是否成功未知也不消费待办，有界重投同一event。
      if ($h->{transport_count}>=3) { print "$id\n"; exit }
      $h->{transport_count}++; $h->{transport_at}=$now;
    } else {
      if ($test) {
        my ($request)=grep { source_id($_->{event_id}) eq $id && $json->encode($_->{identity}) eq $json->encode($identity) } values %{$data->{test_requests}};
        fail('测试只能消费本人绑定request') unless $request;
        fail('回复未持久读回，不能handled') if $cmd eq 'handoff-handled' && $request->{reply_sha256} eq '';
      }
      fail('仅当前收件人能确认') unless $controller || $gate || $test || $planner;
      require_claim($data->{claim}{op_id}) if $gate;
      if ($cmd eq 'handoff-received') {
        fail('received参数非法') unless @args==1;
        if ($h->{received} eq $actor) { print "$id\n"; exit }
        $h->{received}=$actor;
      } elsif ($cmd eq 'handoff-accept') {
        my $idop=$args[1]; fail('accept必须先received且op_id合法') unless @args==2 && $h->{received} eq $actor && id_ok($idop);
        if ($h->{accepted} ne '') {
          fail('claim已存在，须先对账接班') unless $h->{accepted} eq $actor && $h->{owner_fp} eq $owner_fp && $h->{op_id} eq $idop;
          print "$id\n"; exit;
        }
        fail('op_id已用于另一动作') if exists($data->{ops}{$idop}) || grep { $_->{op_id} eq $idop } values %{$data->{handoffs}};
        $h->{accepted}=$actor; $h->{owner_fp}=$owner_fp; $h->{op_id}=$idop; $h->{activity_at}=$now;
      } elsif ($cmd eq 'handoff-reconcile') {
        fail('接班必须持版本和原claim') unless @args==2 && $expect ne '' && $h->{accepted} ne '' && !$h->{handled};
        my $proof=read_file(encode('UTF-8',$args[1]));
        my $p=strict_json($proof); keys_only($p,qw(task_sha256 op_id previous_owner reconciled));
        fail('接班快照/claim/对账证据不一致') unless $p->{task_sha256} eq sha256_hex($raw) && $p->{op_id} eq $h->{op_id} && $p->{previous_owner} eq $h->{accepted} && string_ok($p->{reconciled}) && $p->{reconciled} ne '';
        my $old=$h->{accepted};
        fail('同pane新代际无法证明旧claim owner死亡，保留待办') if $old eq $actor && $h->{owner_fp} ne $owner_fp;
        if ($old ne $actor) {
          if ($old =~ /\Apid:([1-9][0-9]*)\z/) { fail('旧claim owner仍活或未知') unless !kill(0,$1) && $! == ESRCH }
          else { my ($j,$rc)=native_reply('pane','get',$old); fail('旧claim owner仍活或未知') unless $rc && ($j->{error}{code} // '') eq 'pane_not_found' }
        }
        $h->{accepted}=$actor; $h->{received}=$actor; $h->{owner_fp}=$owner_fp; $h->{activity_at}=$now;
        $h->{wait_until}=0; $h->{wait_reason}='';
        # op/prepared保持原值；先读回结果，绝不因为重启而重放副作用。
      } else {
        fail('无本代accepted claim；接班先对账') unless $h->{accepted} eq $actor && $h->{owner_fp} eq $owner_fp;
        if ($cmd eq 'handoff-activity') {
          my ($id0,$wait,$reason)=@args;
          fail('activity/wait非法') unless @args==3 && $wait=~/\A[0-9]+\z/ && $wait<=86400000 && string_ok($reason) && ($wait==0 || $reason ne '');
          fail('handled不能续claim') if $h->{handled};
          $h->{activity_at}=$now; $h->{wait_until}=$wait ? $now+$wait : 0; $h->{wait_reason}=$reason;
        } elsif ($cmd eq 'handoff-prepared') {
          fail('prepared op不一致') unless @args==2 && $args[1] eq $h->{op_id};
          if ($h->{prepared}) { print "$id\n"; exit }
          $h->{prepared}=1;
        } elsif ($cmd eq 'handoff-handled') {
          fail('handled必须先prepared且op一致') unless @args==3 && $h->{prepared} && $args[1] eq $h->{op_id};
          my $ref=encode('UTF-8',$args[2]); $ref="$root/$ref" unless $ref=~m{^/};
          my $resolved=realpath($ref) // fail('result_ref不存在');
          fail('result_ref越项目或符号链接') unless index($resolved,"$root/")==0 && !-l $ref;
          my $proof=read_file($ref);
          my $p=strict_json($proof); keys_only($p,qw(event_id op_id outcome evidence));
          fail('结果读回不匹配/未知') unless $p->{event_id} eq $id && $p->{op_id} eq $h->{op_id} && $p->{outcome}=~/\A(applied|not-applied)\z/ && string_ok($p->{evidence}) && $p->{evidence} ne '';
          if ($h->{handled}) { fail('重复handled结果冲突') unless $h->{result_ref} eq text($resolved) && $h->{result_sha256} eq sha256_hex($proof); print "$id\n"; exit }
          $h->{handled}=1; $h->{result_ref}=text($resolved); $h->{result_sha256}=sha256_hex($proof);
          $h->{wait_until}=0;
        } else { fail("未知交接命令 $cmd") }
      }
    }
    $line="working: $cmd event_id=$id";
  }
} elsif ($cmd eq 'migrate') {
  fail('已迁入协议，不能重迁') if $data;
  fail('仅主控能迁移') unless $controller;
  my $manifest=read_file(encode('UTF-8',$args[0] // ''));
  my $m=strict_json($manifest); keys_only($m,qw(task_sha256 confirm));
  fail('迁移快照变动；重新对账') unless $m->{task_sha256} eq sha256_hex($raw);
  my @writers=qw(run wake worktree worker controller old-fds external-actions);
  keys_only($m->{confirm},@writers);
  my @missing=grep { !string_ok($m->{confirm}{$_}) || $m->{confirm}{$_} eq '' } @writers;
  fail('未确认停写/对账：'.join(',',@missing)) if @missing;
  # 确认清单不等于关闭旧FD：本机探针独立否决；不可用/未知一律拒绝。
  my ($diag,$diag_path)=tempfile('.qwb-lsof-XXXXXXXX',DIR=>$parent,UNLINK=>1);
  my $probe_pid=open(my $probe,'-|'); defined($probe_pid) or fail('无法启动lsof');
  if (!$probe_pid) {
    open STDERR,'>&',$diag or exit 255;
    exec('lsof','-Ffa','--',$file) or exit 255;
  }
  my $fds=do { local $/; <$probe> } // ''; close $probe; my $probe_rc=$?;
  seek($diag,0,0) or fail('lsof诊断读取失败'); my $diagnostic=do { local $/; <$diag> } // ''; close $diag;
  fail('lsof无法确认旧写FD：'.text($diagnostic)) unless ($probe_rc==0 || $probe_rc==256) && $diagnostic eq '';
  fail('lsof无有效FD契约，状态未知') if $probe_rc==0 && $fds !~ /^f[0-9]+/m;
  fail('未确认停写：旧writer打开的写FD') if $fds =~ /^a[wu]/m;
  my $base=-f "$dir/bin/qwb-ledger.sh" ? "$dir/bin" : "$root/bin";
  my $templates=-f "$dir/QWBUDDY.md" ? $dir : "$root/templates";
  my %installed;
  for my $path (map { "$base/qwb-$_.sh" } qw(lib run wake worktree)) {
    my $s=read_file($path);
    fail("未迁调用者 $path") unless index($s,'qwb_ledger')>=0;
    $installed{$path}=sha256_hex($s);
  }
  for my $path ("$templates/TASK.md","$templates/QWBUDDY.md","$templates/roles/执行者.md") {
    my $s=read_file($path);
    fail("未迁模板 $path") unless index($s,'qwb-ledger.sh')>=0;
    $installed{$path}=sha256_hex($s);
  }
  fail('旧票state不合法') unless state_of($body)=~/\A(running|blocked|needs-decision|done|verified)\z/;
  if (-e "$file.qwb-original" || -l "$file.qwb-original") {
    my $saved=read_file("$file.qwb-original");
    fail('既有原字节备份与当前票不一致，必须对账') unless $saved eq $raw;
  } else {
    my $backup=safe_open("$file.qwb-original",O_WRONLY|O_CREAT|O_EXCL);
    print {$backup} $raw or fail('保存原字节失败'); $backup->sync or fail('原字节sync失败'); close $backup or fail('原字节close失败');
  }
  $data={schema=>1,rev=>0,seq=>0,spec_rev=>0,phase=>state_of($body),claim=>undef,workers=>{},questions=>{},events=>[],ops=>{},migration=>{task_sha256=>$m->{task_sha256},confirm=>$m->{confirm},installed=>\%installed}};
} elsif ($cmd eq 'append') {
  ($line)=@args; fail('行非法') unless string_ok($line) && $line =~ /\A(working|done|blocked|needs-decision|wake|worktree|worktree-space):/;
  fail('spec-resolved仅现主控可写，规划grant不扩大权限') if !$controller && $line =~ /\Aworking:\s*spec-resolved:/;
  if ($gate && !$controller) {
    # 09活动绑定接04原票派工；只许本人claim下已派child，不开放普通append权限。
    my ($child,$pane)=$line =~ /\Aworking: worker-activity op=(\S+) pane=(\S+) evidence=.+\z/;
    fail('门禁仅可写本人已派child活动绑定') unless @args==1 && defined($child) && exists($data->{gate}{dispatches}{$child}) &&
      $data->{ops}{$child}{owner} eq $actor && $data->{ops}{$child}{pane} eq $pane && $data->{ops}{$child}{status} eq 'dispatch';
    require_claim($data->{claim}{op_id}); $op=$child;
  }
  if (!$controller && $worker) {
    fail('工人不能写规格处置/运行时记录') unless $line =~ /\A(working|done|blocked|needs-decision):/ && $line !~ /\Aworking:\s*spec-resolved:/;
    $op=$data->{workers}{$actor}; fail('失败派发工人不得回报') if $data->{ops}{$op}{status} eq 'not-sent';
  }
  ($kind)=$line =~ /^([^:]+):/; append_body($line);
} elsif ($cmd eq 'prepare') {
  my ($fp,$brief)=@args;
  fail('场景在预检后已变化') unless defined($fp) && $fp =~ /\A[0-9a-f]{40}\z/ && scen_fp($body) eq $fp;
  my $spev=last_spec_event($body);
  fail('未处理规格疑点') if $spev =~ /^blocked:/;
  fail('场景基线冲突') if fp_of($body) ne '' && fp_of($body) ne $fp;
  field('state','running'); field('scenarios-fp',$fp);
  if (defined($brief) && $brief ne '') {
    fail('附页包含协作区标记') if index($brief,'<!-- qwb-collab-')>=0;
    my $bfp=sha1_hex(encode('UTF-8',$brief)); my @b=$body =~ /^brief-include-fp:\s*(\S+)$/mg;
    if (!@b || $b[-1] ne $bfp) { append_body("## 常驻附页\n\n以下是本项目常驻规则附页（qwbuddy/brief-include.md）原样收录；本附页与其余各节冲突时，以其余各节为准。\n\n$brief\nbrief-include-fp: $bfp") }
  }
} elsif ($cmd eq 'revise' && $data && $data->{planning} && $data->{planning}{pending_revision}) {
  my $p=$data->{planning}; my $r=$p->{pending_revision};
  fail('应用修订须CAS/明确source，不能覆盖在途claim') unless $expect ne '' && @args==1 && $args[0] eq $r->{source}{event} && !$data->{claim} && $r->{spec_rev}==$data->{spec_rev};
  fail('已验收历史不改') if accepted_history();
  fail('gate尚未显式交出旧验收标准') if $data->{gate} && (!$p->{revision_handoff} || $p->{revision_handoff}{spec_rev}!=$data->{spec_rev});
  push @{$p->{revisions}},{spec_rev=>$data->{spec_rev},spec=>$p->{spec},constraints=>$p->{constraints},scenarios=>scenario($body),needs=>$p->{needs},source=>$r->{source},gate=>$data->{gate}};
  spec_replace($r->{spec},$r->{constraints},$r->{scenarios});
  $p->{spec}=$r->{spec}; $p->{constraints}=$r->{constraints}; $p->{needs}=$r->{needs}; graph_check('start',0);
  $data->{spec_rev}++; delete $data->{gate}; $p->{authorization}=undef; $p->{ready}={}; $p->{pending_revision}=undef; $p->{revision_handoff}=undef;
  $line="working: spec-revised source=$r->{source}{event} spec_rev=$data->{spec_rev} previous-evidence-retained-invalid"; append_body($line);
} elsif ($cmd eq 'revise' || $cmd eq 'revise-scenarios') {
  fail('gate持旧spec或已验收历史，只能登记plan-revision并显式handoff') if $data && ($data->{gate} || $data->{phase} eq 'verified' || ($data->{claim} && $data->{claim}{owner} ne $actor));
  fail('规划票修订须使用持久plan-revision/CAS') if $planner || ($data && $data->{planning});
  my ($old,$new,$reason);
  if ($cmd eq 'revise-scenarios') {
    fail('规格修订必须给expect') if $expect eq '';
    my ($block,$why)=@args; $reason=$why; $old=fp_of($body);
    my $current=scenario($body); fail('场景块不存在') if $current eq '';
    fail('新场景块格式非法') unless scenarios_ok($block,qr/\A\#{1,6}[^#]*验收场景/);
    $body =~ s/\Q$current\E/$block/; $new=scen_fp($body);
  } else { ($old,$new,$reason)=@args }
  fail('修订前置不满足') unless $old && $old =~ /\A[0-9a-f]{40}\z/ && $new && $new =~ /\A[0-9a-f]{40}\z/ && string_ok($reason) && $reason ne '' && fp_of($body) eq $old && scen_fp($body) eq $new;
  field('scenarios-fp',$new); $data->{spec_rev}++ if $data;
  $line="working: scenarios-revised: old=$old new=$new reason=$reason"; append_body($line);
} elsif ($cmd eq 'state') {
  fail('state非法') unless $args[0] =~ /\A(running|blocked|needs-decision|done|verified)\z/; field('state',$args[0]);
} elsif ($cmd eq 'claim' || $cmd eq 'start-claim') {
  if ($cmd eq 'start-claim') {
    fail('start-claim参数非法') unless @args==2; my $e=start_check($args[1]);
    if ($data->{planning}) {
      my $p=$data->{planning}; my $fp=ready_fingerprint($p,$e);
      $p->{ready}={fingerprint=>$fp,spec_rev=>$data->{spec_rev},evidence=>$e,op_id=>$args[0],worker=>$args[1]};
      $line="working: planner-ready op_id=$args[0] fingerprint=$fp dependencies-resolved"; append_body($line);
    }
  }
  $op=$args[0]; fail('op非法/已存在') unless id_ok($op) && !exists $data->{ops}{$op};
  fail('op_id已用于交接动作') if grep { $_->{op_id} eq $op } values %{$data->{handoffs} // {}};
  fail('持久claim尚未释放') if $data->{claim};
  $data->{claim}={owner=>$actor,op_id=>$op}; $data->{ops}{$op}={owner=>$actor,pane=>'',status=>'claimed'};
} elsif ($cmd eq 'wake') {
  $kind='wake'; $line='wake: '.strftime('%Y-%m-%dT%H:%M:%SZ',gmtime)." state=$args[1] fp=$args[2]"; append_body($line);
} elsif ($cmd eq 'recover-claim') {
  fail('接管必须持期望版本') if $expect eq '';
  $op=$args[0]; fail('接管op与持久claim不符') unless id_ok($op) && $data->{claim} && $data->{claim}{op_id} eq $op;
  my $old=$data->{claim}{owner}; fail('不能接管本人/不一致op') if $old eq $actor || !exists($data->{ops}{$op}) || $data->{ops}{$op}{owner} ne $old;
  my $s=read_file(encode('UTF-8',$args[1] // ''));
  my $e=strict_json($s); keys_only($e,qw(task_sha256 op_id previous_owner reconciled));
  fail('接管快照/op/原owner/对账证据不符') unless $e->{task_sha256} eq sha256_hex($raw) && $e->{op_id} eq $op && $e->{previous_owner} eq $old && string_ok($e->{reconciled}) && $e->{reconciled} ne '';
  if ($old =~ /\Apid:([1-9][0-9]*)\z/) {
    fail('旧owner仍活或死亡未知') unless !kill(0,$1) && $! == ESRCH;
  } else {
    fail('旧owner身份非法') if $old eq '' || $old =~ /^pid:/;
    my ($j,$rc)=native_reply('pane','get',$old);
    fail('旧owner仍活或死亡未知') unless $rc && ($j->{error}{code} // '') eq 'pane_not_found';
  }
  # 转移原op所有权，不删claim/事件；补偿或release仍须随后显式进行。
  $data->{claim}{owner}=$actor; $data->{ops}{$op}{owner}=$actor;
  $line="working: claim-recovered: op_id=$op previous_owner=$old owner=$actor evidence_sha256=".sha256_hex($s)." reconciled=$e->{reconciled}"; append_body($line);
} elsif ($cmd eq 'release') {
  $op=$args[0]; require_claim($op);
  $data->{claim}=undef if $data->{claim}{op_id} eq $op;
  my $status=$data->{ops}{$op}{status};
  $data->{ops}{$op}{status}=($status eq 'dispatch' ? 'sent' : $status eq 'claimed' ? 'released' : $status);
} elsif ($cmd eq 'dispatch') {
  my $pane; ($op,$pane,$line)=@args; require_claim($op);
  fail('派发记录非法') unless string_ok($line) && string_ok($pane) && $pane ne '' && $line =~ /^dispatch:/ && index($line," pane=$pane dir=")>=0;
  if ($data && $data->{planning} && !$gate) {
    my ($selected)=$line=~/\bworker=([^ ]+)/; my $e=start_check($selected); my $p=$data->{planning};
    my $fp=ready_fingerprint($p,$e);
    fail('派工claim未绑定当前授权/就绪条件') unless ($p->{ready}{op_id} // '') eq $op && ($p->{ready}{worker} // '') eq $selected && ($p->{ready}{fingerprint} // '') eq $fp;
  }
  if ($gate) {
    my $purpose=$data->{gate}{dispatches}{$op} // fail('门禁派工必须先保留child op');
    my $b=$data->{gate}{binding};
    fail('门禁不能换工人/目录/扩产品范围') unless $line =~ /\bworker=\Q$b->{workers}{$purpose}\E(?: |\z)/ && $line =~ /\bdir=\Q$b->{candidate}\E\z/;
  }
  if ($data) {
    fail('同op重复派发或缺op_id收据') unless $data->{ops}{$op}{status} eq 'claimed' && $line =~ /\bop_id=\Q$op\E(?: |\z)/;
    $data->{workers}{$pane}=$op; $data->{ops}{$op}{pane}=$pane; $data->{ops}{$op}{status}='dispatch';
  }
  append_body($line);
} elsif ($cmd eq 'not-sent') {
  ($op,$line)=@args;
  fail('补偿状态行非法') unless string_ok($line) && $line =~ /^blocked:/;
  if ($data) {
    fail('补偿op不属于本人派发') unless id_ok($op) && exists $data->{ops}{$op} && $data->{ops}{$op}{owner} eq $actor && $data->{ops}{$op}{status} eq 'dispatch';
    my ($e)=grep { $_->{kind} eq 'dispatch' && $_->{op_id} eq $op } @{$data->{events}};
    fail('找不到唯一派发收据') unless $e;
    my $disp=$e->{line}; my $cancelled='not-sent:'.substr($disp,9);
    my $n=($body =~ s/^\Q$disp\E$/$cancelled/m);
    fail('派发收据与正文不符') unless $n;
    $data->{ops}{$op}{status}='not-sent';
  } else {
    # 旧票以完整唯一行重读定位，不复用跨FD/整票替换后的offset。
    my $disp=$args[2] // ''; fail('旧dispatch收据非法') unless $disp =~ /^dispatch:/;
    my $n=()=$body =~ /^\Q$disp\E$/mg; fail('旧dispatch不唯一') unless $n==1;
    my $cancelled='not-sent:'.substr($disp,9); $body =~ s/^\Q$disp\E$/$cancelled/m;
  }
  append_body($line);
} elsif ($cmd =~ /\A(question|answer|resume)\z/) {
  my ($key,$value)=@args; fail('问题key/内容非法') unless id_ok($key) && string_ok($value) && $value ne '';
  if ($cmd eq 'question') {
    fail('问题key已存在') if exists $data->{questions}{$key};
    $data->{questions}{$key}={opened=>$value,answer=>'',resumed=>''};
  } else {
    fail('问题key不存在') unless exists $data->{questions}{$key};
    my $q=$data->{questions}{$key};
    if ($cmd eq 'answer') { fail('问题已有答复') if $q->{answer} ne ''; $q->{answer}=$value }
    else { fail('未有真实答复不能恢复') if $q->{answer} eq ''; fail('已恢复') if $q->{resumed} ne ''; $q->{resumed}=$value }
  }
  $line=($cmd eq 'question' ? 'needs-decision' : 'working').": $cmd key=$key $value"; append_body($line);
} else { fail("未知命令 $cmd") }
my $out;
if ($data) {
  $data->{phase}=state_of($body); $data->{rev}++; $data->{seq}++;
  if ($event eq '') {
    open my $rand,'<','/dev/urandom' or fail('random不可用'); read($rand,my $bytes,16)==16 or fail('random不足'); close $rand;
    $event=unpack('H*',$bytes);
  }
  push @{$data->{events}},{event_id=>$event,seq=>$data->{seq},at=>strftime('%Y-%m-%dT%H:%M:%SZ',gmtime),kind=>$kind,actor=>$actor,op_id=>$op,spec_rev=>$data->{spec_rev},line=>$line};
  if ($handoff_return) {
    $data->{handoffs}{$event}=new_handoff($event,$handoff_return->[0],$handoff_return->[1],$data->{events}[-1],$handoff_return->[2]);
  }
  validate();
  $body =~ s/\n*\z/\n/;
  $out=encode('UTF-8',$body)."\n<!-- qwb-collab-v1\n".$json->encode($data)."\n-->\n";
} else { $out=encode($byte_legacy ? 'ISO-8859-1' : 'UTF-8',$body) }
# Legacy retains its inode; migrated tasks and posture share the atomic publisher.
publish($out,!!$data);
print defined($pending_output) ? "$pending_output\n" : "$event\n" if $data;
exit($pending_exit);
PERL
