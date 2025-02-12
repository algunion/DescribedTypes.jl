@enum LLMAdapter STANDARD OPENAI GEMINI

@kwdef struct Annotation
    name::String
    description::String = ""
    markdown::String = ""
    enum::Union{Nothing,Vector{String}} = nothing
    parameters::Union{Nothing,OrderedDict{Symbol,Annotation}} = nothing
end

Annotation(name) = Annotation(name=name, description="Semantic of $name in the context of the schema")

getname(annotation::Annotation) = getfield(annotation, :name)

getdescription(annotation::Annotation) = getfield(annotation, :description)

function getdescription(annotation::Annotation, field::Symbol)
    isnothing(getfield(annotation, :parameters)) && return "Semantic of $field in the context of the schema"
    if haskey(getfield(annotation, :parameters), field)
        return getdescription(getfield(annotation, :parameters)[field])
    else
        return "Semantic of $field in the context of the schema"
    end
end

getenum(annotation::Annotation) = getfield(annotation, :enum)
function getenum(annotation::Annotation, field::Symbol)
    isnothing(getfield(annotation, :parameters)) && return nothing
    if haskey(getfield(annotation, :parameters), field)
        return getenum(getfield(annotation, :parameters)[field])
    else
        return nothing
    end
end


function annotate end

annotate(::Type{T}) where {T} = Annotation(string(T))

# @doc Annotation(name="test", description="test", markdown="test", parameters=OrderedDict("test" => Annotation(name="test", description="test")))
# struct TestStruct
#     a::Int
#     b::String
# end

