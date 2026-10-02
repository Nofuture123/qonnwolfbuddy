# 项目测试策略 qwb-v1

schema: qwb-test-policy-v1
policy_rev: qwb-v1
risks: normal high
required-gates: full

## 风险—场景—命令

normal：已有公共行为和冻结 user_ 正常/失败场景；按票 required 映射执行项目 QWB_GATE_FAST / QWB_GATE_FULL。
high：已有授权、身份、数据安全、恢复/重复事件场景同样直接使用策略，不加测试角色会签；不能把 risk 降 normal 洗旧收据。
快门保护 shell 语法与 ShellCheck；全门保护现有 smoke、review-identity、qwb-lint（安装项目按自己的 config.sh 原命令，不复制母本命令）。原合并前 full 保持必需；策略不自动覆盖新增产品行为。
关键失败信号：dirty/旧 commit 或 tree、spec/场景变化、命令/配置/相关环境变化、策略内容变化、未决缺陷/问题、失败后重放较早成功，都不得 ready。

## 一次受限咨询

只有新行为、真实策略缺口、复杂非绿或同因三轮无新证据的有界技术重诊才请求测试体系。
复用原票 writer、02常驻身份、03关联交接；请求和回复绑定原票/spec/场景/policy。
测试负责人仅回复最小验证条件或受限补测建议；授权执行者写测试，不能替作者自证，gate独自验收。
没有任务健康闲置，不扫全仓造票、不按测试数量记成绩、不新建测试框架、不自动问用户或跑全项目。

## 证据与版本

只复用同 task/attempt、commit+tree、干净对象、spec/场景、命令/config/相关环境及 policy_rev+内容摘要的可信收据；失败后的成功必须明确较晚。变更使相应收据失效，只重跑受影响门，不叠四轮全门。
票只引用本版本，不复制策略正文。已验证版本不可覆盖；修订新增文件/版本，保留旧版及原票引用，回退留影响说明，不无痕改风险。
报告保护效果、失败信号、命令退出码、验证秒数、复用收据摘要；未测 token/费用 unknown。收据不是自动验收/合并/发布。
