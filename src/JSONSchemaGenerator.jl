# Adapted from DescribedTypes.jl / JSONSchemaGenerator.jl (MIT Licensed)
# Original code: https://github.com/matthijscox/JSONSchemaGenerator.jl
# Modified to use JSON.jl v1.0+ (JSON.Object) instead of StructTypes.jl + OrderedCollections

# --- Julia type → JSON type mapping ---

function _json_type(julia_type::Type)
    julia_type isa Union && return :union
    return :object
end
function _json_type(::Type{Any})
    return :any
end
function _json_type(::Type{<:AbstractArray})
    return :array
end
function _json_type(::Type{<:AbstractSet})
    return :array
end
function _json_type(::Type{<:Tuple})
    return :tuple
end
function _json_type(::Type{<:AbstractDict})
    return :map
end
function _json_type(::Type{Bool})
    return :boolean
end
function _json_type(::Type{<:Integer})
    return :integer
end
function _json_type(::Type{<:Real})
    return :number
end
function _json_type(::Type{Nothing})
    return :null
end
function _json_type(::Type{Missing})
    return :null
end
function _json_type(::Type{<:Enum})
    return :enum
end
function _json_type(::Type{<:AbstractString})
    return :string
end
function _json_type(::Type{Symbol})
    return :string
end

# --- Nullable types: Union{Nothing,T} / Union{Missing,T} ---

_nonnull_type(julia_type::Type) = Base.nonmissingtype(Base.nonnothingtype(julia_type))

function _is_nullable(julia_type::Type)
    julia_type === Any && return false
    (Nothing <: julia_type || Missing <: julia_type) || return false
    return _nonnull_type(julia_type) !== Union{}
end

_null_value(julia_type::Type) = Nothing <: julia_type ? nothing : missing

# --- Type parameters ---

# Replace `where` parameters by their upper bounds, e.g. `Vector{T} where T<:Real` → `Vector{Real}`,
# so parametric signatures and fields such as `Vector{<:Real}` map like their bounds.
function _upper_bound_type(julia_type::UnionAll)
    bounded = try
        julia_type{julia_type.var.ub}
    catch
        return julia_type # the bound does not satisfy the other parameters, e.g. `NTuple{N,Int} where N`
    end
    return _upper_bound_type(bounded)
end
_upper_bound_type(type_var::TypeVar) = _upper_bound_type(type_var.ub)
_upper_bound_type(julia_type) = julia_type

# --- Schema generation settings ---

@kwdef mutable struct SchemaSettings
    toplevel::Bool = true
    use_references::Bool = false
    reference_types::Vector{DataType} = DataType[]
    reference_path::String = raw"#/$defs/"
    dict_type::Type{<:AbstractDict} = JSON.Object
    llm_adapter::LLMAdapter = STANDARD
    enum_duplicate_policy::Symbol = :dedupe
    inline_stack::Vector{DataType} = DataType[] # struct types being inlined, to detect recursion
end

# --- Public API ---

"""
    schema(
        schema_type::Type;
        use_references::Bool = false,
        dict_type::Type{<:AbstractDict} = JSON.Object,
        llm_adapter::LLMAdapter = STANDARD,
        enum_duplicate_policy::Symbol = :dedupe
    )::AbstractDict{String, Any}

Generate a JSON Schema dictionary from a Julia type.

When `llm_adapter` is `OPENAI`, the schema is wrapped for the
OpenAI **response-format** structured-output API (`"schema"` key).

When `llm_adapter` is `OPENAI_TOOLS`, the schema is wrapped for
OpenAI **function / tool calling** (`"parameters"` key).

Both OpenAI modes enforce `strict: true`, `additionalProperties: false`,
and require all fields (optional fields use `["type", "null"]`).

When `use_references` is `true`, nested struct types are factored out into
`\$defs` and referenced via `\$ref`. Recursive types require it.

`enum_duplicate_policy` controls how annotation enum duplicates are handled
after conversion to strings:
- `:dedupe` (default) keeps the first instance and removes repeats.
- `:error` throws an `ArgumentError` on duplicates.

# Examples
```julia
struct Person
    name::String
    age::Int
end

DescribedTypes.annotate(::Type{Person}) = DescribedTypes.Annotation(
    name="Person",
    description="A person.",
    parameters=Dict(
        :name => DescribedTypes.Annotation(name="name", description="The person's name"),
        :age  => DescribedTypes.Annotation(name="age", description="The person's age")
    )
)

# Plain JSON Schema
schema(Person)

# OpenAI response-format (uses "schema" wrapper key)
schema(Person, llm_adapter=OPENAI)

# OpenAI tool/function calling (uses "parameters" wrapper key)
schema(Person, llm_adapter=OPENAI_TOOLS)
```
"""
function schema(
    schema_type::Type;
    use_references::Bool=false,
    dict_type::Type{<:AbstractDict}=JSON.Object,
    llm_adapter::LLMAdapter=STANDARD,
    enum_duplicate_policy::Symbol=:dedupe
)::AbstractDict{String,Any}
    _validate_enum_duplicate_policy(enum_duplicate_policy)

    settings = SchemaSettings(
        use_references=use_references,
        reference_types=use_references ? _gather_data_types(schema_type) : DataType[],
        dict_type=dict_type,
        llm_adapter=llm_adapter,
        enum_duplicate_policy=enum_duplicate_policy
    )
    d = _generate_json_object(schema_type, settings)
    annotation = annotate(schema_type)
    return _wrap_schema(settings.llm_adapter, getname(annotation), getdescription(annotation), d, settings)
