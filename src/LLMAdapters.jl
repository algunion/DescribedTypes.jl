module LLMAdapters

const _OPENAI_SY::Symbol = :openai_structured_output
const OPENAI_TYPE::DataType = Val{_OPENAI_SY}
const OPENAI::Val{_OPENAI_SY} = Val(_OPENAI_SY)

end