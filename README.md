# CadE2E-Harness

CadE2E-Harness 在 Autodesk AutoCAD Core Console 中运行 CAD 插件命令。它构建标准项目输出、复制显式输入图纸、按顺序 `NETLOAD` 指定程序集、调用一个命令，并要求出现语义成功 Marker。

Source of Truth：[to0space/CadE2E-Harness](https://github.com/to0space/CadE2E-Harness)。

## 作为 Submodule 使用

消费仓库通常把 Harness 挂载为 Git Submodule：

```powershell
git submodule add git@github.com:to0space/CadE2E-Harness.git Tests/CadE2E-Harness
git submodule update --init --recursive
```

Harness 修改应在源仓库中开发并 Push，随后更新消费仓库中的 Submodule Pointer。

## 命令冒烟测试 Runner

`Run-CommandSmoke.ps1` 是通用入口，消费仓库提供全部产品专用值：

```powershell
& .\Tests\CadE2E-Harness\Run-CommandSmoke.ps1 `
  -RepositoryRoot (Get-Location) `
  -BuildProjectPaths @('Workspace/Product/Product.csproj') `
  -AssemblyPaths @('Workspace/Product/bin/Debug/net472/Product.dll') `
  -TestDrawingPath 'Tests/TestData/input.dwg' `
  -CommandName 'PRODUCT_E2E_SMOKE' `
  -SuccessMarker 'PRODUCT_E2E_END|PASS' `
  -ProcessExitPath 'Tests/Artifacts/Product-Smoke/process-exit.json' `
  -ArtifactPrefix 'Product-Smoke'
```

`RepositoryRoot` 表示消费产品仓库，默认是直接包含 Harness Submodule 的仓库。Harness 嵌套在其他模块中时应显式传入。

Runner 会：

1. 相对消费仓库根目录解析路径；
2. 在标准输出路径构建各项目；
3. 把源 DWG 复制到时间戳 Artifact 目录；
4. 按提供顺序加载程序集；
5. 异步捕获 stdout/stderr；
6. 检查 Core Console Exit Code 和语义 Success Marker；
7. 默认把完整日志写入 `Tests/Artifacts/CadE2E-Harness/`。

无论 Core Console 成功、返回非零退出码还是被 Harness 超时终止，Runner 都会写入
`process-exit.json`。未传 `ProcessExitPath` 时，文件位于本次时间戳 Artifact
目录；传入后可让消费仓库把它固定到案例或产品验证报告目录。记录包含 CAD PID、
起止时间、原始十进制/十六进制退出码、超时及主动终止标记、Success Marker 状态、
日志位置和最终分类：`Succeeded`、`CommandFailed`、`ExitedNonZero`、
`ProcessCrashed`、`TimedOut` 或 `RunnerFailed`。

自动发现未选中预期 AutoCAD 时，传入 `-CoreConsolePath` 或设置 `CAD_E2E_CORE_CONSOLE_PATH`。旧 `MODELY_CORE_CONSOLE_PATH` 仅作为兼容 Fallback。

## 项目专用套件

配置期望、命令名、品牌 Fixture、视觉报告逻辑和产品测试程序集属于消费仓库。它们可以调用通用 Runner，也可以依照 [`autocad-e2e/SKILL.md`](autocad-e2e/SKILL.md) 的契约实现项目 Runner。

Core Console 覆盖无界面 Host 行为。工作流使用无模式 UI、Prompt 或其他交互状态时，最终验收必须在正常完整 AutoCAD 用户环境完成。
