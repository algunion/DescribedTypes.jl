import CodeTracking
import MacroTools

abstract type FunArg end

"""
    PositionalArg

Internal representation of an extracted positional function argument.
"""
Base.@kwdef mutable struct PositionalArg <: FunArg
    name::Symbol
    position::Int
    type::Type = Any
    required::Bool = true
    default_expr::Any = nothing
    enum::Union{Nothing,Vector} = nothing
    description::Union{Nothing,String} = nothing
    llmexclude::Bool = false
end

"""
    KeywordArg

Internal representation of an extracted keyword function argument.
"""
Base.@kwdef mutable struct KeywordArg <: FunArg
    name::Symbol
    type::Type = Any
    required::Bool = true
    default_expr::Any = nothing
    enum::Union{Nothing,Vector} = nothing
    description::Union{Nothing,String} = nothing
    llmexclude::Bool = false
end

"""
    ArgAnnotation(; name, description=nothing, enum=nothing, required=true, llmexclude=false, userprovided=false)

Annotation metadata for one function argument.
"""
struct ArgAnnotation
    name::Symbol
    description::Union{String,Nothing}
    enum::Union{Vector,Nothing}
    required::Bool
    llmexclude::Bool
    userprovided::Bool

    function ArgAnnotation(name::Symbol, description::Union{String,Nothing}, enum::Union{Vector,Nothing}, required::Bool, llmexclude::Bool, userprovided::Bool)
        if required && llmexclude
            throw(ArgumentError("Cannot have required=true and llmexclude=true for $(name)."))
        end
        if required && userprovided
            throw(ArgumentError("Cannot have required=true and userprovided=true for $(name)."))
        end
        return new(name, description, enum, required, llmexclude, userprovided)
    end
end

function ArgAnnotation(; name=Symbol(), description=nothing, enum=nothing, required=true, llmexclude=false, userprovided=false)
    return ArgAnnotation(name, description, enum, required, llmexclude, userprovided)
end

"""
    MethodAnnotation(; name, description=nothing, argsannot=Dict())

Annotation metadata for a function method.
"""
Base.@kwdef struct MethodAnnotation
    name::Symbol
    description::Union{String,Nothing} = nothing
    argsannot::Dict{Symbol,ArgAnnotation} = Dict{Symbol,ArgAnnotation}()
end

"""
    MethodSignature

Extracted signature model for one Julia function method.
"""
Base.@kwdef mutable struct MethodSignature
    name::Symbol
    description::Union{String,Nothing} = nothing
    args::Vector{FunArg}
end

isincluded(arg::FunArg) = !getfield(arg, :llmexclude)

function _method_docstring(fn::Function)
    d = try
        Base.Docs.getdoc(fn)
    catch
        nothing
    end
    if isnothing(d)
        return nothing
    end
    s = strip(string(d))
    if isempty(s) || s == "nothing"
        return nothing
    end
    return s
end

function _select_method(fn::Function, selector::Int)
    ms = collect(methods(fn))
    if selector < 1 || selector > length(ms)
        throw(ArgumentError(
            "Invalid method selector index=$(selector) for function $(nameof(fn)). " *
            "Available methods: $(length(ms))."
        ))
    end
    return ms[selector]
end

_select_method(fn::Function, selector::Method) = selector

function _select_method(fn::Function, selector::Function)
    return selector(methods(fn))
end

function _method_expr(fn::Function, method::Method)::Union{Nothing,Expr}
    types = tuple(method.sig.types[2:end]...)
    code_string = CodeTracking.code_string(fn, types)
    if isnothing(code_string)
        return nothing
    end
    return Meta.parse(code_string)
end

function _optional_positional_cutoff(fn::Function, selected::Method, positional_types::AbstractVector)
    required_count = length(positional_types)
    for method in methods(fn)
        method === selected && continue
        mt = collect(method.sig.types[2:end])
        if length(mt) <= length(positional_types) && mt == positional_types[1:length(mt)]
            required_count = min(required_count, length(mt))
        end
    end
    return required_count
end

