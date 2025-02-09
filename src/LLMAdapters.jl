"""
LLMAdapters.jl - Julia module for handling different LLM adapters for generating structured outputs.
"""
module LLMAdapters

# const _OPENAI_SY::Symbol = :openai_structured_output
# const OPENAI_TYPE::DataType = Val{_OPENAI_SY}
# const OPENAI::Val{_OPENAI_SY} = Val(_OPENAI_SY)

# const OPENAI::Symbol = :openai_structured_output
# const GEMINI::Symbol = :gemini_structured_output

@enum LLMAdapter STANDARD OPENAI GEMINI

export LLMAdapter

end