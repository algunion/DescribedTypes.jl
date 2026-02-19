module DescribedTypes

import JSON

export schema, Annotation, annotate
export LLMAdapter, STANDARD, OPENAI, OPENAI_TOOLS, GEMINI
export ArgAnnotation, MethodAnnotation, MethodSignature, PositionalArg, KeywordArg
export extractsignature, annotate!, callfunction

include("LLMAdapters.jl")
include("JSONSchemaGenerator.jl")
include("FunctionSchemaGenerator.jl")

end