function _runtime_keyword_args(fn::Function, selected::Method, positional_types::AbstractVector)
    keyword_args = KeywordArg[]
    seen = Set{Symbol}()
    name_prefix = "#" * string(selected.name) * "#"

    for sym in names(selected.module, all=true)
        startswith(String(sym), name_prefix) || continue
        isdefined(selected.module, sym) || continue
        candidate = getfield(selected.module, sym)
        candidate isa Function || continue

        for method in methods(candidate)
            sig_types = method.sig.types
            idx = findfirst(t -> t == typeof(fn), sig_types)
            idx === nothing && continue

            trailing_types = collect(sig_types[(idx + 1):end])
            trailing_types == positional_types || continue

            argnames = Base.method_argnames(method)
            for i in 2:(idx - 1)
                kwname = argnames[i]
                kwname == Symbol("") && continue
                kwname in seen && continue
                push!(keyword_args, KeywordArg(name=kwname, type=sig_types[i], required=false))
                push!(seen, kwname)
            end
        end
    end

    return keyword_args
end

function _extractsignature_runtime(fn::Function, method::Method, docs::Union{Nothing,String})
    positional_types = collect(method.sig.types[2:end])
    positional_names = Base.method_argnames(method)[2:end]

    required_cutoff = _optional_positional_cutoff(fn, method, positional_types)
    args = FunArg[]

    for (i, (name, arg_type)) in enumerate(zip(positional_names, positional_types))
        push!(args, PositionalArg(
            name=name,
            position=i,
            type=arg_type,
            required=i <= required_cutoff,
        ))
    end

    append!(args, _runtime_keyword_args(fn, method, positional_types))
    return MethodSignature(name=method.name, description=docs, args=args)
end

function _resolve_type(type_expr, mod::Module)::Type
    if type_expr isa Type
        return type_expr
    end
    try
        evaluated = Core.eval(mod, type_expr)
        if evaluated isa Type
            return evaluated
        end
    catch
        # Fall back to Any when we cannot reliably resolve a type expression.
    end
    return Any
end

function _extract_name_and_type(expr, mod::Module)
    if expr isa Symbol
        return expr, Any
    elseif expr isa Expr
        if expr.head == :(::)
            name_expr = expr.args[1]
            if !(name_expr isa Symbol)
                throw(ArgumentError("Unsupported argument pattern $(repr(expr))."))
            end
            return name_expr, _resolve_type(expr.args[2], mod)
        elseif expr.head == :(...)
            throw(ArgumentError("Varargs are not supported for function schema extraction."))
        end
    end
    throw(ArgumentError("Unsupported argument pattern $(repr(expr))."))
end

function _extract_positional_arg(expr, mod::Module, position::Int)::PositionalArg
    if expr isa Expr && expr.head == :kw
        name, type = _extract_name_and_type(expr.args[1], mod)
        return PositionalArg(
            name=name,
            position=position,
            type=type,
            required=false,
            default_expr=expr.args[2],
        )
    end

    name, type = _extract_name_and_type(expr, mod)
    return PositionalArg(name=name, position=position, type=type)
end

function _extract_keyword_arg(expr, mod::Module)::KeywordArg
    if expr isa Symbol
        return KeywordArg(name=expr, type=Any)
    elseif expr isa Expr
        if expr.head == :kw
            name, type = _extract_name_and_type(expr.args[1], mod)
            return KeywordArg(name=name, type=type, required=false, default_expr=expr.args[2])
        elseif expr.head == :(...)
            throw(ArgumentError("Keyword varargs (`kwargs...`) are not supported for function schema extraction."))
        end
    end
    throw(ArgumentError("Unsupported keyword argument pattern $(repr(expr))."))
end

function _extractsignature(expr::Expr, docs::Union{Nothing,String}, mod::Module)::MethodSignature
    def = MacroTools.splitdef(expr)
    args = FunArg[]

    for (position, arg_expr) in enumerate(def[:args])
        push!(args, _extract_positional_arg(arg_expr, mod, position))
    end

    for kw_expr in def[:kwargs]
        push!(args, _extract_keyword_arg(kw_expr, mod))
    end

    return MethodSignature(name=def[:name], description=docs, args=args)
