# 本仓（QW buddy 母本仓）自己的质量门声明：qwb-test.sh fast|full 读取执行
QWB_GATE_FAST='for f in bin/*.sh tests/smoke.sh; do bash -n "$f" || exit 1; done && shellcheck bin/*.sh'
QWB_GATE_FULL="bash tests/smoke.sh && bash bin/qwb-lint.sh"
