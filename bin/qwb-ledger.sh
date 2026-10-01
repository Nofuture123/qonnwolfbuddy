#!/usr/bin/env bash
# 同一票的唯一运行时 writer；Perl 核心模块，无数据库。未迁票不启用 rename 协议。
set -euo pipefail
if [[ "${1:-}" == --help || "${1:-}" == -h ]]; then
  cat <<'EOF'
用法: qwb-ledger.sh <read|metrics|append|prepare|revise|revise-scenarios|state|claim|release|recover-claim|wake-check|wake|dispatch|not-sent|question|answer|resume|migrate> --project <根> --task <路径> [--expect <rev>] [--event-id <id>] [--legacy] -- <参数...>
gate-assign: 现主控授权已登记门禁actor + JSON（candidate/base/attempt/policy/environment/required/workers），冻结命名场景。
gate-context: 本人claim op；gate-diff: op [精确reviewed head] [直接上下文路径...]，只读差异包。
gate-review: op JSON（context/implementer/reviewer/standards/spec/covered/findings）；保原意见，当前仅Pi原生JSONL身份。
gate-verdict: op accepted，或op rework 根因 新证据；accepted仍待land/cleanup，同根因3轮无新证据转技术重诊。
gate-candidate: op 新attempt 原候选目录 base；gate-receipt: op 候选外JSON，由qwb-test生成，不自动验收。
gate-dispatch: op child review|rework 主控已授权工人；长门在独立命令/op下运行，不持writer锁等待。
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
[[ -n "$CMD" && -n "$ROOT" && -n "$TASK" ]] || { echo '错误：需要命令/project/task' >&2; exit 2; }
ACTOR="${HERDR_PANE_ID:-pid:$PPID}"
BINDIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
IDENTITY='{}'
if [[ "$CMD" != read && "$CMD" != metrics ]]; then
  # shellcheck source=/dev/null
  . "$BINDIR/qwb-lib.sh"
  if [[ "$CMD" == gate-assign ]]; then
    IDENTITY="$(qwb_gate_identity "$ROOT" "${1:-}")" || exit 1
  elif [[ -d "$ROOT/qwbuddy/.roles" ]]; then
    IDENTITY="$(qwb_gate_identity "$ROOT")" || exit 1
  fi