end

"""
    extractsignature(fn::Function, selector::Union{Int,Method,Function}=1) -> MethodSignature

Extract a function-method signature into a schema-friendly representation.
"""
function extractsignature(fn::Function, selector::Union{Int,Method,Function}=1)::MethodSignature
    method = _select_method(fn, selector)
    expr = _method_expr(fn, method)
    docs = _method_docstring(fn)
    if isnothing(expr)
        return _extractsignature_runtime(fn, method, docs)
    end
    return _extractsignature(expr, docs, method.module)
end

"""
    annotate(::Function, ms::MethodSignature) -> MethodAnnotation

Default function annotation fallback. Override this method for custom function
metadata, similarly to `annotate(::Type)`.
"""
function annotate(::Function, ms::MethodSignature)::MethodAnnotation
    argsannot = Dict{Symbol,ArgAnnotation}()
    for arg in ms.args
        argsannot[getfield(arg, :name)] = ArgAnnotation(
            name=getfield(arg, :name),
            description="Semantic of $(getfield(arg, :name)) in the context of $(ms.name)",
            required=getfield(arg, :required),
        )
    end

    description = isnothing(ms.description) ? "Semantic of $(ms.name) in the context of function calling" : ms.description
    return MethodAnnotation(name=ms.name, description=description, argsannot=argsannot)
end

"""
    annotate!(ms::MethodSignature, ma::MethodAnnotation)

Apply method/argument annotations to an extracted method signature.

For safety, all arguments in `ms` must be present in `ma.argsannot`.
"""
function annotate!(ms::MethodSignature, ma::MethodAnnotation)
    if !isnothing(ma.description)
        ms.description = ma.description
    end

    for arg in ms.args
        arg_name = getfield(arg, :name)
        if !haskey(ma.argsannot, arg_name)
            throw(ArgumentError(
                "Method annotation does not match method signature. Missing argument: $(arg_name)"
            ))
        end

        ann = ma.argsannot[arg_name]
        arg.description = ann.description
        arg.enum = ann.enum

        if ann.required
            arg.required = true
            arg.llmexclude = false
        end
        if ann.llmexclude || ann.userprovided
            arg.llmexclude = true
            arg.required = false
        end
    end

    return ms
end

function _normalize_function_enum_values(values::AbstractVector, enum_duplicate_policy::Symbol)
    _validate_enum_duplicate_policy(enum_duplicate_policy)

    normalized = Any[]
    seen = Set{Any}()
    for value in values
        json_value = value isa Symbol ? string(value) : value
        if !(json_value isa Union{String,Number,Bool,Nothing})
            throw(ArgumentError(
                "Function enum values must be JSON scalars (String/Symbol/Number/Bool/nothing). " *
                "Got $(typeof(value))."
            ))
        end

        if json_value in seen
            if enum_duplicate_policy == :error
                throw(ArgumentError(
                    "Duplicate enum value after normalization: $(repr(json_value))."
                ))
            end
            continue
        end

        push!(normalized, json_value)
        push!(seen, json_value)
    end

    return normalized
end

function _arg_accepts_null(arg::FunArg, settings::SchemaSettings)
    arg_type = getfield(arg, :type)
    if _is_nothing_union(arg_type)
        return true
    end

    if _is_openai_mode(settings.llm_adapter) && !getfield(arg, :required)
        return true
    end

    return false
end

function _arg_schema_type(arg::FunArg)
    arg_type = getfield(arg, :type)
    if _is_nothing_union(arg_type)
        return _get_optional_type(arg_type)
    end
    return arg_type
end

function _stringify_type_with_null(current_type)
    if current_type isa String
        return [current_type, "null"]
    elseif current_type isa AbstractVector
        if !("null" in current_type)
            push!(current_type, "null")
        end
        return current_type
    end
    return current_type
end

