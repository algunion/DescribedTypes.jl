module DescribedTypes

import JSON

export schema, Annotation, annotate
export LLMAdapter, STANDARD, OPENAI, OPENAI_TOOLS, GEMINI

include("LLMAdapters.jl")
include("JSONSchemaGenerator.jl")

end
