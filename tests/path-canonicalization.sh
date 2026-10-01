#!/usr/bin/env bash
# 仅检查本地路径语义，不调用账本/身份/进程探针或 Herdr。
set -euo pipefail
perl -MCwd=realpath -MFile::Temp=tempdir -e '
  my $t=tempdir(CLEANUP=>1);
  mkdir "$t/bin" or die "mkdir: $!\n";
  for my $name (qw(qwb-wake.sh other.sh)) {
    open my $f, ">", "$t/bin/$name" or die "fixture: $!\n";
    close $f or die "close: $!\n";
  }
  symlink "$t/bin", "$t/project-link" or die "symlink: $!\n";
  symlink "$t/bin/qwb-wake.sh", "$t/script-link" or die "symlink: $!\n";
  my $expected="$t/bin/qwb-wake.sh";
  for my $case (
    [$expected,$expected,1,"real path"],
    ["$t/project-link/qwb-wake.sh",$expected,1,"linked project"],
    [$expected,"$t/project-link/qwb-wake.sh",1,"linked expected path"],
    ["$t/script-link",$expected,1,"linked script"],
    ["$t/bin/other.sh",$expected,0,"different script"],
    ["$t/missing",$expected,0,"missing candidate"],
    [$expected,"$t/missing",0,"missing expected"],
    ["$t/missing","$t/missing",0,"both missing"]
  ) {
    my ($candidate,$expected,$want,$label)=@$case;
    my $script=realpath($candidate);
    my $same=defined($script) && $script eq (realpath($expected) // "");
    die "FAIL pure path: $label\n" unless !!$same == $want;
    print "PASS pure path: $label\n";
  }
'
