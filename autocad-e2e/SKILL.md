---
name: autocad-e2e
description: 通过 Autodesk AutoCAD Core Console 运行、诊断或扩展端到端和全自动 CAD 测试，并在正常完整 AutoCAD 用户环境中完成验证。适用于程序集加载、命令执行、命名 DWG 校验、写图工作流、生成 DWG 检查、HTML/PDF/PNG 视觉证据和最终用户环境验收。
---

# AutoCAD E2E

执行前阅读消费仓库的 Codebase-specific Test Skill 和所选 Runner。消费仓库定义构建目标、程序集路径、AutoCAD 命令、语义 Marker 和期望 Artifact。

## 选择最小充分测试

- 命令注册、依赖加载和配置发现：Host Loading Test；
- 图纸就绪度和领域断言：只读 Named-DWG Test；
- 正确性依赖生成或修改实体：Mutating Named-DWG Test；
- 需要检查几何、布局、比例、裁切或重叠：增加视觉报告。

Core Console 验证无界面 AutoCAD 行为；无模式 UI 和交互窗口在完整 AutoCAD 中验证。

## 运行类型化 Command Smoke

消费仓库提供一个带语义 PASS Marker 的 Headless AutoCAD Test Command 时，使用 `Run-CommandSmoke.ps1`。传入标准构建项目、NETLOAD 顺序、命令名、Marker 和显式输入图纸；Harness 嵌套时传入消费 `RepositoryRoot`。Runner 会复制图纸、保持标准输出构建、加载程序集、保存日志并要求 Marker。

聚合测试命令中，每个迁移命令使用独立命名断言。增加用例后重跑整套测试，保证旧阶段仍有覆盖。Typed Smoke 证明配置加载、依赖加载和确定性 Planner；所需 DWG 状态具备前，写图和视觉等价保持 Pending。

## 执行契约

1. 构建并加载消费项目的标准部署输出；
2. 测试不得创建平行插件部署；
3. 锁定部署警告视为构建失败；
4. 写图命令运行前，把用户图纸复制到新的 Artifact 目录；
5. 运行目录使用本地时间戳 `yyyyMMdd-HHmmss-fff`；
6. 按所需顺序加载被测程序集；
7. 异步捕获 stdout/stderr 并保存完整 Host Log；
8. 检查 Exit Code、项目语义 Completion Marker、全部断言和必需 Artifact。

构建成功或进程 Exit Code 为 0 都不能单独证明 E2E 成功。

## 让命令可自动化

公开返回结构化结果的类型化 Headless Entry Point，或输出无歧义 Success/Failure Marker。CAD Wrapper 和 Legacy Code 可能捕获异常，因此 Runner 必须独立于 Process Exit Code 检测语义失败。

行为依赖导入块定义、Drawing Dictionary、Layout 或其他 Host State 时，配置与资产校验应在 AutoCAD Host 内完成，并保存足以解释 Missing/Substituted/Fallback Resource 的诊断。

## 生成可信视觉证据

生成测试应：

1. 命令前记录 Model Space Entity ID；
2. 在新图纸副本上只运行一次命令；
3. 命令后记录 Entity ID 并求本次新增集合；
4. 在 Abort Transaction 中临时隐藏已有实体，只 Plot 本次实体；
5. 单独保存完整命令后图纸。

源图已有生成几何时，这能隔离本次视觉证据；保存 DWG 仍是完整结果。

Core Console Plot 时关闭 Background Plot 和 File Dialog，激活所需 Layout，校验 Plot Device 并等待输出文件。PDF 应便于打印；消费项目可以生成确定性黑底预览供屏幕检查。

逐张检查空白、裁切、比例不可读和重叠；确认报告覆盖全部预期 View，并链接生成图纸。

## 在正常用户环境重跑

自动套件通过后，在正常用户 Profile 的完整 AutoCAD 中重跑用户工作流，作为交互加载变更的最终验收：

1. 加载 Core Console 已测试的同一标准部署程序集；
2. 打开自动测试使用的代表性图纸新副本；
3. 通过正常 UI 或命令行运行真实公开命令；
4. 检查 Command Discovery、Dependency、Configuration/Asset、Prompt/UI、Drawing Mutation 和保存结果；
5. 记录程序集路径、AutoCAD 版本/Profile、输入图纸、命令、观察结果和截图/生成图纸。

该验收完成前，状态写为 `Core Console PASS / normal-user run pending`。Agent 无法控制交互 CAD 时，提供精确复现步骤并记录用户结果。

## 诊断失败

- 确认 AutoCAD 实际加载的程序集；文件存在不代表已发现或加载；
- 区分 Host Warning、Assertion Failure、Missing Marker、Nonzero Exit Code 和 Missing Artifact；
- 出现重叠时，判断源图是否已有输出，校验本次实体隔离，并确认命令只执行一次；
- 缺少资产时，先比较配置标识与 AutoCAD 内实际加载定义，再修改领域逻辑。

## 报告结果

说明加载程序集、输入图纸、Runner、语义 Marker、关键断言、Artifact 路径、生成实体数、Normal-user 验收状态和未解决风险。