function _generate_function_arg_schema(arg::FunArg, settings::SchemaSettings)
    arg_type = _arg_schema_type(arg)
    schema_dict = _generate_json_type_def(arg_type, settings)

    if _arg_accepts_null(arg, settings) && haskey(schema_dict, "type")
        schema_dict["type"] = _stringify_type_with_null(schema_dict["type"])
    end

    if _is_openai_mode(settings.llm_adapter)
        schema_dict["description"] = isnothing(getfield(arg, :description)) ?
            "Semantic of $(getfield(arg, :name)) in the context of function calling" :
            getfield(arg, :description)

        enum_values = getfield(arg, :enum)
        if !isnothing(enum_values)
            schema_dict["enum"] = _normalize_function_enum_values(enum_values, settings.enum_duplicate_policy)
        end
    end

    return schema_dict
end

function _generate_function_parameters_schema(ms::MethodSignature, settings::SchemaSettings)
    names = String[]
    props = Any[]
    required = String[]

    for arg in ms.args
        isincluded(arg) || continue
        push!(names, string(getfield(arg, :name)))
        push!(props, _generate_function_arg_schema(arg, settings))

        if _is_openai_mode(settings.llm_adapter)
            push!(required, string(getfield(arg, :name)))
        elseif getfield(arg, :required)
            push!(required, string(getfield(arg, :name)))
        end
    end

    d = _make_dict(settings,
        "type" => "object",
        "properties" => _make_dict(settings, names .=> props),
        "required" => required,
    )

    if _is_openai_mode(settings.llm_adapter)
        d["additionalProperties"] = false
    end

    return d
end

function _annotated_signature(fn::Function, selector::Union{Int,Method,Function}, method_annotation::Union{Nothing,MethodAnnotation})
    ms = extractsignature(fn, selector)
    ma = isnothing(method_annotation) ? annotate(fn, ms) : method_annotation
    annotate!(ms, ma)
    return ms, ma
end

"""
    schema(
        fn::Function;
        selector::Union{Int,Method,Function}=1,
        method_annotation::Union{Nothing,MethodAnnotation}=nothing,
        use_references::Bool=false,
        dict_type::Type{<:AbstractDict}=JSON.Object,
        llm_adapter::LLMAdapter=STANDARD,
        enum_duplicate_policy::Symbol=:dedupe
    )::AbstractDict{String,Any}

Generate a JSON Schema dictionary from a Julia function method.

- `selector` chooses the function method (index, `Method`, or selector function).
- `method_annotation` allows explicit naming/description/per-arg metadata.
- `llm_adapter=OPENAI_TOOLS` emits a tool/function-calling wrapper.
- `llm_adapter=OPENAI` emits a structured-output wrapper.
"""
function schema(
    fn::Function;
    selector::Union{Int,Method,Function}=1,
    method_annotation::Union{Nothing,MethodAnnotation}=nothing,
    use_references::Bool=false,
    dict_type::Type{<:AbstractDict}=JSON.Object,
    llm_adapter::LLMAdapter=STANDARD,
    enum_duplicate_policy::Symbol=:dedupe,
)::AbstractDict{String,Any}
    _validate_enum_duplicate_policy(enum_duplicate_policy)

    if use_references
        reference_types = Set{DataType}()
    else
        reference_types = Set{DataType}()
    end

    settings = SchemaSettings(
        use_references=use_references,
        reference_types=reference_types,
        dict_type=dict_type,
        llm_adapter=llm_adapter,
        enum_duplicate_policy=enum_duplicate_policy,
    )

    ms, ma = _annotated_signature(fn, selector, method_annotation)
    d = _generate_function_parameters_schema(ms, settings)

    if settings.llm_adapter == STANDARD || settings.llm_adapter == GEMINI
        return d
    elseif settings.llm_adapter == OPENAI
        return _make_dict(settings,
            "name" => string(ma.name),
            "description" => isnothing(ma.description) ? "" : ma.description,
            "strict" => true,
            "schema" => d,
        )
    elseif settings.llm_adapter == OPENAI_TOOLS
        return _make_dict(settings,
            "type" => "function",
            "name" => string(ma.name),
            "description" => isnothing(ma.description) ? "" : ma.description,
            "strict" => true,
            "parameters" => d,
        )
    end

    return d
