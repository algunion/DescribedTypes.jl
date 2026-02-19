"""
    LLMAdapter

Enum selecting the LLM-provider schema format.

- `STANDARD`     — plain JSON Schema
- `OPENAI`       — wrapped for OpenAI structured-output response format (`"schema"` key)
- `OPENAI_TOOLS` — wrapped for OpenAI function/tool calling (`"parameters"` key)
- `GEMINI`       — (placeholder) Google Gemini format
"""
@enum LLMAdapter STANDARD OPENAI OPENAI_TOOLS GEMINI

"""
    _is_openai_mode(adapter::LLMAdapter) -> Bool

Return `true` for any OpenAI-flavoured adapter (`OPENAI` or `OPENAI_TOOLS`).
Used internally so that schema-generation rules shared by both modes are written once.
"""
_is_openai_mode(adapter::LLMAdapter) = adapter == OPENAI || adapter == OPENAI_TOOLS

"""
    Annotation(; name, description="", markdown="", enum=nothing, parameters=nothing)

Metadata attached to a Julia type (or one of its fields) for JSON Schema generation.

# Fields
- `name::String` — display name used in the schema
- `description::String` — human-readable description
- `markdown::String` — optional Markdown documentation
- `enum::Union{Nothing,Vector{Union{String,Symbol}}}` — allowable enum values (if any)
- `parameters::Union{Nothing,Dict{Symbol,Annotation}}` — per-field annotations
"""
Base.@kwdef struct Annotation
    name::String
    description::String = ""
    markdown::String = ""
    enum::Union{Nothing,Vector{Union{String,Symbol}}} = nothing
    parameters::Union{Nothing,Dict{Symbol,Annotation}} = nothing
end

Annotation(name::String) = Annotation(; name, description="Semantic of $name in the context of the schema")

getname(a::Annotation) = a.name

getdescription(a::Annotation) = a.description

function getdescription(a::Annotation, field::Symbol)
    params = a.parameters
    if params === nothing || !haskey(params, field)
        return "Semantic of $field in the context of the schema"
    end
    return getdescription(params[field])
end

getenum(a::Annotation) = a.enum

function getenum(a::Annotation, field::Symbol)
    params = a.parameters
    (params === nothing || !haskey(params, field)) && return nothing
    return getenum(params[field])
end

"""
    annotate(::Type{T}) -> Annotation

Return the [`Annotation`](@ref) for type `T`.

Override this method to attach descriptions and field metadata to your types:

```julia
DescribedTypes.annotate(::Type{MyType}) = DescribedTypes.Annotation(
    name = "MyType",
    description = "A short description.",
    parameters = Dict(
        :field1 => DescribedTypes.Annotation(name="field1", description="..."),
    )
)
```
"""
function annotate end

annotate(::Type{T}) where {T} = Annotation(string(T))
