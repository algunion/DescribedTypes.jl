# DescribedTypes.jl

*Annotate Julia types with descriptions and generate JSON Schemas for LLM provider APIs.*

## Overview

DescribedTypes.jl lets you attach human-readable descriptions to Julia `struct` types and their fields, then automatically produces JSON Schema dictionaries compatible with LLM structured-output APIs.

Supported adapters:

| Adapter        | Use case                                                                                                    | Wrapper key    |
| :------------- | :---------------------------------------------------------------------------------------------------------- | :------------- |
| `STANDARD`     | Plain JSON Schema (no wrapping)                                                                             | —              |
| `OPENAI`       | [Structured output via `response_format`](https://developers.openai.com/api/docs/guides/structured-outputs) | `"schema"`     |
| `OPENAI_TOOLS` | [Function / tool calling](https://developers.openai.com/api/docs/guides/function-calling)                   | `"parameters"` |
| `GEMINI`       | Google Gemini *(placeholder)*                                                                               | —              |

## Installation

```julia
using Pkg
Pkg.add("DescribedTypes")
```

Or in the Pkg REPL:

```
pkg> add DescribedTypes
```

## Quick Start

```@example quickstart
using DescribedTypes
using JSON

struct Person
    name::String
    age::Int
end

DescribedTypes.annotate(::Type{Person}) = Annotation(
    name="Person",
    description="A person.",
    parameters=Dict(
        :name => Annotation(name="name", description="The person's name", enum=["Alice", "Bob"]),
        :age  => Annotation(name="age", description="The person's age"),
    ),
)

# OpenAI structured-output format
schema_dict = schema(Person, llm_adapter=OPENAI)
print(JSON.json(schema_dict, 2))
```

See the [Guide](@ref guide) for more detailed usage and examples.
