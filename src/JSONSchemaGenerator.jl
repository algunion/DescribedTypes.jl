# Adapted from DescribedTypes.jl / JSONSchemaGenerator.jl (MIT Licensed)
# Original code: https://github.com/matthijscox/JSONSchemaGenerator.jl
# Modified to use JSON.jl v1.0+ (JSON.Object) instead of StructTypes.jl + OrderedCollections

# --- Julia type → JSON type mapping ---

function _json_type(::Type)
    return :object
end
function _json_type(::Type{<:AbstractArray})
    return :array
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

# --- Union{Nothing, T} detection ---

function _is_nothing_union(::Type)
    return false
end
function _is_nothing_union(::Type{Nothing})
    return false
end
function _is_nothing_union(::Type{Union{Nothing,T}}) where {T}
    return true
end

function _get_optional_type(::Type{Union{Nothing,T}}) where {T}
    return T
end

# --- Schema generation settings ---

Base.@kwdef mutable struct SchemaSettings
    toplevel::Bool = true
    use_references::Bool = false
    reference_types::Set{DataType} = Set{DataType}()
    reference_path::String = raw"#/$defs/"
    dict_type::Type{<:AbstractDict} = JSON.Object
    llm_adapter::LLMAdapter = STANDARD
end

# --- Public API ---

