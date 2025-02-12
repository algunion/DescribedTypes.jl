# DescribedTypes

[![Build Status](https://github.com/algunion/DescribedTypes.jl/actions/workflows/CI.yml/badge.svg?branch=main)](https://github.com/algunion/DescribedTypes.jl/actions/workflows/CI.yml?query=branch%3Amain)

This package attempts to provide a way to annotate types with descriptions which in turn can be used to generate JSON Schemas compatible with LLM providers APIs (for structured output functionality).

Future versions of this package will provide specialized macros for increased ergonomics and ease of use. The current version emulates the `StructTypes.jl` functionality (see test file for examples).

## Example

```julia
using DescribedTypes
using OrderedCollections: OrderedDict
using StructTypes
using JSON3

struct Person
    name::String
    age::Int
end

StructTypes.StructType(::Type{Person}) = StructTypes.Struct()

DescribedTypes.annotate(::Type{Person}) = DescribedTypes.Annotation(
    name="Person",
    description="A schema for a person.",
    parameters=OrderedDict(
        :name => DescribedTypes.Annotation(name="name", description="The name of the person"),
        :age => DescribedTypes.Annotation(name="age", description="The age of the person")
    )
)

schema_dict = DescribedTypes.schema(Person, llm_adapter=DescribedTypes.OPENAI)
JSON3.pretty(schema_dict)
```

This will generate a JSON schema for the `Person` type with annotations for the fields.

## Advanced Example

```julia
using DescribedTypes
using OrderedCollections: OrderedDict
using StructTypes
using JSON3

struct OptionalFieldSchema
    int::Int
    optional::Union{Nothing, String}
end

StructTypes.StructType(::Type{OptionalFieldSchema}) = StructTypes.Struct()
StructTypes.omitempties(::Type{OptionalFieldSchema}) = (:optional,)
DescribedTypes.annotate(::Type{OptionalFieldSchema}) = DescribedTypes.Annotation(
    name="OptionalFieldSchema",
    description="A schema containing an optional field.",
    markdown="Optional field",
    parameters=OrderedDict(
        :int => DescribedTypes.Annotation(name="int", description="An integer field"),
        :optional => DescribedTypes.Annotation(name="optional", description="An optional string field")
    )
)

schema_dict = DescribedTypes.schema(OptionalFieldSchema, llm_adapter=DescribedTypes.OPENAI)
JSON3.pretty(schema_dict)
```

This will generate a JSON schema for the `OptionalFieldSchema` type, including handling for optional fields in a way that is [compatible with OpenAI's LLM API](https://platform.openai.com/docs/guides/structured-outputs/supported-schemas?format=without-parse#all-fields-must-be-required):
> Although all fields must be required (and the model will return a value for each parameter), it is possible to emulate an optional parameter by using a union type with null.