end

function _raw_arguments_dict(arguments::AbstractDict)
    if haskey(arguments, "arguments")
        inner = arguments["arguments"]
        if inner isa AbstractString
            parsed = JSON.parse(inner)
            parsed isa AbstractDict || throw(ArgumentError("Expected `arguments` JSON string to decode to an object."))
            return parsed
        elseif inner isa AbstractDict
            return inner
        end
        throw(ArgumentError("`arguments` must be an object or a JSON string object."))
    end
    return arguments
end

function _raw_arguments_dict(arguments::AbstractString)
    parsed = JSON.parse(arguments)
    parsed isa AbstractDict || throw(ArgumentError("Expected JSON arguments to decode to an object."))
    return _raw_arguments_dict(parsed)
end

function _lookup_argument(raw_arguments::AbstractDict, name::Symbol)
    name_string = string(name)
    if haskey(raw_arguments, name_string)
        return true, raw_arguments[name_string]
    elseif haskey(raw_arguments, name)
        return true, raw_arguments[name]
    end
    return false, nothing
end

function _coerce_to_type(value, target_type::Type, arg_name::Symbol)
    if value === nothing
        if target_type === Any || _is_nothing_union(target_type)
            return nothing
        end
        throw(ArgumentError("Argument `$(arg_name)` does not accept null values for type $(target_type)."))
    end

    if target_type === Any
        return value
    end

    if _is_nothing_union(target_type)
        inner = _get_optional_type(target_type)
        return _coerce_to_type(value, inner, arg_name)
    end

    if target_type == Symbol
        value isa Symbol && return value
        value isa AbstractString && return Symbol(value)
        throw(ArgumentError("Argument `$(arg_name)` expects Symbol-compatible value, got $(typeof(value))."))
    elseif target_type <: AbstractString
        value isa AbstractString || throw(ArgumentError("Argument `$(arg_name)` expects string, got $(typeof(value))."))
        return String(value)
    elseif target_type <: Bool
        value isa Bool || throw(ArgumentError("Argument `$(arg_name)` expects Bool, got $(typeof(value))."))
        return value
    elseif target_type <: Integer
        value isa Integer || throw(ArgumentError("Argument `$(arg_name)` expects Integer, got $(typeof(value))."))
        return convert(target_type, value)
    elseif target_type <: AbstractFloat
        value isa Real || throw(ArgumentError("Argument `$(arg_name)` expects Real, got $(typeof(value))."))
        return convert(target_type, value)
    elseif target_type <: Enum
        if value isa target_type
            return value
        elseif value isa AbstractString
            for enum_instance in instances(target_type)
                if string(enum_instance) == value
                    return enum_instance
                end
            end
        elseif value isa Integer
            try
                return target_type(value)
            catch
            end
        end
        throw(ArgumentError(
            "Argument `$(arg_name)` expects enum $(target_type). " *
            "Supported inputs are enum names or integer enum values."
        ))
    elseif target_type <: AbstractArray
        value isa AbstractVector || throw(ArgumentError("Argument `$(arg_name)` expects array, got $(typeof(value))."))
        element_type = eltype(target_type)
        return [_coerce_to_type(v, element_type, arg_name) for v in value]
    elseif target_type <: AbstractDict
        value isa AbstractDict || throw(ArgumentError("Argument `$(arg_name)` expects object/dict, got $(typeof(value))."))
        return value
    elseif isstructtype(target_type)
        value isa AbstractDict || throw(ArgumentError("Argument `$(arg_name)` expects object for $(target_type), got $(typeof(value))."))
        return _dict_to_struct(value, target_type, arg_name)
    end

    return value
end

function _dict_to_struct(value::AbstractDict, target_type::Type, arg_name::Symbol)
    names = fieldnames(target_type)
    types = fieldtypes(target_type)
    field_values = Any[]

    for (field_name, field_type) in zip(names, types)
        present, raw = _lookup_argument(value, field_name)
        if !present
            if _is_nothing_union(field_type)
                push!(field_values, nothing)
                continue
            end
            throw(ArgumentError(
                "Argument `$(arg_name)` object for $(target_type) is missing required field `$(field_name)`."
            ))
        end
        push!(field_values, _coerce_to_type(raw, field_type, field_name))
    end

    return target_type(field_values...)
