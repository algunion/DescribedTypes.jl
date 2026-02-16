# instructions.md

## Epistemic Stance

This codebase follows an experimental and falsifiable development model.

Assume initial interpretations are wrong.

Do not invest in long speculative reasoning chains about APIs, types,
performance, or semantics. Instead:

-   Formulate a minimal hypothesis.
-   Encode it as a small, runnable experiment.
-   Execute and observe.
-   Only proceed with behavior that survives testing.

Prefer empirical verification over narrative confidence.

If an assumption cannot be tested quickly, isolate it and mark it
explicitly as a hypothesis.

------------------------------------------------------------------------

## Julia-First Operational Mode

Julia is a live laboratory. Use it.

Before designing abstractions:

-   Prototype behavior in a short script.
-   Inspect types with `typeof`, `fieldtypes`, `methods`,
    `@code_warntype`.
-   Benchmark with `BenchmarkTools`.
-   Validate allocations and inference.

Never assume type stability. Demonstrate it.

If performance is relevant, produce a micro-benchmark before optimizing
or refactoring.

------------------------------------------------------------------------

## Micro-Experiment Pattern

When introducing new logic:

1.  Write the smallest self-contained function that expresses the
    hypothesis.
2.  Write a short test or assertion validating expected behavior.
3.  If performance matters, write a benchmark snippet.
4.  Only then integrate into larger structures.

Example pattern:

``` julia
# Hypothesis: this transformation is type-stable and allocation-free

f(x::Vector{Float64}) = sum(x) / length(x)

using Test
@test f([1.0, 2.0, 3.0]) == 2.0

using BenchmarkTools
@btime f($([1.0, 2.0, 3.0]))
```

If the hypothesis fails, revise the design before expanding scope.

------------------------------------------------------------------------

## Helper Modules and Experimental Scaffolding

You may create:

-   Temporary helper modules.
-   Macros for instrumentation.
-   Debug utilities for structural introspection.
-   Script-level experiment files.

Experimental scaffolding is preferred over speculative reasoning.

Remove or isolate scaffolding once knowledge is stabilized.

------------------------------------------------------------------------

## Type Discipline

-   Prefer concrete field types in structs.
-   Avoid `Any` unless justified.
-   Validate type stability with `@code_warntype`.
-   If dynamic behavior is required, demonstrate correctness with
    explicit tests.

Never rely on assumed dispatch behavior. Inspect `methods(f)` if needed.

------------------------------------------------------------------------

## Performance Claims

Performance statements must be supported by:

-   A reproducible `@btime` benchmark.
-   Clear input sizes.
-   Mention of allocations if relevant.

No unmeasured optimization narratives.

------------------------------------------------------------------------

## API and External Systems

When integrating with external APIs:

-   Create a minimal request experiment.
-   Validate response shape.
-   Encode the response schema as a small struct or validation test.
-   Only then build abstraction layers.

Do not assume documentation matches reality. Probe it.

------------------------------------------------------------------------

## Refactoring Rule

Refactor only after:

-   Behavior is verified.
-   Tests pass.
-   Performance characteristics are understood.

Do not refactor speculative designs.

------------------------------------------------------------------------

## Failure Handling

When encountering ambiguity:

-   Reduce to a minimal reproducible snippet.
-   Isolate the failing behavior.
-   Print intermediate types and values.
-   Prefer clarity over cleverness.

------------------------------------------------------------------------

## General Constraints

-   Use modern Julia idioms.
-   Prefer multiple dispatch over conditional branching.
-   Keep functions small and composable.
-   Avoid premature abstraction.
-   Document invariants explicitly.

Every nontrivial assumption should be testable.

------------------------------------------------------------------------

This is development as controlled conjecture and refutation. Code
survives by resisting falsification.

Speculation is cheap. Experiments are decisive.

## Grounding Reporting and Syncrhonization

When learning from external sources, create a `grounding/` directory at the project root. For each truth source, create a markdown file with:
- A summary of key insights.
- A mapping of relevant concepts to project constructs.

Keep these files up to date as the project evolves. They serve as a shared reference for the team and help maintain alignment with external realities.