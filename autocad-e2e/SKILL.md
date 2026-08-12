---
name: autocad-e2e
description: Run, diagnose, or extend ModelY end-to-end and fully automated AutoCAD tests through Autodesk Core Console. Use for command and config discovery, named-DWG validation, mutating CAD workflows, generated-DWG checks, or HTML/PDF/PNG visual reports inside the real AutoCAD host.
---

# AutoCAD E2E

Use the repository's Core Console runners to verify behavior inside AutoCAD. Read `../README.md` and the selected runner before changing or invoking it.

## Select the smallest sufficient runner

- `../Run-Tests.ps1`: command registration, facade wiring, config discovery, and YAML loading.
- `../Run-LmscTests.ps1`: read-only LMSC readiness checks against a named DWG.
- `../Run-LmscVisualTests.ps1`: real LMSC generation on a copied DWG, with an HTML/PDF/PNG visual report.

Use the visual runner when correctness depends on entities created or modified in the drawing. Core Console cannot validate modeless WPF rendering; test that in full AutoCAD.

## Execution rules

1. Build and load the standard facade at `ModelY/bin/<Configuration>/net472/ModelY.AutoCAD.dll`.
2. Do not redirect plugin output into `Artifacts` or create a parallel deployment.
3. Close AutoCAD before rebuilding. Treat `MSB3026` locked-DLL warnings as build failures; build with `-warnaserror:MSB3026` when appropriate.
4. For a user-provided DWG, copy it into a new artifact directory before running any mutating command. Never modify the source DWG.
5. Name run directories with local timestamps in `yyyyMMdd-HHmmss-fff` form. Do not use hashes or GUIDs.
6. Load the exact facade and dependent test assemblies in their required order.
7. Capture stdout and stderr asynchronously, save `CoreConsole.log`, and check the process exit code.
8. Require the runner's final semantic marker, such as `MODELY_CAD_TESTS_END|PASS` or `MODELY_CAD_VISUAL_TEST_END|PASS`, plus all expected files and assertions. A successful build or zero exit code alone is insufficient.

## Make mutating commands testable

Expose a typed headless entry point that returns a structured result or emits an unambiguous failure marker. AutoCAD command wrappers and legacy code may catch exceptions, so console execution alone can otherwise report a false pass.

Validate configured target blocks against block definitions imported inside AutoCAD. Record available, missing, and fallback block names in the artifact directory. Report latent asset gaps even when the current drawing does not exercise them.

## Produce trustworthy visual evidence

For a generation test:

1. Record model-space entity IDs before the command.
2. Run the command once on the fresh copied DWG.
3. Record entity IDs afterward and calculate the current-run difference.
4. Plot only the new entities by temporarily hiding pre-existing model entities inside an aborting transaction.
5. Save the complete post-command drawing separately as `generated.dwg`.

This prevents old elevations already present in the source drawing from overlapping the current run's visual evidence. The saved DWG remains a faithful full result and may contain both old and newly generated content.

For Core Console plotting, set `BACKGROUNDPLOT=0` and `FILEDIA=0`, activate Model space, validate plot devices, and wait for output files. Keep PDFs print-friendly. Create black-background PNG previews with the deterministic image transformation used by the harness.

Inspect every PNG for blank output, clipping, unreadable scale, and overlap. Confirm that the HTML report links or embeds every expected facade and the generated DWG.

## Diagnose failures

- Files present on disk do not prove AutoCAD discovered or loaded them. Confirm the exact loaded paths in the log.
- Separate harmless font-substitution or temporary-file cleanup warnings from failed assertions, missing markers, nonzero exit codes, and absent artifacts.
- If output overlaps, first determine whether the source already contains generated geometry; then verify current-run entity isolation and ensure the command ran only once.
- If a block is missing, inspect `block-definitions.txt`, the configured name, and any selected fallback before changing command logic.

## Report the result

State:

- the exact facade path and source DWG tested;
- the runner and PASS marker observed;
- the artifact directory, log, report, and generated-DWG paths;
- the key assertions and entity counts;
- unresolved asset, warning, or visual-quality risks.
