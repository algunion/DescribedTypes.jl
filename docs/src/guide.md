# [Guide](@id guide)

## Annotating Types

Every type that you want to generate a schema for needs an [`annotate`](@ref) method
that returns an [`Annotation`](@ref). The annotation carries a name, description,
and per-field metadata.

```@example guide
using DescribedTypes
using JSON

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
nothing # hide
```

If you don't define `annotate` for a type, a default annotation is generated
using the type name, with generic field descriptions.

## Generating Schemas

Use [`schema`](@ref) to produce a JSON Schema dictionary.

**Plain JSON Schema (`STANDARD`):**

```@example guide
d = schema(Weather)
print(JSON.json(d, 2))
```

**OpenAI response-format wrapper (`OPENAI`):**

```@example guide
d = schema(Weather, llm_adapter=OPENAI)
print(JSON.json(d, 2))
```

**OpenAI function/tool-calling wrapper (`OPENAI_TOOLS`):**

```@example guide
d = schema(Weather, llm_adapter=OPENAI_TOOLS)
print(JSON.json(d, 2))
```

## Optional Fields

Fields typed as `Union{Nothing, T}` are treated as optional:

- In `STANDARD` mode they are omitted from the `"required"` array.
- In `OPENAI` / `OPENAI_TOOLS` modes all fields remain required (per OpenAI spec),
  but optional fields use `["type", "null"]` to allow a `null` value.

```@example guide
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
nothing # hide
```

**Standard schema (optional fields omitted from `required`):**

```@example guide
print(JSON.json(schema(Query), 2))
```

**OpenAI schema (optional fields use `["type", "null"]`):**

```@example guide
print(JSON.json(schema(Query, llm_adapter=OPENAI), 2))
```

## Enum Fields

There are two ways to represent enums:

### 1. Julia `@enum` types

Automatically serialised to their string representations:

```@example guide
@enum Color red green blue

struct Palette
    primary::Color
end

print(JSON.json(schema(Palette), 2))
```

You can also annotate the enum field with a description — the enum values are
still inferred from the Julia type, so you don't need to repeat them:

```@example guide
DescribedTypes.annotate(::Type{Palette}) = Annotation(
    name="Palette",
    description="A color palette.",
    parameters=Dict(
        :primary => Annotation(name="primary", description="The primary color"),
    ),
)

print(JSON.json(schema(Palette, llm_adapter=OPENAI), 2))
```

### 2. String fields with enum annotations

Constrain allowed values via the `enum` keyword in [`Annotation`](@ref):

```@example guide
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

print(JSON.json(schema(Shirt, llm_adapter=OPENAI), 2))
```

!!! note
    The `enum` keyword in annotations only takes effect in OpenAI modes
    (`OPENAI` / `OPENAI_TOOLS`). In `STANDARD` mode it is ignored.

You can also use symbols in the annotation enum values:

```@example guide
DescribedTypes.annotate(::Type{Shirt}) = Annotation(
    name="Shirt",
    description="A shirt.",
    parameters=Dict(
        :color => Annotation(name="color", description="Shirt color", enum=[:red, :green, :blue]),
    ),
)

print(JSON.json(schema(Shirt, llm_adapter=OPENAI), 2))
```

Duplicate handling is configurable when generating schema:

```@example guide
# default: :dedupe
schema(Shirt, llm_adapter=OPENAI)

# strict: error on duplicates after normalization
# schema(Shirt, llm_adapter=OPENAI, enum_duplicate_policy=:error)
```

## Nested Types

Nested structs are expanded inline by default:

```@example guide
struct Address
    street::String
    city::String
end

struct Person
    name::String
    address::Address
end

print(JSON.json(schema(Person), 2))
```

### Schema References

For deeply nested or repeated types, pass `use_references=true` to factor
shared types into `$defs` and reference them via `$ref`:

```@example guide
print(JSON.json(schema(Person, use_references=true), 2))
```

## Custom Dict Type

By default schemas use `JSON.Object` (preserves insertion order). You can
switch to `Dict` if order doesn't matter:

```@example guide
d = schema(Person, dict_type=Dict)
typeof(d)
```
