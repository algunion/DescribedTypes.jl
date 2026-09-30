import CodeTracking
import MacroTools

abstract type FunArg end

"""
    PositionalArg

Internal representation of an extracted positional function argument.
"""
@kwdef mutable struct PositionalArg <: FunArg
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
@kwdef mutable struct KeywordArg <: FunArg
    name::Symbol
    type::Type = Any
    required::Bool = true
    default_expr::Any = nothing
    enum::Union{Nothing,Vector} = nothing
    description::Union{Nothing,String} = nothing
    llmexclude::Bool = false
end

"""
    ArgAnnotation(; name, description=nothing, enum=nothing, llmexclude=false, userprovided=false, required=!(llmexclude || userprovided))

Annotation metadata for one function argument.

`required` defaults to `true`, except for arguments hidden from the model
(`llmexclude=true` or `userprovided=true`), which default to `false`.
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

function ArgAnnotation(; name=Symbol(), description=nothing, enum=nothing, llmexclude=false, userprovided=false, required=!(llmexclude || userprovided))
    return ArgAnnotation(name, description, enum, required, llmexclude, userprovided)
end

"""
    MethodAnnotation(; name, description=nothing, argsannot=Dict())

Annotation metadata for a function method.
"""
@kwdef struct MethodAnnotation
    name::Symbol
    description::Union{String,Nothing} = nothing
    argsannot::Dict{Symbol,ArgAnnotation} = Dict{Symbol,ArgAnnotation}()
end

"""
    MethodSignature

