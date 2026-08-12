# CadE2E-Harness

CadE2E-Harness runs CAD plugin commands inside Autodesk AutoCAD Core Console.
It builds standard project outputs, copies an explicit input drawing, NETLOADs
the requested assemblies, invokes one command, and requires a semantic success
marker.

Source of truth: [to0space/CadE2E-Harness](https://github.com/to0space/CadE2E-Harness).

## Use as a submodule

A consuming repository normally mounts the harness as a Git submodule:

```powershell
git submodule add git@github.com:to0space/CadE2E-Harness.git tests/CadE2E-Harness
git submodule update --init --recursive
```

Develop harness changes in the source repository, push them, then update the
consuming repository's submodule pointer.

## Command smoke runner

`Run-CommandSmoke.ps1` is the generic entry point. The consuming repository
supplies all product-specific values:

```powershell
& .\tests\CadE2E-Harness\Run-CommandSmoke.ps1 `
  -RepositoryRoot (Get-Location) `
  -BuildProjectPaths @('Workspace/Product/Product.csproj') `
  -AssemblyPaths @('Workspace/Product/bin/Debug/net472/Product.dll') `
  -TestDrawingPath 'Tests/TestData/input.dwg' `
  -CommandName 'PRODUCT_E2E_SMOKE' `
  -SuccessMarker 'PRODUCT_E2E_END|PASS' `
  -ArtifactPrefix 'Product-Smoke'
```

`RepositoryRoot` identifies the consuming product repository and defaults to
the repository that directly contains the Harness submodule. Pass it when the
Harness is nested inside another mounted module.

The runner:

1. resolves paths relative to the consuming repository root;
2. builds each requested project at its standard output path;
3. copies the source DWG into a timestamped artifact directory;
4. loads assemblies in the supplied order;
5. captures stdout and stderr without blocking;
6. checks the Core Console exit code and semantic success marker; and
7. writes the full log under `Artifacts/CadE2E-Harness/`.

Pass `-CoreConsolePath` or set `CAD_E2E_CORE_CONSOLE_PATH` when automatic
discovery does not select the intended AutoCAD installation. The legacy
`MODELY_CORE_CONSOLE_PATH` variable remains available as a compatibility
fallback.

## Project-specific suites

Configuration expectations, command names, brand fixtures, visual-report
logic, and product test assemblies belong in the consuming repository. They
may call this generic runner or implement a project-owned runner using the
contract in [`autocad-e2e/SKILL.md`](autocad-e2e/SKILL.md).

Core Console covers headless host behavior. Complete interactive acceptance in
a normal full-AutoCAD user environment when the workflow uses modeless UI,
prompts, or other interactive host state.
