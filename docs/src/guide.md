# [Guide](@id guide)

## Annotating Types

Every type that you want to generate a schema for needs an [`annotate`](@ref) method
that returns an [`Annotation`](@ref). The annotation carries a name, description,
and per-field metadata.

```julia
using DescribedTypes

struct Weather
    location::String
    temperature::Float64
    unit::String
end

DescribedTypes.annotate(::Type{Weather}) = Annotation(
    name="Weather",
    description="Current weather observation.",
    parameters=Dict(
        :location    => Annotation(name="location", description="City name"),
        :temperature => Annotation(name="temperature", description="Temperature value"),
        :unit        => Annotation(name="unit", description="Unit of measurement", enum=["celsius", "fahrenheit"]),
    ),
)
```

If you don't define `annotate` for a type, a default annotation is generated
using the type name, with generic field descriptions.

## Generating Schemas

Use [`schema`](@ref) to produce a JSON Schema dictionary:

```julia
using JSON

# Plain JSON Schema
d = schema(Weather)
println(JSON.json(d, 2))

# OpenAI response-format wrapper
d = schema(Weather, llm_adapter=OPENAI)

# OpenAI function/tool-calling wrapper
d = schema(Weather, llm_adapter=OPENAI_TOOLS)
```

## Optional Fields

Fields typed as `Union{Nothing, T}` are treated as optional:

- In `STANDARD` mode they are omitted from the `"required"` array.
- In `OPENAI` / `OPENAI_TOOLS` modes all fields remain required (per OpenAI spec),
  but optional fields use `["type", "null"]` to allow a `null` value.

```julia
struct Query
    text::String
    max_tokens::Union{Nothing, Int}
end

DescribedTypes.annotate(::Type{Query}) = Annotation(
    name="Query",
    description="A search query.",
    parameters=Dict(
        :text       => Annotation(name="text", description="The query string"),
        :max_tokens => Annotation(name="max_tokens", description="Optional token limit"),
    ),
)
```

## Enum Fields

There are two ways to represent enums:

1. **Julia `@enum` types** — automatically serialised to their string representations:

```julia
@enum Color red green blue

struct Palette
    primary::Color
end
```

2. **String fields with enum annotations** — constrain allowed values via the `enum` keyword in [`Annotation`](@ref):

```julia
struct Shirt
    color::String
end

DescribedTypes.annotate(::Type{Shirt}) = Annotation(
    name="Shirt",
    description="A shirt.",
    parameters=Dict(
        :color => Annotation(name="color", description="Shirt color", enum=["red", "green", "blue"]),
    ),
)
```

!!! note
    The `enum` keyword in annotations only takes effect in OpenAI modes
    (`OPENAI` / `OPENAI_TOOLS`). In `STANDARD` mode it is ignored.

## Nested Types

Nested structs are expanded inline by default:

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

### Schema References

For deeply nested or repeated types, pass `use_references=true` to factor
shared types into `$defs` and reference them via `$ref`:

```julia
d = schema(Person, use_references=true)
```

## Custom Dict Type

By default schemas use `JSON.Object` (preserves insertion order). You can
switch to `Dict` if order doesn't matter:

```julia
d = schema(Person, dict_type=Dict)
```
