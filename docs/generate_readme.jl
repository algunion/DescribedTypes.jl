#!/usr/bin/env julia
# Generate README.md with real, executed output from DescribedTypes.jl
#
# Run from the project root:
#   julia docs/generate_readme.jl

using Pkg
Pkg.activate(dirname(@__DIR__))

using DescribedTypes
using JSON

# ---------- helper: capture printed output ----------
function capture(f)
    buf = IOBuffer()
    f(buf)
    return String(take!(buf))
end

# ---------- Example 1: OPENAI response format ----------

struct Person_RF
    name::String
    age::Int
end

DescribedTypes.annotate(::Type{Person_RF}) = Annotation(
    name="Person",
    description="A schema for a person.",
    parameters=Dict(
        :name => Annotation(name="name", description="The name of the person", enum=["Alice", "Bob"]),
        :age => Annotation(name="age", description="The age of the person"),
    ),
)

openai_output = capture() do io
    d = schema(Person_RF, llm_adapter=OPENAI)
    print(io, JSON.json(d, 2))
end

# ---------- Example 2: OPENAI_TOOLS function calling ----------

struct Person_TC
    name::String
    age::Int
end

DescribedTypes.annotate(::Type{Person_TC}) = Annotation(
    name="get_person",
    description="Fetches information about a person.",
    parameters=Dict(
        :name => Annotation(name="name", description="The name of the person", enum=["Alice", "Bob"]),
        :age => Annotation(name="age", description="The age of the person"),
    ),
)

tools_output = capture() do io
    d = schema(Person_TC, llm_adapter=OPENAI_TOOLS)
    print(io, JSON.json(d, 2))
end

# ---------- Example 3: Optional fields ----------

struct PersonOpt
    name::String
    nickname::Union{Nothing,String}
end

DescribedTypes.annotate(::Type{PersonOpt}) = Annotation(
    name="PersonOpt",
    description="A person with an optional nickname.",
    parameters=Dict(
        :name => Annotation(name="name", description="Full name"),
        :nickname => Annotation(name="nickname", description="Optional nickname"),
    ),
)

optional_standard = capture() do io
    d = schema(PersonOpt)
    print(io, JSON.json(d, 2))
end

optional_openai = capture() do io
    d = schema(PersonOpt, llm_adapter=OPENAI)
    print(io, JSON.json(d, 2))
end

# ---------- Assemble README ----------

readme = """
# DescribedTypes

[![Build Status](https://github.com/algunion/DescribedTypes.jl/actions/workflows/CI.yml/badge.svg?branch=main)](https://github.com/algunion/DescribedTypes.jl/actions/workflows/CI.yml?query=branch%3Amain)
[![codecov](https://codecov.io/gh/algunion/DescribedTypes.jl/branch/main/graph/badge.svg)](https://codecov.io/gh/algunion/DescribedTypes.jl)
[![Stable Docs](https://img.shields.io/badge/docs-stable-blue.svg)](https://algunion.github.io/DescribedTypes.jl/stable/)
[![Dev Docs](https://img.shields.io/badge/docs-dev-blue.svg)](https://algunion.github.io/DescribedTypes.jl/dev/)

This package provides a way to annotate Julia types with descriptions, which are
then used to generate JSON Schemas compatible with LLM provider APIs (for
structured-output functionality).

OpenAI uses JSON Schema in two different places, and the package supports both:

- **`OPENAI`** — for [structured output via `response_format`](https://developers.openai.com/api/docs/guides/structured-outputs)
  (the model's direct response). Wraps the schema under a `"schema"` key.
- **`OPENAI_TOOLS`** — for [function / tool calling](https://developers.openai.com/api/docs/guides/function-calling)
  (arguments the model passes to your code). Wraps the schema under a `"parameters"` key.

## Example — Response Format (`OPENAI`)

```julia
using DescribedTypes
using JSON

struct Person
    name::String
    age::Int
end

DescribedTypes.annotate(::Type{Person}) = Annotation(
    name="Person",
    description="A schema for a person.",
    parameters=Dict(
        :name => Annotation(name="name", description="The name of the person", enum=["Alice", "Bob"]),
        :age  => Annotation(name="age", description="The age of the person")
    )
)

schema_dict = schema(Person, llm_adapter=OPENAI)
println(JSON.json(schema_dict, 2))
```

Output *(generated automatically by [`docs/generate_readme.jl`](docs/generate_readme.jl))*:
```json
$(openai_output)
```

## Example — Tool / Function Calling (`OPENAI_TOOLS`)

```julia
DescribedTypes.annotate(::Type{Person}) = Annotation(
    name="get_person",
    description="Fetches information about a person.",
    parameters=Dict(
        :name => Annotation(name="name", description="The name of the person", enum=["Alice", "Bob"]),
        :age  => Annotation(name="age", description="The age of the person")
    )
)

schema_dict = schema(Person, llm_adapter=OPENAI_TOOLS)
println(JSON.json(schema_dict, 2))
```

Output:
```json
$(tools_output)
```

## Optional Fields

Both `OPENAI` and `OPENAI_TOOLS` modes enforce that all fields are listed in
`"required"`. Optional fields (`Union{Nothing, T}`) are represented as
`["type", "null"]`, following the
[OpenAI structured-output requirement](https://developers.openai.com/api/docs/guides/structured-outputs):

> Although all fields must be required (and the model will return a value for
> each parameter), it is possible to emulate an optional parameter by using a
> union type with null.

**Standard schema** (optional field excluded from `required`):

```json
$(optional_standard)
```

**OpenAI schema** (optional field uses `["type", "null"]`):

```json
$(optional_openai)
```

---

*Output blocks in this README were generated by running `julia docs/generate_readme.jl`.*
"""

readme_path = joinpath(dirname(@__DIR__), "README.md")
write(readme_path, readme)
println("README.md written ($(filesize(readme_path)) bytes)")