"""
    schema(
        schema_type::Type;
        use_references::Bool = false,
        dict_type::Type{<:AbstractDict} = JSON.Object,
        llm_adapter::LLMAdapter = STANDARD
    )::AbstractDict{String, Any}

Generate a JSON Schema dictionary from a Julia type.

When `llm_adapter` is `OPENAI`, the schema is wrapped for the
OpenAI **response-format** structured-output API (`"schema"` key).

When `llm_adapter` is `OPENAI_TOOLS`, the schema is wrapped for
OpenAI **function / tool calling** (`"parameters"` key).

Both OpenAI modes enforce `strict: true`, `additionalProperties: false`,
and require all fields (optional fields use `["type", "null"]`).

When `use_references` is `true`, nested struct types are factored out into
`\$defs` and referenced via `\$ref`.

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
    llm_adapter::LLMAdapter=STANDARD
)::AbstractDict{String,Any}
    if use_references
        reference_types = _gather_data_types(schema_type)
    else
        reference_types = Set{DataType}()
    end
    settings = SchemaSettings(
        use_references=use_references,
        reference_types=reference_types,
        dict_type=dict_type,
        llm_adapter=llm_adapter
    )
    d = _generate_json_object(schema_type, settings)
    if settings.llm_adapter == STANDARD
        return d
    elseif settings.llm_adapter == OPENAI
        annotation = annotate(schema_type)
        return _make_dict(settings,
            "name" => getname(annotation),
            "description" => getdescription(annotation),
            "strict" => true,
            "schema" => d
        )
    elseif settings.llm_adapter == OPENAI_TOOLS
        annotation = annotate(schema_type)
        return _make_dict(settings,
            "type" => "function",
            "name" => getname(annotation),
            "description" => getdescription(annotation),
            "strict" => true,
            "parameters" => d
        )
    elseif settings.llm_adapter == GEMINI
        return d # TODO: implement GEMINI-specific wrapping
    end
end

# --- Internal helpers ---

# Helper to create a dict of the configured type from pairs
_make_dict(settings::SchemaSettings, pairs::Pair{String}...) =
    settings.dict_type{String,Any}(collect(pairs))

_make_dict(settings::SchemaSettings, pairs::AbstractVector{<:Pair}) =
    settings.dict_type{String,Any}(pairs)

function _generate_json_object(julia_type::Type, settings::SchemaSettings)
    annotation = annotate(julia_type)

    is_top_level = settings.toplevel
    if is_top_level
        settings.toplevel = false
    end

    names = fieldnames(julia_type)
    types = fieldtypes(julia_type)

    json_property_names = String[]
    required_json_property_names = String[]
    json_properties = []

    for (name, type) in zip(names, types)
        name_string = string(name)

        is_optional = _is_nothing_union(type)

        if is_optional
            type = _get_optional_type(type)
            if _is_openai_mode(settings.llm_adapter)
                push!(required_json_property_names, name_string)
            end
        else
            push!(required_json_property_names, name_string)
        end

        if settings.use_references && type in settings.reference_types
            rt = _json_reference(type, settings)
            if is_optional && _is_openai_mode(settings.llm_adapter)
                push!(json_properties, _make_dict(settings,
                    "description" => getdescription(annotation, name),
                    "anyOf" => [rt, _make_dict(settings, "type" => "null")]
                ))
            else
                rt["description"] = getdescription(annotation, name)
                push!(json_properties, rt)
            end
        else
            jt = _generate_json_type_def(type, settings)

            if _is_openai_mode(settings.llm_adapter)
                if is_optional && haskey(jt, "type")
                    jt["type"] = [jt["type"], "null"]
                end
                jt["description"] = getdescription(annotation, name)

                en = getenum(annotation, name)
                if !isnothing(en)
                    jt["enum"] = en
                end
            end

            push!(json_properties, jt)
        end
        push!(json_property_names, name_string)
    end

    d = _make_dict(settings,
        "type" => "object",
        "properties" => _make_dict(settings, json_property_names .=> json_properties),
        "required" => required_json_property_names,
    )

    if _is_openai_mode(settings.llm_adapter)
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

# --- Type definition dispatch ---

function _generate_json_type_def(julia_type::Type, settings::SchemaSettings)
    return _generate_json_type_def(Val(_json_type(julia_type)), julia_type, settings)
end

function _generate_json_type_def(::Val{:object}, julia_type::Type, settings::SchemaSettings)
    return _generate_json_object(julia_type, settings)
end

function _generate_json_type_def(::Val{:array}, julia_type::Type{<:AbstractArray}, settings::SchemaSettings)
    element_type = eltype(julia_type)
    if settings.use_references && element_type in settings.reference_types
        item_type = _json_reference(element_type, settings)
    else
        item_type = _generate_json_type_def(element_type, settings)
    end
    return _make_dict(settings,
        "type" => "array",
        "items" => item_type
    )
end

function _generate_json_type_def(::Val{:enum}, julia_type::Type, settings::SchemaSettings)
    return _make_dict(settings,
        "type" => "string",
        "enum" => string.(instances(julia_type))
    )
end

function _generate_json_type_def(::Val, julia_type::Type, settings::SchemaSettings)
    return _make_dict(settings,
        "type" => string(_json_type(julia_type))
    )
end

# --- Schema references ---

function _json_reference(julia_type::Type, settings::SchemaSettings)
    return _make_dict(settings,
        raw"$ref" => settings.reference_path * string(julia_type)
    )
end

function _generate_json_reference_types(settings::SchemaSettings)
    d = settings.dict_type{String,Any}()
    for ref_type in settings.reference_types
        d[string(ref_type)] = _generate_json_type_def(ref_type, settings)
    end
    return d
end

# --- Reference type gathering ---

function _gather_data_types(julia_type::Type)::Set{DataType}
    data_types = Set{DataType}()
    for field_type in fieldtypes(julia_type)
        _gather_data_types!(data_types, _get_type_to_gather(field_type))
    end
    return data_types
end

function _gather_data_types!(data_types::Set{DataType}, julia_type::Type)::Nothing
    if _json_type(julia_type) == :object && isstructtype(julia_type)
        push!(data_types, julia_type)
        for field_type in fieldtypes(julia_type)
            _gather_data_types!(data_types, _get_type_to_gather(field_type))
        end
    end
    return nothing
end

function _get_type_to_gather(input_type::Type)
    if _is_nothing_union(input_type)
        return _get_optional_type(input_type)
    elseif input_type <: AbstractArray
        return eltype(input_type)
    else
        return input_type
    end
end

