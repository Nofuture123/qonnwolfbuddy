#!/usr/bin/env bash
# 同一票的唯一运行时 writer；Perl 核心模块，无数据库。未迁票不启用 rename 协议。
set -euo pipefail
if [[ "${1:-}" == --help || "${1:-}" == -h ]]; then
  cat <<'EOF'
用法: qwb-ledger.sh <read|metrics|append|prepare|revise|revise-scenarios|state|claim|release|recover-claim|wake-check|wake|dispatch|not-sent|question|answer|resume|migrate> --project <根> --task <路径> [--expect <rev>] [--event-id <id>] [--legacy] -- <参数...>
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
exec perl - "$CMD" "$ROOT" "$TASK" "$ACTOR" "$EXPECT" "$EVENT" "$LEGACY" "$BINDIR" "$@" <<'PERL'
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
use Errno qw(ESRCH);
binmode STDERR, ':encoding(UTF-8)';
my ($cmd,$root,$file,$actor,$expect,$event,$legacy,$bindir,@args)=@ARGV;
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
  keys_only($data,qw(schema rev seq spec_rev phase claim workers questions events ops migration));
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
sub native_reply {
  open my $probe,'-|','herdr',@_ or fail('原生身份探针无法启动');
  my $s=do { local $/; <$probe> } // ''; close $probe; my $rc=$?;
  my $j=strict_json($s); fail('原生身份回复不是对象') unless ref($j) eq 'HASH';
  return ($j,$rc);
}
my $wake_cmd=$cmd eq 'wake' || $cmd eq 'wake-check';
my $watcher=0;
if ($data && $wake_cmd && !$controller) {
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
fail('角色未授权（仅现有主控/已绑定工人）') unless $controller || $watcher || ($worker && $cmd =~ /\A(append|question)\z/) || (!$data && $legacy && $cmd ne 'migrate');
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
my ($kind,$line,$op)=($cmd,'','');
sub append_body { $body =~ s/\n?\z/\n/; $body.="$_[0]\n" }
sub field {
  my ($key,$val)=@_;
  my $n=()=$body =~ /^\Q$key\E:/mg; fail("重复$key") if $n>1;
  if ($n) { $body =~ s/^\Q$key\E:[^\n]*/$key: $val/m }
  else { $body="$key: $val\n$body" }
}
sub require_claim {
  my $id=shift; fail('op_id非法') unless id_ok($id);
  if ($data) { fail('无本人持久claim/op') unless $data->{claim} && $data->{claim}{owner} eq $actor && $data->{claim}{op_id} eq $id }
}
if ($cmd eq 'migrate') {
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
  $op=$args[0]; require_claim($op); $data->{claim}=undef;
  my $status=$data->{ops}{$op}{status};
  $data->{ops}{$op}{status}=($status eq 'dispatch' ? 'sent' : $status eq 'claimed' ? 'released' : $status);
} elsif ($cmd eq 'dispatch') {
  my $pane; ($op,$pane,$line)=@args; require_claim($op);
  fail('派发记录非法') unless string_ok($line) && string_ok($pane) && $pane ne '' && $line =~ /^dispatch:/ && index($line," pane=$pane dir=")>=0;
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
print "$event\n" if $data;
PERL
