---
name: autocad-e2e
description: Run, diagnose, or extend end-to-end and fully automated CAD tests through Autodesk AutoCAD Core Console, then verify the result in a normal full-AutoCAD user environment. Use for assembly loading, command execution, named-DWG validation, mutating CAD workflows, generated-DWG checks, HTML/PDF/PNG visual evidence, or final user-environment acceptance in a consuming codebase.
---

# AutoCAD E2E

Read the consuming repository's codebase-specific test skill and the selected
runner before execution. The consuming repository defines its build targets,
assembly paths, AutoCAD commands, semantic markers, and expected artifacts.

## Select the smallest sufficient test

- Use a host-loading test for command registration, dependency loading, and configuration discovery.
- Use a read-only named-DWG test for drawing readiness and domain assertions.
- Use a mutating named-DWG test when correctness depends on generated or modified CAD entities.
- Add a visual report when geometry, layout, scale, clipping, or overlap must be inspected.

Core Console validates headless AutoCAD behavior. Validate modeless UI rendering
and interactive window behavior in full AutoCAD.

## Run a typed command smoke suite

Use `Run-CommandSmoke.ps1` when the consuming repository exposes one headless
AutoCAD test command with a semantic PASS marker. Supply the standard projects
to build, assemblies in NETLOAD order, command name, marker, and optional input
drawing. The runner copies the drawing, builds without redirecting output,
loads the requested assemblies, persists the log, and requires the marker.

Treat each migrated command as a separate named assertion inside the aggregate
test command. Rerun the aggregate suite after adding each case so older command
slices remain covered. A typed smoke establishes config loading, dependency
loading, and deterministic planner behavior. Keep drawing mutation and visual
equivalence pending until the required DWG state is available.

## Execution contract

1. Build and load the consuming project's standard deployment output.
2. Do not create a parallel plugin deployment for testing.
3. Treat locked deployment warnings as build failures.
4. Copy a user-provided drawing into a new artifact directory before any mutating command.
5. Name run directories with local timestamps in `yyyyMMdd-HHmmss-fff` form.
6. Load the exact assemblies under test in their required order.
7. Capture stdout and stderr asynchronously and persist the complete host log.
8. Check the Core Console exit code, the project-defined semantic completion marker, every assertion, and every required artifact.

A successful build or zero process exit code does not establish E2E success.

## Make commands automatable

Expose a typed headless entry point returning a structured result, or emit an
unambiguous success or failure marker. CAD command wrappers and legacy code may
catch exceptions, so the runner must detect semantic failure independently of
the process exit code.

Keep configuration and asset validation inside the AutoCAD host when behavior
depends on imported block definitions, drawing dictionaries, layouts, or other
host state. Persist enough diagnostics to explain missing, substituted, or
fallback resources.

## Produce trustworthy visual evidence

For a generation test:

1. Record model-space entity IDs before the command.
2. Run the command once on the fresh drawing copy.
3. Record entity IDs afterward and calculate the current-run difference.
4. Plot the current-run entities by temporarily hiding pre-existing model entities inside an aborting transaction.
5. Save the complete post-command drawing separately.

This isolates the visual evidence when the source already contains generated
geometry. The saved drawing remains the complete result.

For Core Console plotting, disable background plotting and file dialogs,
activate the required layout, validate plot devices, and wait for output files.
Keep PDFs print-friendly. A consuming project may generate deterministic
dark-background previews for screen inspection.

Inspect every visual for blank output, clipping, unreadable scale, and overlap.
Confirm that the report includes every expected view and links the generated
drawing.

## Rerun in the normal user environment

After the automated suite passes, rerun the user-facing workflow in the
installed full AutoCAD application under a normal user profile. Treat this run
as final acceptance for a change that will be loaded interactively.

1. Load the same standard deployment assembly exercised by Core Console.
2. Open a fresh copy of the representative drawing used by the automated run.
3. Invoke the real public command through its normal UI or command-line entry.
4. Verify command discovery, dependency loading, configuration and asset
   discovery, prompts or modeless UI, drawing mutations, and saved output.
5. Record the assembly path, AutoCAD version/profile, input drawing, command,
   observed result, and any screenshot or generated drawing used as evidence.

Report the state as `Core Console PASS / normal-user run pending` until this
acceptance run has completed. If the agent cannot control the interactive CAD
session, provide exact reproduction steps and capture the user's result.

## Diagnose failures

- Confirm the exact assemblies loaded by AutoCAD; filesystem presence does not prove discovery or loading.
- Separate host warnings from failed assertions, missing markers, nonzero exit codes, and absent artifacts.
- For overlap, determine whether the source contains prior output, verify current-run entity isolation, and confirm the command ran once.
- For missing assets, compare configured identifiers with the definitions actually loaded inside AutoCAD before changing domain logic.

## Report the result

State the loaded assemblies, input drawing, runner, semantic marker, key
assertions, artifact paths, generated entity counts, normal-user acceptance
result, and unresolved risks.