end

# --- Internal helpers ---

# Helper to create a dict of the configured type from pairs
function _make_dict(settings::SchemaSettings, pairs::Pair{String}...)
    d = settings.dict_type{String,Any}()
    for (key, value) in pairs
        d[key] = value
    end
    return d
end

function _validate_enum_duplicate_policy(enum_duplicate_policy::Symbol)
    if enum_duplicate_policy != :dedupe && enum_duplicate_policy != :error
        throw(ArgumentError(
            "Invalid enum_duplicate_policy=$(repr(enum_duplicate_policy)). " *
            "Expected :dedupe or :error."
        ))
    end
    return nothing
end

"""
Normalize annotation enum values for JSON output.

Converts symbols/strings to strings. Duplicate handling is controlled by
`enum_duplicate_policy`:
- `:dedupe` keeps first-seen order and removes repeats.
- `:error` throws `ArgumentError` when a duplicate is found.
"""
function _normalize_enum_values(values::AbstractVector, enum_duplicate_policy::Symbol=:dedupe)
    _validate_enum_duplicate_policy(enum_duplicate_policy)

    normalized = String[]
    seen = Set{String}()

    for value in values
        if !(value isa String || value isa Symbol)
            throw(ArgumentError(
                "Annotation enum values must be String or Symbol. Got $(typeof(value))."
            ))
        end

        value_string = string(value)
        if value_string in seen
            if enum_duplicate_policy == :error
                throw(ArgumentError(
                    "Duplicate enum value after normalization: $(repr(value_string))."
                ))
            end
            continue
        end

        push!(normalized, value_string)
        push!(seen, value_string)
    end

    return normalized
end

function _validate_annotation_fields(julia_type::Type, annotation::Annotation)
    params = annotation.parameters
    params === nothing && return nothing
    actual_fields = fieldnames(julia_type)
    annotated_fields = keys(params)
    extra = setdiff(annotated_fields, actual_fields)
    if !isempty(extra)
        throw(ArgumentError(
            "Annotation for $(julia_type) references fields that do not exist on the type: $(join(extra, ", ")). " *
            "Actual fields: $(join(actual_fields, ", "))."
        ))
    end
    return nothing
end

function _check_object_type(julia_type::Type)
    if !(julia_type isa DataType && isconcretetype(julia_type) && isstructtype(julia_type))
        throw(ArgumentError(
            "Cannot generate a JSON Schema for $(julia_type): it has no JSON mapping and is not a " *
            "concrete struct type. Use a concrete type (or a Union of concrete types) instead."
        ))
    end
    return nothing
end

# Prefix errors raised for a nested field/argument with where they happened
function _with_context(f, context::AbstractString)
    try
        return f()
    catch err
        err isa ArgumentError || rethrow()
        throw(ArgumentError("$(context): $(err.msg)"))
    end
end