Extracted signature model for one Julia function method.
"""
@kwdef mutable struct MethodSignature
    name::Symbol
    description::Union{String,Nothing} = nothing
    args::Vector{FunArg}
end

isincluded(arg::FunArg) = !arg.llmexclude

# Docstrings of `fn` whose signature covers `method`; generic docstrings (attached without
# a signature) are the fallback. `Base.Docs.getdoc` is a customization hook, not a lookup.
function _method_docstring(fn::Function, method::Method)
    binding = Base.Docs.Binding(parentmodule(fn), nameof(fn))
    argtypes = Base.tuple_type_tail(method.sig)
    matching = String[]
    generic = String[]
    for mod in Base.Docs.modules
        docs = Base.Docs.meta(mod; autoinit=false)
        (isnothing(docs) || !haskey(docs, binding)) && continue
        multidoc = docs[binding]
        for docsig in multidoc.order
            text = strip(_docstr_text(multidoc.docs[docsig]))
            isempty(text) && continue
            if argtypes <: docsig
                push!(matching, text)
            elseif docsig === Union{}
                push!(generic, text)
            end
        end
    end
    texts = isempty(matching) ? generic : matching
    return isempty(texts) ? nothing : join(texts, "\n\n")
end

function _docstr_text(docstr::Base.Docs.DocStr)
    if isempty(docstr.text) # documented with a non-string object, e.g. `@doc md"..."`
        return isnothing(docstr.object) ? "" : string(docstr.object)
    end
    return join(string(part) for part in docstr.text)
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

# Source of `method`'s definition with wrapping macro calls (`@inline`, `@eval`, ...) peeled off;
# `nothing` when the source is unavailable or is not a function definition.
function _method_expr(method::Method)::Union{Nothing,Expr}
    definition = CodeTracking.definition(String, method)
    isnothing(definition) && return nothing
    expr = _unwrap_macrocalls(Meta.parse(first(definition); raise=false))
    return expr isa Expr && MacroTools.isdef(expr) ? expr : nothing
end

function _unwrap_macrocalls(expr)
    if expr isa Expr && expr.head === :macrocall && !isempty(expr.args)
        return _unwrap_macrocalls(last(expr.args))
    end
    return expr
end

# Types in `method`'s signature (including the function itself) with `where` parameters bounded
function _signature_types(method::Method)
    sig = method.sig
    return Any[_upper_bound_type(Base.rewrap_unionall(T, sig)) for T in Base.unwrap_unionall(sig).types]
end

function _optional_positional_cutoff(fn::Function, selected::Method, positional_types::AbstractVector)
    required_count = length(positional_types)
    for method in methods(fn)
        method === selected && continue
        mt = _signature_types(method)[2:end]
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
            sig_types = _signature_types(method)
            idx = findfirst(t -> t == typeof(fn), sig_types)
            idx === nothing && continue

            trailing_types = sig_types[(idx + 1):end]
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
    positional_types = _signature_types(method)[2:end]
    if any(Base.isvarargtype, positional_types)
        throw(ArgumentError("Varargs are not supported for function schema extraction."))
    end
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

# `where` parameters mapped to their upper-bound expressions, e.g. `T<:Real` gives `:T => :Real`
function _where_bounds(where_params)
    bounds = Dict{Symbol,Any}()
    for param in where_params
        bound = _where_bound(param)
        isnothing(bound) && continue
        name, upper = bound
        bounds[name] = _substitute_bounds(upper, bounds) # later parameters may refer to earlier ones
    end
    return bounds
end

_where_bound(param::Symbol) = (param, :Any)
function _where_bound(param::Expr)
    param.head === :<: && return (param.args[1], param.args[2])
    param.head === :>: && return (param.args[1], :Any)
    param.head === :comparison && return (param.args[3], param.args[5]) # L <: T <: U
    return nothing
end
_where_bound(param) = nothing

_substitute_bounds(expr, bounds::AbstractDict) =
    MacroTools.postwalk(x -> x isa Symbol ? get(bounds, x, x) : x, expr)

function _resolve_type(type_expr, mod::Module, bounds::AbstractDict)::Type
    if type_expr isa Type
        return _upper_bound_type(type_expr)
    end
    try
        evaluated = Core.eval(mod, _substitute_bounds(type_expr, bounds))
        if evaluated isa Type
            return _upper_bound_type(evaluated)
        end
    catch
        # Fall back to Any when we cannot reliably resolve a type expression.
    end
    return Any
end

function _extract_name_and_type(expr, mod::Module, bounds::AbstractDict)
    if expr isa Symbol
        return expr, Any
    elseif expr isa Expr
        if expr.head == :(::) && length(expr.args) == 2
            name_expr = expr.args[1]
            if !(name_expr isa Symbol)
                throw(ArgumentError("Unsupported argument pattern $(repr(expr))."))
            end
            return name_expr, _resolve_type(expr.args[2], mod, bounds)
        elseif expr.head == :(...)
            throw(ArgumentError("Varargs are not supported for function schema extraction."))
        end
    end
    throw(ArgumentError("Unsupported argument pattern $(repr(expr))."))
end

function _extract_positional_arg(expr, mod::Module, bounds::AbstractDict, position::Int)::PositionalArg
    if expr isa Expr && expr.head == :kw
        name, type = _extract_name_and_type(expr.args[1], mod, bounds)
        return PositionalArg(
            name=name,
            position=position,
            type=type,
            required=false,
            default_expr=expr.args[2],
        )
    end

    name, type = _extract_name_and_type(expr, mod, bounds)
    return PositionalArg(name=name, position=position, type=type)
end

function _extract_keyword_arg(expr, mod::Module, bounds::AbstractDict)::KeywordArg
    if expr isa Expr && expr.head == :kw
        name, type = _extract_name_and_type(expr.args[1], mod, bounds)
        return KeywordArg(name=name, type=type, required=false, default_expr=expr.args[2])
    elseif expr isa Expr && expr.head == :(...)
        throw(ArgumentError("Keyword varargs (`kwargs...`) are not supported for function schema extraction."))
    end
    # a keyword without a default value (`k` or `k::T`) is required
    name, type = _extract_name_and_type(expr, mod, bounds)
    return KeywordArg(name=name, type=type)
end

function _extractsignature(expr::Expr, method::Method, docs::Union{Nothing,String})::MethodSignature
    def = MacroTools.splitdef(expr)
    mod = method.module
    bounds = _where_bounds(get(def, :whereparams, ()))
    args = FunArg[]

    for (position, arg_expr) in enumerate(def[:args])
        push!(args, _extract_positional_arg(arg_expr, mod, bounds, position))
    end

    for kw_expr in def[:kwargs]
        push!(args, _extract_keyword_arg(kw_expr, mod, bounds))
    end

    return MethodSignature(name=method.name, description=docs, args=args)
end

"""
    extractsignature(fn::Function, selector::Union{Int,Method,Function}=1) -> MethodSignature

Extract a function-method signature into a schema-friendly representation.

The method's docstring, if any, becomes the signature description.
"""
function extractsignature(fn::Function, selector::Union{Int,Method,Function}=1)::MethodSignature
    method = _select_method(fn, selector)
    docs = _method_docstring(fn, method)
    expr = _method_expr(method)
    if isnothing(expr)
        return _extractsignature_runtime(fn, method, docs)
    end
    return _extractsignature(expr, method, docs)
end

"""
    annotate(::Function, ms::MethodSignature) -> MethodAnnotation

