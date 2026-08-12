# CadE2E-Harness

CadE2E-Harness executes CAD plugins inside Autodesk AutoCAD Core Console: build
the plugin, `NETLOAD` it through an AutoCAD script, invoke a test command, and
assert against the console output and generated artifacts.

Source of truth: [to0space/CadE2E-Harness](https://github.com/to0space/CadE2E-Harness).

The harness is normally committed into a consuming project as a Git submodule.
For ModelY, use the conventional path `tests/CadE2E-Harness`:

```powershell
git submodule add git@github.com:to0space/CadE2E-Harness.git tests/CadE2E-Harness
git submodule update --init --recursive
git add .gitmodules tests/CadE2E-Harness
git commit -m "Add CadE2E-Harness submodule"
```

After cloning a consuming project, initialize the harness with
`git submodule update --init --recursive`. Commit harness development in its
source repository first, then commit the updated submodule pointer in the
consuming project.

The consuming repository owns its plugin and test-command assemblies. This
submodule owns the runners, E2E execution conventions, and reusable skill.

The config-discovery test calls the same catalog and YAML loader used by
`T0PZ`. It verifies that these files are visible and parse successfully inside
the AutoCAD host:

- `GlobalConfig.yaml`
- `HelloTo0Config.yaml`
- `CadToSuConfig.yaml`
- `ZhuanZhuanLmscConfig.yaml`

Run from the repository root:

```powershell
& .\tests\CadE2E-Harness\Run-Tests.ps1
```

The runner locates the newest installed `accoreconsole.exe`. Override it when
needed:

```powershell
& .\tests\CadE2E-Harness\Run-Tests.ps1 `
  -CoreConsolePath "C:\Program Files\Autodesk\AutoCAD 2023\accoreconsole.exe" `
  -TestDrawingPath "D:\path\to\store-plan.dwg"
```

The runner builds and tests the standard facade deployment:

```text
ModelY/bin/Debug/net472/ModelY.AutoCAD.dll
```

It does not create a second plugin deployment. Core Console logs are written
under `Artifacts/CadE2E-Harness/`.

To validate the exact deployment loaded by AutoCAD without rebuilding it:

```powershell
& .\tests\CadE2E-Harness\Run-Tests.ps1 `
  -ExistingPluginPath ".\ModelY\bin\Debug\net472\ModelY.AutoCAD.dll" `
  -TestDrawingPath "D:\path\to\store-plan.dwg"
```

Core Console is headless, so this test covers command registration and the
catalog feeding the T0PZ file selector. WPF rendering remains a GUI-host test.

## LMSC named-DWG tests

`Run-LmscTests.ps1` loads a named drawing, the standard ModelY facade, and the
test assembly, then invokes the AutoCAD command `RunCADtests`:

```powershell
& .\tests\CadE2E-Harness\Run-LmscTests.ps1 `
  -CoreConsolePath "C:\Program Files\Autodesk\AutoCAD 2023\accoreconsole.exe" `
  -TestDrawingPath "D:\path\to\store-plan.dwg"
```

The current suite is read-only. It validates the named drawing, LMSC YAML,
standard block asset, paper layouts, facade index blocks and viewports, local
index geometry, Zhuanzhuan drawing frames, and configured plan-block mappings.

To see the same test in full AutoCAD, load these assemblies in order:

1. `ModelY/bin/Debug/net472/ModelY.AutoCAD.dll`
2. `Tests/ModelY.AutoCAD.Tests/bin/Debug/net472/ModelY.AutoCAD.Tests.dll`

Open the target DWG and run `RunCADtests`.

## LMSC visual report

`Run-LmscVisualTests.ps1` runs the real LMSC generation workflow on a copied
DWG. Its fixed MVP profile is 中岛, facades A/B/C/D, 3200 left/right heights,
and the legacy default upper-logo dimensions. The source DWG remains unchanged.

```powershell
& .\tests\CadE2E-Harness\Run-LmscVisualTests.ps1 `
  -CoreConsolePath "C:\Program Files\Autodesk\AutoCAD 2023\accoreconsole.exe" `
  -TestDrawingPath "D:\path\to\store-plan.dwg"
```

The result folder uses a readable local timestamp, for example
`Artifacts/CadE2E-Harness/Lmsc-Visual-20260811-193045-123`. It contains:

- `report.html`, with an embedded PDF view for each generated facade;
- `facade-A.pdf` through `facade-D.pdf`, plus black-background PNG previews;
- `generated.dwg`, the modified test copy;
- `CoreConsole.log`.

The runner requires all four facade PDFs and the
`MODELY_CAD_VISUAL_TEST_END|PASS` marker.

PDF and PNG facade views isolate the model-space entities created by the
current LMSC run. Existing elevations in the source drawing therefore do not
overlap the visual evidence. The saved `generated.dwg` remains the complete
post-command drawing.

## Configured generic LMSC visual report

`Run-LmscGdcVisualTests.ps1` verifies `GenericDesignCommands/Lmsc` separately
from the Zhuanzhuan CDC runtime. Its test bridge infers a generic YAML from the
CDC's mapping and planning sections, supplies A/B/C/D index frames, and invokes
`LmscCommand` with the generic adapter and workflow:

```powershell
& .\tests\CadE2E-Harness\Run-LmscGdcVisualTests.ps1 `
  -CoreConsolePath "C:\Program Files\Autodesk\AutoCAD 2023\accoreconsole.exe" `
  -TestDrawingPath "D:\path\to\store-plan.dwg"
```

Artifacts use the `Lmsc-Gdc-Visual-yyyyMMdd-HHmmss-fff` prefix. The HTML report
links the inferred `LmscConfig.yaml`, generated DWG, A/B/C/D PDF/PNG views,
missing block inventory, and any `PolicyKey` values that still require a
client-specific runtime extension.
