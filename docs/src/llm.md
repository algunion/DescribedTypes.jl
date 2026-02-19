# LLM-Optimized Reference

> Compressed single-page reference for LLM code-generation tools.
> Contains all public signatures, types, and usage patterns.

## Package

```julia
using DescribedTypes
# Exports: schema, Annotation, annotate, LLMAdapter, STANDARD, OPENAI, OPENAI_TOOLS, GEMINI,
#          ArgAnnotation, MethodAnnotation, MethodSignature, PositionalArg, KeywordArg,
#          extractsignature, annotate!, callfunction
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

### Function-annotation types

```julia
struct ArgAnnotation
    name::Symbol
    description::Union{String,Nothing}
    enum::Union{Vector,Nothing}
    required::Bool
    llmexclude::Bool
    userprovided::Bool
end

Base.@kwdef struct MethodAnnotation
    name::Symbol
    description::Union{String,Nothing} = nothing
    argsannot::Dict{Symbol,ArgAnnotation} = Dict{Symbol,ArgAnnotation}()
end

Base.@kwdef mutable struct MethodSignature
    name::Symbol
    description::Union{String,Nothing} = nothing
    args::Vector{FunArg}
end
```

Use these to annotate extracted function methods before schema generation.

## Functions

### `annotate`

```julia
annotate(::Type{T}) -> Annotation
annotate(::Function, ::MethodSignature) -> MethodAnnotation
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
For functions, default fallback emits a `MethodAnnotation` with generic
argument descriptions and inferred required/default behavior.

### `schema`

```julia
schema(
    schema_type::Type;
    use_references::Bool = false,
    dict_type::Type{<:AbstractDict} = JSON.Object,
    llm_adapter::LLMAdapter = STANDARD,
    enum_duplicate_policy::Symbol = :dedupe
) -> AbstractDict{String, Any}

schema(
    fn::Function;
    selector::Union{Int,Method,Function}=1,
    method_annotation::Union{Nothing,MethodAnnotation}=nothing,
    use_references::Bool=false,
    dict_type::Type{<:AbstractDict}=JSON.Object,
    llm_adapter::LLMAdapter=STANDARD,
    enum_duplicate_policy::Symbol=:dedupe
) -> AbstractDict{String, Any}
```

Generates a JSON Schema dictionary from a Julia type or a Julia function
method.

For function schemas:
- `selector` chooses which method to extract (index, `Method`, or selector fn).
- `method_annotation` overrides/augments metadata without defining `annotate`.

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

### `extractsignature`

```julia
extractsignature(fn::Function, selector::Union{Int,Method,Function}=1) -> MethodSignature
```

Extract one Julia function method into a schema-friendly signature model.

### `annotate!`

```julia
annotate!(ms::MethodSignature, ma::MethodAnnotation)
```

Apply a `MethodAnnotation` to an extracted signature.

### `callfunction`

```julia
callfunction(
    fn::Function,
    arguments::Union{AbstractString,AbstractDict};
    selector::Union{Int,Method,Function}=1,
    method_annotation::Union{Nothing,MethodAnnotation}=nothing,
)
```

Validate/coerce JSON-style arguments and call the Julia function method.

Supports OpenAI-style wrappers:
- `{ "arguments": "{...json...}" }`
- `{ "arguments": {...object...} }`

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

### Function tool schema and invocation

```julia
function weather(city::String, days::Int=3; unit::String="celsius")
    return (; city, days, unit)
end

DescribedTypes.annotate(::typeof(weather), ms::MethodSignature) = MethodAnnotation(
    name=:weather_tool,
    description="Weather lookup tool.",
    argsannot=Dict(
        :city => ArgAnnotation(name=:city, description="City name", required=true),
        :days => ArgAnnotation(name=:days, description="Forecast horizon", required=false),
        :unit => ArgAnnotation(name=:unit, description="Temperature unit", enum=["celsius", "fahrenheit"], required=false),
    ),
)

tool_schema = schema(weather, llm_adapter=OPENAI_TOOLS)
result = callfunction(weather, Dict("city" => "Paris", "unit" => "fahrenheit"))
```

### Overloaded methods with `selector`

```julia
function weather_multi(city::String)
    return (; city, mode="quick")
end

function weather_multi(city::String, days::Int)
    return (; city, days, mode="full")
end

sel = first(methods(weather_multi, (String, Int)))
schema(weather_multi, selector=sel, llm_adapter=OPENAI_TOOLS)
callfunction(weather_multi, Dict("city" => "Paris", "days" => 2), selector=sel)
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

## Current limits (functions)

- Varargs (`args...`) and keyword splats (`kwargs...`) are unsupported.
- Runtime fallback extraction may not fully reconstruct required keyword-only
  semantics when source is unavailable to `CodeTracking`.
