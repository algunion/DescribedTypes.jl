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

**Output**:
```json
{
  "name": "Person",
  "description": "A schema for a person.",
  "strict": true,
  "schema": {
    "type": "object",
    "properties": {
      "name": {
        "type": "string",
        "description": "The name of the person",
        "enum": [
          "Alice",
          "Bob"
        ]
      },
      "age": {
        "type": "integer",
        "description": "The age of the person"
      }
    },
    "required": [
      "name",
      "age"
    ],
    "additionalProperties": false
  }
}
```

## Example — Tool / Function Calling (`OPENAI_TOOLS`)

```julia
using DescribedTypes
using JSON

struct Person
    name::String
    age::Int
end

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

**Output**:
```json
{
  "type": "function",
  "name": "get_person",
  "description": "Fetches information about a person.",
  "strict": true,
  "parameters": {
    "type": "object",
    "properties": {
      "name": {
        "type": "string",
        "description": "The name of the person",
        "enum": [
          "Alice",
          "Bob"
        ]
      },
      "age": {
        "type": "integer",
        "description": "The age of the person"
      }
    },
    "required": [
      "name",
      "age"
    ],
    "additionalProperties": false
  }
}
```

## Optional Fields

Both `OPENAI` and `OPENAI_TOOLS` modes enforce that all fields are listed in
`"required"`. Optional fields (`Union{Nothing, T}`) are represented as
`["type", "null"]`, following the
[OpenAI structured-output requirement](https://developers.openai.com/api/docs/guides/structured-outputs):

> Although all fields must be required (and the model will return a value for
> each parameter), it is possible to emulate an optional parameter by using a
> union type with null.