function _generate_json_object(julia_type::Type, settings::SchemaSettings)
    _check_object_type(julia_type)
    if julia_type in settings.inline_stack
        throw(ArgumentError(
            "$(julia_type) is recursive and cannot be inlined. " *
            "Pass `use_references=true` to emit it under `\$defs` and reference it with `\$ref`."
        ))
    end
    annotation = annotate(julia_type)
    _validate_annotation_fields(julia_type, annotation)

    is_top_level = settings.toplevel
    if is_top_level
        settings.toplevel = false
    end
    strict = _is_openai_mode(settings.llm_adapter)

    properties = _make_dict(settings)
    required_json_property_names = String[]

    push!(settings.inline_stack, julia_type)
    for (name, field_type) in zip(fieldnames(julia_type), fieldtypes(julia_type))
        name_string = string(name)
        is_optional = _is_nullable(field_type)
        value_type = is_optional ? _nonnull_type(field_type) : field_type

        # OpenAI modes require every field, and emulate optional ones with a `null` alternative
        if strict || !is_optional
            push!(required_json_property_names, name_string)
        end

        # Descriptions and annotation enums are emitted in OpenAI modes; `$ref`s always carry a description
        is_reference = _is_reference(value_type, settings)
        description = strict || is_reference ? getdescription(annotation, name) : nothing

        properties[name_string] = _with_context("Field `$(name)` of $(julia_type)") do
            en = strict && !is_reference ? getenum(annotation, name) : nothing
            enum_values = isnothing(en) ? nothing : _normalize_enum_values(en, settings.enum_duplicate_policy)
            _property_schema(value_type, settings;
                nullable=strict && is_optional, description, enum=enum_values)
        end
    end
    pop!(settings.inline_stack)

    d = _make_dict(settings,
        "type" => "object",
        "properties" => properties,
        "required" => required_json_property_names,
    )

    if strict
        d["additionalProperties"] = false
        if !is_top_level
            d["description"] = getdescription(annotation)
        end
    end

    if is_top_level && settings.use_references
        d[raw"$defs"] = _generate_json_reference_types(settings)
    end

    return d
end

# Schema of one object property or function argument: a `$ref` or an inline definition,
# plus an optional description, an optional enum override, and optional admission of `null`.
function _property_schema(value_type, settings::SchemaSettings; nullable::Bool, description=nothing, enum=nothing)
    julia_type = _upper_bound_type(value_type)
    if _is_reference(julia_type, settings)
        # admitting `null` wraps the `$ref` in an `anyOf`, so describe the wrapper
        d = _json_reference(julia_type, settings)
        nullable && (d = _make_nullable(d, settings))
        isnothing(description) || (d["description"] = description)
        return d
    end
    d = _generate_json_type_def(julia_type, settings)
    isnothing(description) || (d["description"] = description)
    isnothing(enum) || (d["enum"] = enum)
    return nullable ? _make_nullable(d, settings) : d
end

# --- Null admission ---

_is_null_schema(d) = get(d, "type", nothing) == "null"

_with_null(type::AbstractString) = type == "null" ? type : [type, "null"]
_with_null(types::AbstractVector) = "null" in types ? types : vcat(types, "null")

# Make the schema `d` also accept JSON `null`
function _make_nullable(d::AbstractDict, settings::SchemaSettings)
    if haskey(d, "anyOf")
        any(_is_null_schema, d["anyOf"]) || push!(d["anyOf"], _make_dict(settings, "type" => "null"))
    elseif haskey(d, "type")
        d["type"] = _with_null(d["type"])
        # `enum` is checked independently of `type`, so `null` has to be one of its values too
        if haskey(d, "enum") && !(nothing in d["enum"])
            d["enum"] = vcat(collect(d["enum"]), nothing)
        end
    elseif !isempty(d) # e.g. a bare `$ref`; the empty schema already accepts `null`
        return _make_dict(settings, "anyOf" => Any[d, _make_dict(settings, "type" => "null")])
    end
    return d
end

# --- Type definition dispatch ---

function _generate_json_type_def(julia_type::Type, settings::SchemaSettings)
    bounded_type = _upper_bound_type(julia_type)
    return _generate_json_type_def(Val(_json_type(bounded_type)), bounded_type, settings)
end

function _generate_json_type_def(::Val{:object}, julia_type::Type, settings::SchemaSettings)
    return _generate_json_object(julia_type, settings)
end

function _generate_json_type_def(::Val{:array}, julia_type::Type, settings::SchemaSettings)
    return _make_dict(settings,
        "type" => "array",
        "items" => _schema_for(eltype(julia_type), settings)
    )
end

function _generate_json_type_def(::Val{:tuple}, julia_type::Type, settings::SchemaSettings)
    params = Base.unwrap_unionall(julia_type).parameters
    if length(params) == 1 && Base.isvarargtype(params[1])
        return _make_dict(settings,
            "type" => "array",
            "items" => _schema_for(Base.unwrapva(params[1]), settings)
        )
    end
    if any(Base.isvarargtype, params) || length(unique(params)) > 1
        throw(ArgumentError(
            "$(julia_type) is not supported: only homogeneous tuples (`NTuple`) map to JSON arrays. " *
            "Use a struct or a NamedTuple for heterogeneous records."
        ))
    end
    d = _make_dict(settings, "type" => "array")
    if !isempty(params)
        d["items"] = _schema_for(first(params), settings)
    end
    d["minItems"] = length(params)
    d["maxItems"] = length(params)
    return d
end

