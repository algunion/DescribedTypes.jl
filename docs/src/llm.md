# LLM-Optimized Reference

> Compressed single-page reference for LLM code-generation tools.
> Contains all public signatures, types, and usage patterns.

## Package

```julia
using DescribedTypes
# Exports: schema, Annotation, annotate, LLMAdapter, STANDARD, OPENAI, OPENAI_TOOLS, GEMINI
```

## Types

### `LLMAdapter`

```julia
@enum LLMAdapter STANDARD OPENAI OPENAI_TOOLS GEMINI
```

Selects the LLM-provider schema format:
- `STANDARD` — plain JSON Schema (no wrapping).
- `OPENAI` — OpenAI structured-output response format; wraps schema under `"schema"` key, sets `strict: true`, `additionalProperties: false`, all fields required (optional → `["type", "null"]`).
- `OPENAI_TOOLS` — OpenAI function/tool calling; wraps schema under `"parameters"` key with `"type": "function"`, same strict rules as `OPENAI`.
- `GEMINI` — placeholder for Google Gemini format.

### `Annotation`

```julia
Base.@kwdef struct Annotation
    name::String
    description::String = ""
    markdown::String = ""
    enum::Union{Nothing, Vector{Union{String,Symbol}}} = nothing
    parameters::Union{Nothing, Dict{Symbol, Annotation}} = nothing
end

Annotation(name::String)  # convenience; auto-generates description
```

Metadata for a Julia type or field used during JSON Schema generation.

- `name` — display name in schema.
- `description` — human-readable description.
- `markdown` — optional Markdown docs.
- `enum` — constrained values (`String` and/or `Symbol`) for schema enums.
- `parameters` — per-field `Annotation` keyed by field name (`Symbol`).

## Functions

### `annotate`

```julia
annotate(::Type{T}) -> Annotation
```

Override per type to attach metadata:

```julia
DescribedTypes.annotate(::Type{MyStruct}) = Annotation(
    name = "MyStruct",
    description = "Short description.",
    parameters = Dict(
        :field1 => Annotation(name="field1", description="Field 1 description"),
        :field2 => Annotation(name="field2", description="Field 2 description", enum=["a", "b"]),
    ),
)
```

Default fallback uses `string(T)` as name with generic field descriptions.

### `schema`

```julia
schema(
    schema_type::Type;
    use_references::Bool = false,
    dict_type::Type{<:AbstractDict} = JSON.Object,
    llm_adapter::LLMAdapter = STANDARD,
    enum_duplicate_policy::Symbol = :dedupe
) -> AbstractDict{String, Any}
```

Generates a JSON Schema dictionary from a Julia type.

**Keyword arguments:**
- `use_references` — when `true`, nested struct types are factored into `$defs` and referenced via `$ref`.
- `dict_type` — dictionary type for the output (default `JSON.Object` for ordered keys).
- `llm_adapter` — schema format selector (see `LLMAdapter`).
- `enum_duplicate_policy` — enum duplicate handling after string normalization:
  - `:dedupe` (default): keep first-seen value, remove duplicates.
  - `:error`: throw `ArgumentError` on duplicates.

**Return shape by adapter:**

| `llm_adapter`  | Top-level keys                                                                     |
| :------------- | :--------------------------------------------------------------------------------- |
| `STANDARD`     | `type`, `properties`, `required` [, `$defs`]                                       |
| `OPENAI`       | `name`, `description`, `strict`, `schema` → {schema object}                        |
| `OPENAI_TOOLS` | `type="function"`, `name`, `description`, `strict`, `parameters` → {schema object} |

## Patterns

### Define a type and annotate it

```julia
struct Weather
    location::String
    temperature::Float64
    unit::String
end

DescribedTypes.annotate(::Type{Weather}) = Annotation(
    name = "Weather",
    description = "Current weather observation.",
    parameters = Dict(
        :location    => Annotation(name="location", description="City name"),
        :temperature => Annotation(name="temperature", description="Temperature value"),
        :unit        => Annotation(name="unit", description="Unit of measurement",
                                   enum=["celsius", "fahrenheit"]),
    ),
)
```

### Generate schemas

```julia
using JSON

# Plain JSON Schema
schema(Weather)

# OpenAI structured output (response_format)
schema(Weather, llm_adapter=OPENAI)

# OpenAI tool/function calling
schema(Weather, llm_adapter=OPENAI_TOOLS)

# With $defs for nested types
schema(Weather, use_references=true)
```

### Optional fields

Use `Union{Nothing, T}`. In `STANDARD` mode the field is not in `required`. In `OPENAI`/`OPENAI_TOOLS` mode the field stays required but its type becomes `["type", "null"]`.

```julia
struct Query
    text::String
    max_results::Union{Nothing, Int}
end
```

### Nested structs

```julia
struct Address
    street::String
    city::String
end

struct Person
    name::String
    address::Address
end
```

Nested structs are inlined by default. Pass `use_references=true` to factor them into `$defs`.

### Enums

Julia `@enum` types map to `"type": "string"` with `"enum"` values automatically. Field-level enums can also be set via the `enum` kwarg in `Annotation`.

### Serializing to JSON string

```julia
import JSON
JSON.json(schema(MyType), 2)        # pretty-printed
JSON.json(schema(MyType, llm_adapter=OPENAI))  # compact
```

## Supported Julia type mappings

| Julia type                  | JSON Schema type  |
| :-------------------------- | :---------------- |
| `String` / `AbstractString` | `string`          |
| `Bool`                      | `boolean`         |
| `<:Integer`                 | `integer`         |
| `<:Real`                    | `number`          |
| `Nothing` / `Missing`       | `null`            |
| `<:AbstractArray`           | `array`           |
| `<:Enum`                    | `string` + `enum` |
| Any other `struct`          | `object`          |
