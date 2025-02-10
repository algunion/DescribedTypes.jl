"""
LLMAdapters.jl - Julia module for handling different LLM adapters for generating structured outputs.
"""
module LLMAdapters
import OrderedCollections: OrderedDict
# const _OPENAI_SY::Symbol = :openai_structured_output
# const OPENAI_TYPE::DataType = Val{_OPENAI_SY}
# const OPENAI::Val{_OPENAI_SY} = Val(_OPENAI_SY)

# const OPENAI::Symbol = :openai_structured_output
# const GEMINI::Symbol = :gemini_structured_output

@enum LLMAdapter STANDARD OPENAI GEMINI

@kwdef struct Annotation
    name::String
    description::String
    markdown::String = ""
    parameters::OrderedDict{String,Any}
end

export LLMAdapter, Annotation

@doc Annotation("da", "de", "", OrderedDict())
struct TestStruct
    x::Int
end

@doc Annotation("dad", "ded", "", OrderedDict())
TestStruct() = TestStruct(0)


end