Default function annotation fallback. Override this method for custom function
metadata, similarly to `annotate(::Type)`.
"""
function annotate(::Function, ms::MethodSignature)::MethodAnnotation
    argsannot = Dict{Symbol,ArgAnnotation}()
    for arg in ms.args
        argsannot[arg.name] = ArgAnnotation(
            name=arg.name,
            description="Semantic of $(arg.name) in the context of $(ms.name)",
            required=arg.required,
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
        if !haskey(ma.argsannot, arg.name)
            throw(ArgumentError(
                "Method annotation does not match method signature. Missing argument: $(arg.name)"
            ))
        end

        ann = ma.argsannot[arg.name]
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
    # In OpenAI strict modes, optional/defaulted arguments are sent as `null` to mean "use the default"
    return _is_nullable(arg.type) || (_is_openai_mode(settings.llm_adapter) && !arg.required)
end

_arg_schema_type(arg::FunArg) = _is_nullable(arg.type) ? _nonnull_type(arg.type) : arg.type

function _generate_function_arg_schema(arg::FunArg, settings::SchemaSettings)
    strict = _is_openai_mode(settings.llm_adapter)
    description = strict ? something(arg.description, "Semantic of $(arg.name) in the context of function calling") : nothing
    enum_values = strict && !isnothing(arg.enum) ?
        _normalize_function_enum_values(arg.enum, settings.enum_duplicate_policy) : nothing
    return _property_schema(_arg_schema_type(arg), settings;
        nullable=_arg_accepts_null(arg, settings), description, enum=enum_values)
end

function _generate_function_parameters_schema(ms::MethodSignature, settings::SchemaSettings)
    properties = _make_dict(settings)
    required = String[]

    for arg in ms.args
        isincluded(arg) || continue
        name = string(arg.name)
        properties[name] = _with_context("Argument `$(arg.name)` of $(ms.name)") do
            _generate_function_arg_schema(arg, settings)
        end

        if _is_openai_mode(settings.llm_adapter) || arg.required
            push!(required, name)
        end
    end

    d = _make_dict(settings,
        "type" => "object",
        "properties" => properties,
        "required" => required,
    )

    if _is_openai_mode(settings.llm_adapter)
        d["additionalProperties"] = false
    end

    if settings.use_references
        d[raw"$defs"] = _generate_json_reference_types(settings)
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
- `use_references=true` factors struct-typed arguments into `\$defs`.
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

    ms, ma = _annotated_signature(fn, selector, method_annotation)

    reference_types = DataType[]
    if use_references
        for arg in ms.args
            isincluded(arg) && _gather_data_types!(reference_types, arg.type)
        end
    end

    settings = SchemaSettings(
        toplevel=false, # the parameters object is the root, so struct arguments are nested objects
        use_references=use_references,
        reference_types=reference_types,
        dict_type=dict_type,
        llm_adapter=llm_adapter,
        enum_duplicate_policy=enum_duplicate_policy,
    )

    d = _generate_function_parameters_schema(ms, settings)
    return _wrap_schema(settings.llm_adapter, string(ma.name), something(ma.description, ""), d, settings)
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
    target_type = _upper_bound_type(target_type)

    if value === nothing
        if target_type === Any || Nothing <: target_type || Missing <: target_type
            return _null_value(target_type)
        end
        throw(ArgumentError("Argument `$(arg_name)` does not accept null values for type $(target_type)."))
    end

    if target_type === Any
        return value
    end

    if _is_nullable(target_type)
        return _coerce_to_type(value, _nonnull_type(target_type), arg_name)
    end

    if target_type isa Union
        return _coerce_to_union(value, target_type, arg_name)
    elseif target_type == Symbol
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
    elseif target_type <: Number
        value isa Number || throw(ArgumentError("Argument `$(arg_name)` expects number, got $(typeof(value))."))
        return convert(target_type, value)
    elseif target_type <: AbstractArray
        value isa AbstractVector || throw(ArgumentError("Argument `$(arg_name)` expects array, got $(typeof(value))."))
        element_type = eltype(target_type)
        # typed comprehension: the element type must not depend on inference (empty arrays)
        return element_type[_coerce_to_type(v, element_type, arg_name) for v in value]
    elseif target_type <: AbstractSet
        value isa AbstractVector || throw(ArgumentError("Argument `$(arg_name)` expects array, got $(typeof(value))."))
        element_type = eltype(target_type)
        return convert(target_type, Set{element_type}(_coerce_to_type(v, element_type, arg_name) for v in value))
    elseif target_type <: Tuple
        return _coerce_to_tuple(value, target_type, arg_name)
    elseif target_type <: AbstractDict
        value isa AbstractDict || throw(ArgumentError("Argument `$(arg_name)` expects object/dict, got $(typeof(value))."))
        return _coerce_to_dict(value, target_type, arg_name)
    elseif isstructtype(target_type)
        value isa AbstractDict || throw(ArgumentError("Argument `$(arg_name)` expects object for $(target_type), got $(typeof(value))."))
        return _dict_to_struct(value, target_type, arg_name)
    end

    return value
end

function _coerce_to_union(value, target_type::Union, arg_name::Symbol)
    value isa target_type && return value
    for member in Base.uniontypes(target_type)
        try
            return _coerce_to_type(value, member, arg_name)
        catch err
            err isa ArgumentError || rethrow()
        end
    end
    throw(ArgumentError("Argument `$(arg_name)` value $(repr(value)) does not match any type in $(target_type)."))
end

function _coerce_to_tuple(value, target_type::Type, arg_name::Symbol)
    value isa AbstractVector || throw(ArgumentError("Argument `$(arg_name)` expects array, got $(typeof(value))."))
    params = Base.unwrap_unionall(target_type).parameters
    if length(params) == 1 && Base.isvarargtype(params[1])
        element_types = fill(_upper_bound_type(Base.unwrapva(params[1])), length(value))
    else
        if length(value) != length(params)
            throw(ArgumentError("Argument `$(arg_name)` expects $(length(params)) elements, got $(length(value))."))
        end
        element_types = collect(params)
    end
    return Tuple(_coerce_to_type(v, T, arg_name) for (v, T) in zip(value, element_types))
end

function _coerce_to_dict(value::AbstractDict, target_type::Type, arg_name::Symbol)
    key_type, value_type = keytype(target_type), valtype(target_type)
    result = Dict{key_type,value_type}()
    for (k, v) in value
        result[_coerce_to_type(k, key_type, arg_name)] = _coerce_to_type(v, value_type, arg_name)
    end
    return convert(target_type, result)
end

function _dict_to_struct(value::AbstractDict, target_type::Type, arg_name::Symbol)
    names = fieldnames(target_type)
    types = fieldtypes(target_type)
    field_values = Any[]

    for (field_name, field_type) in zip(names, types)
        present, raw = _lookup_argument(value, field_name)
        if !present
            if _is_nullable(field_type)
                push!(field_values, _null_value(field_type))
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

# Check annotation enum membership, then coerce the JSON value to the argument's Julia type
function _coerce_argument(raw_value, arg::FunArg)
    # `null` is governed by the argument type (nullable or not), not by the enum
    if !isnothing(arg.enum) && raw_value !== nothing
        _check_enum_membership(raw_value, arg.enum, arg.name)
    end
    return _coerce_to_type(raw_value, arg.type, arg.name)
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

    included_names = Set{String}(string(arg.name) for arg in ms.args if isincluded(arg))
    for raw_key in keys(raw_arguments)
        k = raw_key isa Symbol ? string(raw_key) : String(raw_key)
        if !(k in included_names)
            throw(ArgumentError("Unexpected argument key `$(k)` for function $(ms.name)."))
        end
    end

    positional_args = sort(
        [arg for arg in ms.args if arg isa PositionalArg && isincluded(arg)],
        by=arg -> arg.position
    )
    keyword_args = [arg for arg in ms.args if arg isa KeywordArg && isincluded(arg)]

    positional_values = Any[]
    seen_optional_gap = false

    for arg in positional_args
        present, raw_value = _lookup_argument(raw_arguments, arg.name)

        if !present
            if arg.required
                throw(ArgumentError("Missing required argument `$(arg.name)` for function $(ms.name)."))
            end
            seen_optional_gap = true
            continue
        end

        if seen_optional_gap
            throw(ArgumentError(
                "Cannot supply positional argument `$(arg.name)` after omitting an earlier optional positional argument."
            ))
        end

        # In OpenAI-style strict schemas we encode optional/defaulted args as nullable.
        # A null payload means "use the Julia default", so we omit it from the call.
        if raw_value === nothing && !arg.required
            seen_optional_gap = true
            continue
        end

        push!(positional_values, _coerce_argument(raw_value, arg))
    end

    keyword_values = Pair{Symbol,Any}[]
    for arg in keyword_args
        present, raw_value = _lookup_argument(raw_arguments, arg.name)

        if !present
            if arg.required
                throw(ArgumentError("Missing required keyword argument `$(arg.name)` for function $(ms.name)."))
            end
            continue
        end

        if raw_value === nothing && !arg.required
            continue
        end

        push!(keyword_values, arg.name => _coerce_argument(raw_value, arg))
    end

    return fn(positional_values...; keyword_values...)
end
