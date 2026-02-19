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

## Function Method Tools (`function -> schema`, `JSON -> call`)

The package also supports direct function-method extraction and invocation:

```julia
# Weather lookup helper.
function weather(city::String, days::Int=3; unit::String="celsius", include_humidity::Bool=false)
    return (; city, days, unit, include_humidity)
end

DescribedTypes.annotate(::typeof(weather), ms::MethodSignature) = MethodAnnotation(
    name=:weather_tool,
    description="Weather lookup tool.",
    argsannot=Dict(
        :city => ArgAnnotation(name=:city, description="City name", required=true),
        :days => ArgAnnotation(name=:days, description="Forecast horizon", required=false),
        :unit => ArgAnnotation(name=:unit, description="Temperature unit", enum=["celsius", "fahrenheit"], required=false),
        :include_humidity => ArgAnnotation(name=:include_humidity, description="Include humidity signal", required=false),
    ),
)

tool_schema = schema(weather, llm_adapter=OPENAI_TOOLS)
result = callfunction(weather, Dict("city" => "Paris", "unit" => "fahrenheit"))
```

Tool schema output:
```json
{
  "type": "function",
  "name": "weather_tool",
  "description": "Weather lookup tool.",
  "strict": true,
  "parameters": {
    "type": "object",
    "properties": {
      "city": {
        "type": "string",
        "description": "City name"
      },
      "days": {
        "type": [
          "integer",
          "null"
        ],
        "description": "Forecast horizon"
      },
      "unit": {
        "type": [
          "string",
          "null"
        ],
        "description": "Temperature unit",
        "enum": [
          "celsius",
          "fahrenheit"
        ]
      },
      "include_humidity": {
        "type": [
          "boolean",
          "null"
        ],
        "description": "Include humidity signal"
      }
    },
    "required": [
      "city",
      "days",
      "unit",
      "include_humidity"
    ],
    "additionalProperties": false
  }
}
```

Function-call output:
```json
{
  "city": "Paris",
  "days": 3,
  "unit": "fahrenheit",
  "include_humidity": false
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

**Standard schema** (optional field excluded from `required`):

```json
{
  "type": "object",
  "properties": {
    "name": {
      "type": "string"
    },
    "nickname": {
      "type": "string"
    }
  },
  "required": [
    "name"
  ]
}
```

**OpenAI schema** (optional field uses `["type", "null"]`):

```json
{
  "name": "PersonOpt",
  "description": "A person with an optional nickname.",
  "strict": true,
  "schema": {
    "type": "object",
    "properties": {
      "name": {
        "type": "string",
        "description": "Full name"
      },
      "nickname": {
        "type": [
          "string",
          "null"
        ],
        "description": "Optional nickname"
      }
    },
    "required": [
      "name",
      "nickname"
    ],
    "additionalProperties": false
  }
}
```

## Symbol Enums and Duplicate Handling

Field-level annotation enums accept both `String` and `Symbol` values. Schema
output still emits strings (JSON-compatible).

```julia
struct PersonSymbolEnum
    name::String
end

DescribedTypes.annotate(::Type{PersonSymbolEnum}) = Annotation(
    name="PersonSymbolEnum",
    description="A person with symbol-based enum annotations.",
    parameters=Dict(
        :name => Annotation(name="name", description="The name", enum=[:Alice, "Alice", :Bob]),
    ),
)

# Default duplicate policy is :dedupe
schema(PersonSymbolEnum, llm_adapter=OPENAI)
```

Output (`:dedupe`, default):
```json
{
  "name": "PersonSymbolEnum",
  "description": "A person with symbol-based enum annotations.",
  "strict": true,
  "schema": {
    "type": "object",
    "properties": {
      "name": {
        "type": "string",
        "description": "The name",
        "enum": [
          "Alice",
          "Bob"
        ]
      }
    },
    "required": [
      "name"
    ],
    "additionalProperties": false
  }
}
```

To enforce strict duplicate handling, pass `enum_duplicate_policy=:error`:

```julia
schema(PersonSymbolEnum, llm_adapter=OPENAI, enum_duplicate_policy=:error)
```

Raises:
```text
ArgumentError("Duplicate enum value after normalization: \"Alice\".")
```

---

*Output blocks in this README were generated by running `julia docs/generate_readme.jl`.*