fi
exec perl - "$CMD" "$ROOT" "$TASK" "$ACTOR" "$EXPECT" "$EVENT" "$LEGACY" "$BINDIR" "$IDENTITY" "$@" <<'PERL'
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
my ($cmd,$root,$file,$actor,$expect,$event,$legacy,$bindir,$identity_raw,@args)=@ARGV;
sub fail { die "账本拒绝：$_[0]\n" }
sub text { my $v=shift; return decode('UTF-8',$v,FB_CROAK) }
@args=map { text($_) } @args;
$actor=text($actor);
$root=realpath($root) // fail('项目根不存在');
$file="$root/$file" unless $file =~ m{^/};
my $original_parent=dirname($file);
fail('tasks符号链接非法') if -l $original_parent;
my $parent=realpath($original_parent) // fail('tasks目录不存在');
$file="$parent/".basename($file);
fail('tasks/路径或符号链接非法') unless $parent eq "$root/tasks" && !-l $parent && -d $parent && realpath($parent) eq $parent;
fail('任务路径非法') unless basename($file) =~ /\.md\z/ && basename($file) !~ /[\x00-\x1f]/;
sub safe_open {
  my ($path,$flags)=@_;
  sysopen(my $fh,$path,$flags|O_NOFOLLOW,0600) or fail("打开 $path: $!");
  my @s=stat($fh); my @l=lstat($path);
  fail("路径非本人常规单链接文件 $path") unless @s && @l && S_ISREG($s[2]) && $s[3]==1 && $s[4]==$< && $s[0]==$l[0] && $s[1]==$l[1];
  binmode $fh; return $fh;
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
my $in=safe_open($file,O_RDONLY);
my $raw=do { local $/; <$in> }; close $in or fail('读关闭失败');
fail('票为空') unless defined($raw) && length($raw);
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
my $has_protocol=index($body,'<!-- qwb-collab-')>=0;
my $data;
if ($body =~ /\n<!-- qwb-collab-v1\n([^\n]+)\n-->\n?\z/) {
  $data=strict_json(encode('UTF-8',$1));
  $body=substr($body,0,$-[0]);
} elsif (index($body,'<!-- qwb-collab-')>=0) { fail('协作区格式非法') }
sub keys_only {
  my ($h,@keys)=@_; fail('schema对象非法') unless ref($h) eq 'HASH';
  my %ok=map { $_=>1 } @keys; my @unknown=grep { !$ok{$_} } keys %$h;
  fail('schema未知键 '.join(',',@unknown)) if @unknown;
  my @missing=grep { !exists $h->{$_} } @keys; fail('schema缺键 '.join(',',@missing)) if @missing;
}
sub id_ok { defined($_[0]) && !ref($_[0]) && $_[0] =~ /\A[A-Za-z0-9_.:-]{1,160}\z/ }
sub string_ok { defined($_[0]) && !ref($_[0]) && $_[0] !~ /[\x00-\x1f]/ }
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
sub scen_fp { sha1_hex(encode($byte_legacy ? 'ISO-8859-1' : 'UTF-8',scenario($_[0]))) }
sub validate {
  # 协议存在与JSON值真假无关；null/false/0必须拒绝，不能剥标记降级legacy。
  return unless $has_protocol || defined($data);
  keys_only($data,qw(schema rev seq spec_rev phase claim workers questions events ops migration), exists($data->{handoffs}) ? 'handoffs' : (), exists($data->{gate}) ? 'gate' : ());
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
    keys_only($g->{identity},qw(actor pane incarnation owner_fp controller session_id actual_model actual_effort));
    fail('gate身份非法') unless id_ok($g->{identity}{actor}) && string_ok($g->{identity}{pane}) && $g->{identity}{pane} ne '' && $g->{identity}{incarnation}=~/\A[1-9][0-9]*\z/ && $g->{identity}{owner_fp}=~/\A[0-9a-f]{64}\z/;
    my $b=$g->{binding}; keys_only($b,qw(candidate base attempt policy environment required workers spec_rev scenarios_fp spec_sha256 head tree workers_sha256 worker_profiles));
    fail('gate绑定非法') unless id_ok($b->{attempt}) && id_ok($b->{policy}) && $b->{candidate}=~m{\A/} && $b->{environment}=~m{\A/} && $b->{spec_rev}=~/\A[0-9]+\z/ && $b->{scenarios_fp}=~/\A[0-9a-f]{40}\z/ && $b->{spec_sha256}=~/\A[0-9a-f]{64}\z/ && ref($b->{required}) eq 'HASH' && exists($b->{required}{full});
    fail('gate候选OID非法') for grep { !defined($_) || !/\A[0-9a-f]{40,64}\z/ } @{$b}{qw(base head tree)};
    for my $name (keys %{$b->{required}}) { fail('gate场景映射非法') unless $name=~/\A(fast|full)\z/ && ref($b->{required}{$name}) eq 'ARRAY' && @{$b->{required}{$name}} }
    keys_only($b->{workers},qw(review rework)); keys_only($b->{worker_profiles},qw(review rework));
    for my $p (values %{$b->{worker_profiles}}) { keys_only($p,qw(model provider effort)); fail('gate型号配置非法') if grep { !string_ok($_) || $_ eq '' } values %$p }
    for my $id (keys %{$g->{dispatches}}) { fail('gate child op非法') unless exists($data->{ops}{$id}) && $g->{dispatches}{$id}=~/\A(review|rework)\z/ }
    fail('gate verdict非法') unless $data->{gate}{verdict}=~/\A(pending|rework|rediagnose|accepted)\z/;
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
  print $json->encode({events=>\@events,done_at=>@done ? $done[-1]{at} : 'unknown',legacy_times=>'unknown'}),"\n"; exit;
}
my $dir="$root/qwbuddy";
my $controller_guard;
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
my $controller=$owner ne '' && $owner eq $actor;
my $worker=$data && exists $data->{workers}{$actor};
my $identity=strict_json($identity_raw);
my $gate=$data && $data->{gate} && $identity->{pane} && $identity->{pane} eq $actor && $json->encode($identity) eq $json->encode($data->{gate}{identity}) && $identity->{owner_fp} eq sha256_hex($owner_raw);
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
if ($data && ($wake_cmd || $handoff_watch) && !$controller && !$gate) {
  # .watch由主控ensure在同一目录锁内登记，绑定原owner文件代次；换主控自动失效。
  my $w=safe_open("$dir/.watch",O_RDONLY); my $s=<$w> // ''; close $w;
  my ($pane,$target,$generation)=$s =~ /\Apane=(\S+) workspace=\S+ pid=\S* started=\S+ controller=(\S+) owner-fp=([0-9a-f]{64}) cmd=/;
  fail('值守未获本代主控wake授权') unless defined($pane) && $pane eq $actor && $target eq $owner && ($args[0] // '') eq $owner && $generation eq sha256_hex($owner_raw);
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
if (!$data && $legacy && $cmd ne 'migrate') {
  # expand期保留旧票格式与原inode；不能假称裸追加旧会话受新协议保护。
  # 仅已接线运行时可用；公开工人入口必须先受控迁票。
  fail('旧票仅支持运行时兼容动作') unless $cmd =~ /\A(check|wake-check|wake|append|prepare|revise|dispatch|not-sent)\z/;
} elsif ($cmd ne 'migrate') { fail('旧票只读；先停写/对账/确认迁移') unless $data }
my $gate_allowed=$cmd =~ /\A(claim|release|check|dispatch|not-sent|gate-context|gate-receipt|gate-review|gate-verdict|gate-candidate|gate-diff|gate-dispatch|handoff-pending|handoff-received|handoff-accept|handoff-activity|handoff-prepared|handoff-handled)\z/;
fail('角色未授权（仅现有主控/已绑定工人/本代获授权门禁）') unless $controller || $watcher || ($gate && $gate_allowed) || ($worker && $cmd =~ /\A(append|question|handoff-send)\z/) || (!$data && $legacy && $cmd ne 'migrate');
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
  if ($h->{accepted} ne '' && $h->{owner_fp} eq sha256_hex($owner_raw)) {
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
  my $fh=safe_open(encode('UTF-8',$_[0]),O_RDONLY); my $s=do { local $/; <$fh> }; close $fh;
  return (strict_json($s),sha256_hex($s));
}
sub receipt_interval_ok {
  my $r=shift;
  return 0 if grep { !defined($r->{$_}) || ref($r->{$_}) || $r->{$_}!~/\A[0-9]+\z/ } qw(started_at ended_at elapsed_seconds);
  return $r->{ended_at}>=$r->{started_at} && $r->{elapsed_seconds}==$r->{ended_at}-$r->{started_at};
}
sub gate_context {
  my $observe=shift // 0;
  my $g=$data->{gate} // fail('未授权门禁'); my $b=$g->{binding};
  fail('规格/场景已变；原收据失效，交主控重授权') unless $observe || $data->{spec_rev}==$b->{spec_rev} && scen_fp($body) eq $b->{scenarios_fp};
  my $spec=$body; $spec=~s/^(?:state|scenarios-fp|working|done|blocked|needs-decision|dispatch|not-sent|wake|worktree|worktree-space):[^\n]*\n?//mg;
  fail('规格正文已变') unless $observe || sha256_hex(encode('UTF-8',$spec)) eq $b->{spec_sha256};
  my $c=encode('UTF-8',$b->{candidate});
  fail('候选路径变化') unless (realpath($c) // '') eq $c && capture('git','-C',$c,'rev-parse','--show-toplevel') eq $c;
  fail('候选非本项目副本') unless capture('git','-C',$c,'rev-parse','--path-format=absolute','--git-common-dir') eq capture('git','-C',$root,'rev-parse','--path-format=absolute','--git-common-dir');
  my $conf=-f "$c/qwbuddy/config.sh" ? "$c/qwbuddy/config.sh" : "$c/qwb.config.sh";
  my $fh=safe_open($conf,O_RDONLY); my $cfg=do { local $/; <$fh> }; close $fh;
  my $workers=safe_open("$root/qwbuddy/workers.sh",O_RDONLY); my $worker_config=do { local $/; <$workers> }; close $workers;
  fail('工人型号/effort配置已变，交主控重授权') unless $observe || sha256_hex($worker_config) eq $b->{workers_sha256};
  my $envfh=safe_open(encode('UTF-8',$b->{environment}),O_RDONLY); my $envbody=do { local $/; <$envfh> }; close $envfh;
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
  return {task=>text($file),project=>text($root),candidate=>$b->{candidate},attempt=>$b->{attempt},base=>$b->{base},workers=>$b->{workers},worker_profiles=>$b->{worker_profiles},workers_sha256=>sha256_hex($worker_config),head=>$head,tree=>$tree,status=>$dirty eq '' ? 'clean' : 'dirty',dirty_sha256=>sha256_hex($dirty),spec_rev=>$data->{spec_rev},spec_sha256=>sha256_hex(encode('UTF-8',$spec)),scenarios_fp=>scen_fp($body),policy=>$b->{policy},required=>$b->{required},config=>text($conf),config_sha256=>sha256_hex($cfg),commands=>\%commands,environment_sha256=>sha256_hex($json->encode(\%environment))};
}
if ($cmd eq 'gate-context' || $cmd eq 'gate-diff') {
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
  my ($r,$sha)=json_file($args[1]); keys_only($r,qw(context implementer reviewer standards spec covered findings));
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
  fail('同原生会话/同family审核冲突；保留现有身份门') if $r->{implementer}{session} eq $r->{reviewer}{session} || $r->{implementer}{family} eq $r->{reviewer}{family} || $r->{reviewer}{session} eq $data->{gate}{identity}{session_id};
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
    fail('dirty或无独立审核') unless $c->{status} eq 'clean' && @{$g->{reviews}};
    for my $id (keys %{$g->{dispatches}}) {
      my $status=$data->{ops}{$id}{status};
      fail('派出的审核/返修仍在途，不能ready') if $status=~/\A(claimed|dispatch)\z/ || ($status eq 'sent' && !grep { $_->{op_id} eq $id && $_->{kind} eq 'done' } @{$data->{events}});
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
    my $spev=''; while ($body =~ /^(blocked:\s*spec-defect:.*|working:\s*spec-resolved:.*)$/mg) { $spev=$1 }
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
  fail('candidate参数非法') unless @args==4; require_claim($args[0]);
  my ($id,$attempt,$candidate,$base)=@args; my $g=$data->{gate};
  fail('只能在原票rework后提交新attempt') unless $g->{verdict} eq 'rework' && id_ok($attempt) && $attempt ne $g->{binding}{attempt} && $base eq $g->{binding}{base};
  fail('不能切到未授权副本') unless $candidate eq $g->{binding}{candidate};
  for my $id (grep { $g->{dispatches}{$_} eq 'rework' } keys %{$g->{dispatches}}) {
    my $status=$data->{ops}{$id}{status};
    fail('返修工人尚未交回，不能切candidate') if $status=~/\A(claimed|dispatch)\z/ || ($status eq 'sent' && !grep { $_->{op_id} eq $id && $_->{kind} eq 'done' } @{$data->{events}});
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
    $g->{dispatches}{$id} eq $purpose && ($data->{ops}{$id}{status}=~/\A(claimed|dispatch)\z/ || ($data->{ops}{$id}{status} eq 'sent' && !grep { $_->{op_id} eq $id && $_->{kind} eq 'done' } @{$data->{events}}))
  } keys %{$g->{dispatches}};
  $g->{dispatches}{$child}=$purpose; $data->{ops}{$child}={owner=>$actor,pane=>'',status=>'claimed'};
  $op=$child; $line="working: gate-dispatch purpose=$purpose acceptance-op=$claim child=$child original-scope"; append_body($line);
} elsif ($cmd eq 'gate-assign') {
  fail('授权仅现主控且票必须已迁/无在途claim') unless $controller && $data && !$data->{claim};
  fail('门禁身份未证实或已授权（不覆盖历史）') unless @args==2 && $identity->{actor} eq $args[0] && !$data->{gate};
  my $fh=safe_open(encode('UTF-8',$args[1]),O_RDONLY); my $s=do { local $/; <$fh> }; close $fh;
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
  my $spec=$body; $spec=~s/^(?:state|scenarios-fp|working|done|blocked|needs-decision|dispatch|not-sent|wake|worktree|worktree-space):[^\n]*\n?//mg;
  $b->{spec_sha256}=sha256_hex(encode('UTF-8',$spec));
  my $workers=safe_open("$root/qwbuddy/workers.sh",O_RDONLY); my $worker_config=do { local $/; <$workers> }; close $workers;
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
      next unless $e->{kind} eq 'migrate' || ($e->{kind} !~ /\A(?:handoff-|gate-(?!verdict))/ && $e->{line}=~/\A(working|done|blocked|needs-decision):/);
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
      fail('仅当前收件人能确认') unless $controller || $gate;
      require_claim($data->{claim}{op_id}) if $gate;
      if ($cmd eq 'handoff-received') {
        fail('received参数非法') unless @args==1;
        if ($h->{received} eq $actor) { print "$id\n"; exit }
        $h->{received}=$actor;
      } elsif ($cmd eq 'handoff-accept') {
        my $idop=$args[1]; fail('accept必须先received且op_id合法') unless @args==2 && $h->{received} eq $actor && id_ok($idop);
        if ($h->{accepted} ne '') {
          fail('claim已存在，须先对账接班') unless $h->{accepted} eq $actor && $h->{owner_fp} eq sha256_hex($owner_raw) && $h->{op_id} eq $idop;
          print "$id\n"; exit;
        }
        fail('op_id已用于另一动作') if exists($data->{ops}{$idop}) || grep { $_->{op_id} eq $idop } values %{$data->{handoffs}};
        $h->{accepted}=$actor; $h->{owner_fp}=sha256_hex($owner_raw); $h->{op_id}=$idop; $h->{activity_at}=$now;
      } elsif ($cmd eq 'handoff-reconcile') {
        fail('接班必须持版本和原claim') unless @args==2 && $expect ne '' && $h->{accepted} ne '' && !$h->{handled};
        my $fh=safe_open(encode('UTF-8',$args[1]),O_RDONLY); my $proof=do { local $/; <$fh> }; close $fh;
        my $p=strict_json($proof); keys_only($p,qw(task_sha256 op_id previous_owner reconciled));
        fail('接班快照/claim/对账证据不一致') unless $p->{task_sha256} eq sha256_hex($raw) && $p->{op_id} eq $h->{op_id} && $p->{previous_owner} eq $h->{accepted} && string_ok($p->{reconciled}) && $p->{reconciled} ne '';
        my $old=$h->{accepted};
        fail('同pane新代际无法证明旧claim owner死亡，保留待办') if $old eq $actor && $h->{owner_fp} ne sha256_hex($owner_raw);
        if ($old ne $actor) {
          if ($old =~ /\Apid:([1-9][0-9]*)\z/) { fail('旧claim owner仍活或未知') unless !kill(0,$1) && $! == ESRCH }
          else { my ($j,$rc)=native_reply('pane','get',$old); fail('旧claim owner仍活或未知') unless $rc && ($j->{error}{code} // '') eq 'pane_not_found' }
        }
        $h->{accepted}=$actor; $h->{received}=$actor; $h->{owner_fp}=sha256_hex($owner_raw); $h->{activity_at}=$now;
        $h->{wait_until}=0; $h->{wait_reason}='';
        # op/prepared保持原值；先读回结果，绝不因为重启而重放副作用。
      } else {
        fail('无本代accepted claim；接班先对账') unless $h->{accepted} eq $actor && $h->{owner_fp} eq sha256_hex($owner_raw);
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
          my $fh=safe_open($ref,O_RDONLY); my $proof=do { local $/; <$fh> }; close $fh;
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
  my $mfh=safe_open(encode('UTF-8',$args[0] // ''),O_RDONLY);
  my $manifest=do { local $/; <$mfh> }; close $mfh;
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
    my $fh=safe_open($path,O_RDONLY); my $s=do { local $/; <$fh> }; close $fh;
    fail("未迁调用者 $path") unless index($s,'qwb_ledger')>=0;
    $installed{$path}=sha256_hex($s);
  }
  for my $path ("$templates/TASK.md","$templates/QWBUDDY.md","$templates/roles/执行者.md") {
    my $fh=safe_open($path,O_RDONLY); my $s=do { local $/; <$fh> }; close $fh;
    fail("未迁模板 $path") unless index($s,'qwb-ledger.sh')>=0;
    $installed{$path}=sha256_hex($s);
  }
  fail('旧票state不合法') unless state_of($body)=~/\A(running|blocked|needs-decision|done|verified)\z/;
  if (-e "$file.qwb-original" || -l "$file.qwb-original") {
    my $backup=safe_open("$file.qwb-original",O_RDONLY); my $saved=do { local $/; <$backup> }; close $backup;
    fail('既有原字节备份与当前票不一致，必须对账') unless $saved eq $raw;
  } else {
    my $backup=safe_open("$file.qwb-original",O_WRONLY|O_CREAT|O_EXCL);
    print {$backup} $raw or fail('保存原字节失败'); $backup->sync or fail('原字节sync失败'); close $backup or fail('原字节close失败');
  }
  $data={schema=>1,rev=>0,seq=>0,spec_rev=>0,phase=>state_of($body),claim=>undef,workers=>{},questions=>{},events=>[],ops=>{},migration=>{task_sha256=>$m->{task_sha256},confirm=>$m->{confirm},installed=>\%installed}};
} elsif ($cmd eq 'append') {
  ($line)=@args; fail('行非法') unless string_ok($line) && $line =~ /\A(working|done|blocked|needs-decision|wake|worktree|worktree-space):/;
  if (!$controller && $worker) {
    fail('工人不能写规格处置/运行时记录') unless $line =~ /\A(working|done|blocked|needs-decision):/ && $line !~ /\Aworking:\s*spec-resolved:/;
    $op=$data->{workers}{$actor}; fail('失败派发工人不得回报') if $data->{ops}{$op}{status} eq 'not-sent';
  }
  ($kind)=$line =~ /^([^:]+):/; append_body($line);
} elsif ($cmd eq 'prepare') {
  my ($fp,$brief)=@args;
  fail('场景在预检后已变化') unless defined($fp) && $fp =~ /\A[0-9a-f]{40}\z/ && scen_fp($body) eq $fp;
  my $spev=''; while ($body =~ /^(blocked:\s*spec-defect:.*|working:\s*spec-resolved:.*)$/mg) { $spev=$1 }
  fail('未处理规格疑点') if $spev =~ /^blocked:/;
  fail('场景基线冲突') if fp_of($body) ne '' && fp_of($body) ne $fp;
  field('state','running'); field('scenarios-fp',$fp);
  if (defined($brief) && $brief ne '') {
    fail('附页包含协作区标记') if index($brief,'<!-- qwb-collab-')>=0;
    my $bfp=sha1_hex(encode('UTF-8',$brief)); my @b=$body =~ /^brief-include-fp:\s*(\S+)$/mg;
    if (!@b || $b[-1] ne $bfp) { append_body("## 常驻附页\n\n以下是本项目常驻规则附页（qwbuddy/brief-include.md）原样收录；本附页与其余各节冲突时，以其余各节为准。\n\n$brief\nbrief-include-fp: $bfp") }
  }
} elsif ($cmd eq 'revise' || $cmd eq 'revise-scenarios') {
  my ($old,$new,$reason);
  if ($cmd eq 'revise-scenarios') {
    fail('规格修订必须给expect') if $expect eq '';
    my ($block,$why)=@args; $reason=$why; $old=fp_of($body);
    my $current=scenario($body); fail('场景块不存在') if $current eq '';
    fail('新场景块格式非法') unless $block =~ /\A\#{1,6}[^#]*验收场景/ && $block =~ /Given/ && $block =~ /When/ && $block =~ /Then/ && $block =~ /失败|拒绝|fail|error/i && index($block,'<!-- qwb-collab-')<0;
    $body =~ s/\Q$current\E/$block/; $new=scen_fp($body);
  } else { ($old,$new,$reason)=@args }
  fail('修订前置不满足') unless $old && $old =~ /\A[0-9a-f]{40}\z/ && $new && $new =~ /\A[0-9a-f]{40}\z/ && string_ok($reason) && $reason ne '' && fp_of($body) eq $old && scen_fp($body) eq $new;
  field('scenarios-fp',$new); $data->{spec_rev}++ if $data;
  $line="working: scenarios-revised: old=$old new=$new reason=$reason"; append_body($line);
} elsif ($cmd eq 'state') {
  fail('state非法') unless $args[0] =~ /\A(running|blocked|needs-decision|done|verified)\z/; field('state',$args[0]);
} elsif ($cmd eq 'claim') {
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
  my $fh=safe_open(encode('UTF-8',$args[1] // ''),O_RDONLY); my $s=do { local $/; <$fh> }; close $fh;
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
# 检查最新原路径，拒绝合作区外裸追加/替换；锁对象仍是同一个sidecar inode。
my $check=safe_open($file,O_RDONLY); my $latest=do { local $/; <$check> }; close $check;
fail('票在锁内被旧writer改动，停新动作并对账') unless $latest eq $raw;
if (!$data) {
  # legacy不换inode（持旧FD的会话还没停）；新协议安全保证只在contract后成立。
  my $w=safe_open($file,O_RDWR); seek($w,0,0) or fail('legacy seek失败');
  print {$w} $out or fail('legacy写失败'); truncate($w,length($out)) or fail('legacy truncate失败'); close $w or fail('legacy close失败');
} else {
  my ($w,$tmp)=tempfile('.qwb-publish-XXXXXXXX',DIR=>$parent,UNLINK=>0);
  my $ok=eval {
    binmode $w;
    my @s=stat($file); chmod($s[2]&0777,$tmp) or fail('candidate chmod失败');
    print {$w} $out or fail('candidate写失败'); $w->sync or fail('candidate sync失败'); close $w or fail('candidate close失败');
    # 使用独立程序作发布点，测试可用PATH假mv屏障/失败；无shell/eval。
    system('mv','-f','--',$tmp,$file)==0 or fail('候选发布失败');
    1;
  };
  if (!$ok) { my $error=$@; close $w; unlink $tmp; die $error }
}
print defined($pending_output) ? "$pending_output\n" : "$event\n" if $data;
PERL
