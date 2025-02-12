# Adapted/changed the MIT Licensed code from: https://github.com/matthijscox/JSONSchemaGenerator.jl


# by default we assume the type is a custom type, which should be a JSON object
_json_type(::Type{<:Any}) = :object
#_json_type(::Type{<:AbstractDict}) = :object

_json_type(::Type{<:AbstractArray}) = :array
_json_type(::Type{Bool}) = :boolean
_json_type(::Type{<:Integer}) = :integer
_json_type(::Type{<:Real}) = :number
_json_type(::Type{Nothing}) = :null
_json_type(::Type{Missing}) = :null
_json_type(::Type{<:Enum}) = :enum
_json_type(::Type{<:AbstractString}) = :string

_is_nothing_union(::Type) = false
_is_nothing_union(::Type{Nothing}) = false
_is_nothing_union(::Type{Union{Nothing,T}}) where {T} = true

_get_optional_type(::Type{Union{Nothing,T}}) where {T} = T

Base.@kwdef mutable struct SchemaSettings
    toplevel::Bool = true # will be set to false by top level schema object
    use_references::Bool = false # create schema references instead of nesting types
    reference_types::Set{DataType}
    reference_path = "#/\$defs/"
    dict_type::Type{<:AbstractDict} = OrderedDict
    llm_adapter::LLMAdapter = STANDARD
end

"""
```julia
schema(
    schema_type::Type;
    use_references::Bool = false,
    dict_type::Type{<:AbstractDict} = OrderedCollections.OrderedDict
    llm_adapter::LLMAdapter = STANDARD
)::AbstractDict{String, Any}
```

Generate a JSONSchema in the form of a dictionary.

# Example
```julia
using JSONSchemaGenerator, StructTypes

struct OptionalFieldSchema
    int::Int
    optional::Union{Nothing, String}
end
StructTypes.StructType(::Type{OptionalFieldSchema}) = StructTypes.Struct()
StructTypes.omitempties(::Type{OptionalFieldSchema}) = (:optional,)

struct NestedFieldSchema
    int::Int
    field::OptionalFieldSchema
    vector::Vector{OptionalFieldSchema}
end
StructTypes.StructType(::Type{NestedFieldSchema}) = StructTypes.Struct()

schema_dict = JSONSchemaGenerator.schema(NestedFieldSchema)
```
"""
function schema(
    schema_type::Type;
    use_references::Bool=false,
    dict_type::Type{<:AbstractDict}=OrderedDict,
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

        if settings.llm_adapter == OPENAI
            result = OrderedDict(
                "name" => getname(annotation),
                "description" => getdescription(annotation),
                "strict" => true,
                "parameters" => d
            )
            return result
        elseif settings.llm_adapter == GEMINI
            return d # TO DO: implement GEMINI
        end
    else
        return d # TO DO: implement GEMINI
    end

end

# by default we do not resolve nested objects into reference definitions
function _generate_json_object(julia_type::Type, settings::SchemaSettings)
    isstruct = isstructtype(julia_type)
    annotation = annotate(julia_type)

    is_top_level = settings.toplevel

    if is_top_level
        settings.toplevel = false # downstream types are not toplevel
    end
    names = fieldnames(julia_type)
    structypes_names = StructTypes.names(julia_type) |> OrderedDict
    types = fieldtypes(julia_type)
    json_property_names = String[]
    required_json_property_names = String[]
    json_properties = []
    optional_fields = StructTypes.omitempties(julia_type)
    for (name, type) in zip(names, types)
        sym_name = get(structypes_names, name, name)
        name_string = string(sym_name)

        is_optional = _is_nothing_union(type)

        if is_optional # we assume it's an optional field type / to do: check GEMINI
            @argcheck name in optional_fields "we miss $name in $(StructTypes.omitempties(julia_type))"
            type = _get_optional_type(type)
            if settings.llm_adapter == OPENAI
                push!(required_json_property_names, name_string)
            end
        elseif !(name in optional_fields)
            push!(required_json_property_names, name_string)
        end

        if settings.use_references && type in settings.reference_types
            rt = _json_reference(type, settings)
            if is_optional && settings.llm_adapter == OPENAI
                push!(json_properties, settings.dict_type{String,Any}(
                    "description" => getdescription(annotation, sym_name),
                    "anyOf" => [rt, settings.dict_type{String,Any}("type" => "null")]
                ))
            else
                rt["description"] = getdescription(annotation, sym_name)
                push!(json_properties, rt)
            end
        else
            jt = _generate_json_type_def(type, settings)

            if settings.llm_adapter == OPENAI
                if is_optional && haskey(jt, "type")
                    jt["type"] = [jt["type"], "null"]

                end
                jt["description"] = getdescription(annotation, sym_name)

                en = getenum(annotation, sym_name)
                if !isnothing(en)
                    jt["enum"] = en
                end

            end

            push!(json_properties, jt)

        end
        push!(json_property_names, name_string)
    end
    d = settings.dict_type{String,Any}(
        "type" => "object",
        "properties" => settings.dict_type{String,Any}(
            json_property_names .=> json_properties
        ),
        "required" => required_json_property_names,
    )
    if settings.llm_adapter == OPENAI
        d["additionalProperties"] = false

        if !is_top_level
            d["description"] = getdescription(annotation)
        end
    end

    if is_top_level && settings.use_references
        d["\$defs"] = _generate_json_reference_types(settings)
    end
    return d
end

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
    return settings.dict_type{String,Any}(
        "type" => "array",
        "items" => item_type
    )
end

function _generate_json_type_def(::Val{:enum}, julia_type::Type, settings::SchemaSettings)
    return settings.dict_type{String,Any}(
        "type" => "string",
        "enum" => string.(instances(julia_type))
    )
end

function _generate_json_type_def(::Val, julia_type::Type, settings::SchemaSettings)
    return settings.dict_type{String,Any}(
        "type" => string(_json_type(julia_type))
    )
end

# used in things like { "\$ref": "#/MyObject" }
function _json_reference(julia_type::Type, settings::SchemaSettings)
    return settings.dict_type{String,Any}(
        "\$ref" => settings.reference_path * string(julia_type)
    )
end

function _generate_json_reference_types(settings::SchemaSettings)
    d = settings.dict_type{String,Any}()
    for ref_type in settings.reference_types
        d[string(ref_type)] = _generate_json_type_def(ref_type, settings)
    end
    return d
end

function _gather_data_types(julia_type::Type)::Set{DataType}
    data_types = Set{DataType}()
    for field_type in fieldtypes(julia_type)
        _gather_data_types!(data_types, _get_type_to_gather(field_type))
    end
    return data_types
end

function _gather_data_types!(data_types::Set{DataType}, julia_type::Type)::Nothing
    if StructTypes.StructType(julia_type) isa StructTypes.DataType
        push!(data_types, julia_type)
        for field_type in fieldtypes(julia_type)
            _gather_data_types!(data_types, _get_type_to_gather(field_type))
        end
    end
    return nothing
end

function _get_type_to_gather(input_type::Type)
    if _is_nothing_union(input_type)
        type_to_gather = _get_optional_type(input_type)
    elseif input_type <: AbstractArray
        type_to_gather = eltype(input_type)
    else
        type_to_gather = input_type
    end
    return type_to_gather
end