end

function _check_enum_membership(value, enum_values::Vector, arg_name::Symbol)
    normalized_enum = _normalize_function_enum_values(enum_values, :dedupe)
    probe_value = value isa Symbol ? string(value) : value
    if !(probe_value in normalized_enum)
        throw(ArgumentError(
            "Argument `$(arg_name)` value $(repr(value)) is not in enum $(repr(normalized_enum))."
        ))
    end
end

"""
    callfunction(
        fn::Function,
        arguments::Union{AbstractString,AbstractDict};
        selector::Union{Int,Method,Function}=1,
        method_annotation::Union{Nothing,MethodAnnotation}=nothing,
    )

Call a Julia function from JSON-like arguments using extracted method metadata.

- `arguments` can be a JSON string or dictionary-like object.
- Supports OpenAI-style `{ "arguments": "{...}" }` and `{ "arguments": {...} }`.
- Validates required/extra keys, coerces JSON values into Julia argument types,
  and invokes `fn` with positional and keyword arguments.
"""
function callfunction(
    fn::Function,
    arguments::Union{AbstractString,AbstractDict};
    selector::Union{Int,Method,Function}=1,
    method_annotation::Union{Nothing,MethodAnnotation}=nothing,
)
    raw_arguments = _raw_arguments_dict(arguments)
    ms, _ = _annotated_signature(fn, selector, method_annotation)

    included_names = Set{String}(string(getfield(arg, :name)) for arg in ms.args if isincluded(arg))
    for raw_key in keys(raw_arguments)
        k = raw_key isa Symbol ? string(raw_key) : String(raw_key)
        if !(k in included_names)
            throw(ArgumentError("Unexpected argument key `$(k)` for function $(ms.name)."))
        end
    end

    positional_args = sort(
        [arg for arg in ms.args if arg isa PositionalArg && isincluded(arg)],
        by=arg -> getfield(arg, :position)
    )
    keyword_args = [arg for arg in ms.args if arg isa KeywordArg && isincluded(arg)]

    positional_values = Any[]
    seen_optional_gap = false

    for arg in positional_args
        arg_name = getfield(arg, :name)
        present, raw_value = _lookup_argument(raw_arguments, arg_name)

        if !present
            if getfield(arg, :required)
                throw(ArgumentError("Missing required argument `$(arg_name)` for function $(ms.name)."))
            end
            seen_optional_gap = true
            continue
        end

        if seen_optional_gap
            throw(ArgumentError(
                "Cannot supply positional argument `$(arg_name)` after omitting an earlier optional positional argument."
            ))
        end

        # In OpenAI-style strict schemas we encode optional/defaulted args as nullable.
        # A null payload means "use the Julia default", so we omit it from the call.
        if raw_value === nothing && !getfield(arg, :required)
            seen_optional_gap = true
            continue
        end

        enum_values = getfield(arg, :enum)
        if !isnothing(enum_values)
            _check_enum_membership(raw_value, enum_values, arg_name)
        end

        push!(positional_values, _coerce_to_type(raw_value, getfield(arg, :type), arg_name))
    end

    keyword_values = Pair{Symbol,Any}[]
    for arg in keyword_args
        arg_name = getfield(arg, :name)
        present, raw_value = _lookup_argument(raw_arguments, arg_name)

        if !present
            if getfield(arg, :required)
                throw(ArgumentError("Missing required keyword argument `$(arg_name)` for function $(ms.name)."))
            end
            continue
        end

        if raw_value === nothing && !getfield(arg, :required)
            continue
        end

        enum_values = getfield(arg, :enum)
        if !isnothing(enum_values)
            _check_enum_membership(raw_value, enum_values, arg_name)
        end

        push!(keyword_values, arg_name => _coerce_to_type(raw_value, getfield(arg, :type), arg_name))
    end

    return fn(positional_values...; keyword_values...)
end