function _generate_json_type_def(::Val{:map}, julia_type::Type, settings::SchemaSettings)
    if _is_openai_mode(settings.llm_adapter)
        throw(ArgumentError(
            "$(julia_type) cannot be represented in OpenAI strict mode, which requires every object " *
            "to list its `properties` and set `additionalProperties: false`. Use a struct instead."
        ))
    end
    d = _make_dict(settings, "type" => "object")
    value_type = valtype(julia_type)
    if value_type !== Any
        d["additionalProperties"] = _schema_for(value_type, settings)
    end
    return d
end

function _generate_json_type_def(::Val{:union}, julia_type::Type, settings::SchemaSettings)
    members = Base.uniontypes(julia_type)
    nonnull_members = filter(T -> T !== Nothing && T !== Missing, members)
    isempty(nonnull_members) && return _make_dict(settings, "type" => "null")

    branches = unique!(Any[_schema_for(T, settings) for T in nonnull_members])
    d = length(branches) == 1 ? only(branches) : _make_dict(settings, "anyOf" => branches)
    return length(nonnull_members) < length(members) ? _make_nullable(d, settings) : d
end

function _generate_json_type_def(::Val{:any}, julia_type::Type, settings::SchemaSettings)
    if _is_openai_mode(settings.llm_adapter)
        throw(ArgumentError(
            "Values of type `Any` cannot be represented in OpenAI strict mode, which needs a `type` " *
            "for every schema. Add a concrete type annotation."
        ))
    end
    return _make_dict(settings) # the empty schema accepts any JSON value
end

function _generate_json_type_def(::Val{:enum}, julia_type::Type, settings::SchemaSettings)
    return _make_dict(settings,
        "type" => "string",
        "enum" => [string(instance) for instance in instances(julia_type)]
    )
end

function _generate_json_type_def(::Val, julia_type::Type, settings::SchemaSettings)
    return _make_dict(settings,
        "type" => string(_json_type(julia_type))
    )
end

# --- Schema references ---

_is_reference(julia_type, settings::SchemaSettings) =
    settings.use_references && _upper_bound_type(julia_type) in settings.reference_types

function _json_reference(julia_type::Type, settings::SchemaSettings)
    return _make_dict(settings,
        raw"$ref" => settings.reference_path * string(julia_type)
    )
end

# Schema of a nested value: a `$ref` for types factored into `$defs`, an inline definition otherwise
function _schema_for(julia_type, settings::SchemaSettings)
    bounded_type = _upper_bound_type(julia_type)
    if _is_reference(bounded_type, settings)
        return _json_reference(bounded_type, settings)
    end
    return _generate_json_type_def(bounded_type, settings)
end

function _generate_json_reference_types(settings::SchemaSettings)
    d = _make_dict(settings)
    for ref_type in settings.reference_types
        d[string(ref_type)] = _generate_json_type_def(ref_type, settings)
    end
    return d
end

# --- Reference type gathering ---

# Struct types reachable from the fields of `julia_type`, in first-seen (declaration) order
function _gather_data_types(julia_type::Type)::Vector{DataType}
    data_types = DataType[]
    for field_type in fieldtypes(julia_type)
        _gather_data_types!(data_types, field_type)
    end
    return data_types
end

function _gather_data_types!(data_types::Vector{DataType}, julia_type)::Nothing
    bounded_type = _upper_bound_type(julia_type)
    _gather_data_types!(Val(_json_type(bounded_type)), data_types, bounded_type)
    return nothing
end

function _gather_data_types!(::Val{:object}, data_types::Vector{DataType}, julia_type::Type)
    julia_type isa DataType && isconcretetype(julia_type) && isstructtype(julia_type) || return nothing
    julia_type in data_types && return nothing # already visited; also stops recursive types
    push!(data_types, julia_type)
    for field_type in fieldtypes(julia_type)
        _gather_data_types!(data_types, field_type)
    end
    return nothing
end

function _gather_data_types!(::Val{:array}, data_types::Vector{DataType}, julia_type::Type)
    return _gather_data_types!(data_types, eltype(julia_type))
end

function _gather_data_types!(::Val{:map}, data_types::Vector{DataType}, julia_type::Type)
    return _gather_data_types!(data_types, valtype(julia_type))
end

function _gather_data_types!(::Val{:union}, data_types::Vector{DataType}, julia_type::Type)
    for member in Base.uniontypes(julia_type)
        _gather_data_types!(data_types, member)
    end
    return nothing
end

function _gather_data_types!(::Val{:tuple}, data_types::Vector{DataType}, julia_type::Type)
    for param in Base.unwrap_unionall(julia_type).parameters
        _gather_data_types!(data_types, Base.unwrapva(param))
    end
    return nothing
end

_gather_data_types!(::Val, data_types::Vector{DataType}, julia_type::Type) = nothing
