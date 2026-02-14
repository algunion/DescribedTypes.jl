if isdefined(@__MODULE__, :LanguageServer)
    include("../src/DescribedTypes.jl")
end

using DescribedTypes
using JSONSchema
using JSON
using ArgCheck
using Test

module TestTypes
using DescribedTypes
using ArgCheck

# this is more complex than simple equality: the function reports first key/value pair that differs
# also the recursive comparison is implemented
# important to return the key/value pair that differs (if any) for better debugging
function compare_dicts(d1, d2; pass=0)
    @argcheck typeof(d1) == typeof(d2) "Inputs have different types"
    @argcheck length(d1) == length(d2) "Dicts have different lengths. d1 keys: $(keys(d1)), d2 keys: $(keys(d2))"
    d1 == d2 && return nothing
    for (k, v) in d1
        if !haskey(d2, k)
            return (k, v, nothing)
        elseif v isa AbstractDict
            res = compare_dicts(v, d2[k]; pass=pass + 1)
            res !== nothing && return res
        elseif v != d2[k]
            return (k, v, d2[k])
        end
    end
    # Check for keys in d2 that are missing from d1
    for k in keys(d2)
        if !haskey(d1, k)
            return (k, nothing, d2[k])
        end
    end
    return nothing
end


struct BasicSchema
    int::Int64
    float::Float64
    string::String
end
DescribedTypes.annotate(::Type{BasicSchema}) = DescribedTypes.Annotation(name="BasicSchema", description="A schema containing an integer, float, and string field.", markdown="Basic schema", parameters=Dict(:int => DescribedTypes.Annotation(name="int", description="An integer field"), :float => DescribedTypes.Annotation(name="float", description="A float field"), :string => DescribedTypes.Annotation(name="string", description="A string field")))

@enum Fruit begin
    apple = 1
    orange = 2
end


struct EnumeratedSchema
    fruit::Fruit
end
DescribedTypes.annotate(::Type{EnumeratedSchema}) = DescribedTypes.Annotation(name="EnumeratedSchema", description="A schema containing a single Fruit field.", markdown="Fruit type", parameters=Dict(:fruit => DescribedTypes.Annotation(name="fruit", description="Fruit type")))


struct OptionalFieldSchema
    int::Int
    optional::Union{Nothing,String}
end
DescribedTypes.annotate(::Type{OptionalFieldSchema}) = DescribedTypes.Annotation(name="OptionalFieldSchema", description="A schema containing an optional field.", markdown="Optional field", parameters=Dict(:int => DescribedTypes.Annotation(name="int", description="An integer field"), :optional => DescribedTypes.Annotation(name="optional", description="An optional string field")))


struct ArraySchema
    integers::Vector{Int64}
    types::Vector{OptionalFieldSchema}
end
DescribedTypes.annotate(::Type{ArraySchema}) = DescribedTypes.Annotation(name="ArraySchema", description="A schema containing an array of integers and an array of OptionalFieldSchema.", markdown="Array schema", parameters=Dict(:integers => DescribedTypes.Annotation(name="integers", description="An array of integers"), :types => DescribedTypes.Annotation(name="types", description="An array of OptionalFieldSchema")))

function ArraySchema()
    optional_array = [
        TestTypes.OptionalFieldSchema(1, "foo"),
        TestTypes.OptionalFieldSchema(1, nothing)
    ]
    return ArraySchema([1, 2], optional_array)
end

struct NestedSchema
    int::Int
    optional::OptionalFieldSchema
    enum::EnumeratedSchema
end
DescribedTypes.annotate(::Type{NestedSchema}) = DescribedTypes.Annotation(name="NestedSchema", description="A schema containing an integer, an OptionalFieldSchema, and an EnumeratedSchema.", markdown="Nested schema", parameters=Dict(:int => DescribedTypes.Annotation(name="int", description="An integer field"), :optional => DescribedTypes.Annotation(name="optional", description="An optional field"), :enum => DescribedTypes.Annotation(name="enum", description="An enumerated field")))

function NestedSchema()
    return NestedSchema(
        1,
        OptionalFieldSchema(1, nothing),
        EnumeratedSchema(apple)
    )
end

struct DoubleNestedSchema
    int::Int
    arrays::ArraySchema
    enum::EnumeratedSchema
    nested::NestedSchema
end
DescribedTypes.annotate(::Type{DoubleNestedSchema}) = DescribedTypes.Annotation(name="DoubleNestedSchema", description="A schema containing an integer, an ArraySchema, an EnumeratedSchema, and a NestedSchema.", markdown="Double nested schema", parameters=Dict(:int => DescribedTypes.Annotation(name="int", description="An integer field"), :arrays => DescribedTypes.Annotation(name="arrays", description="An array of ArraySchema"), :enum => DescribedTypes.Annotation(name="enum", description="An enumerated field"), :nested => DescribedTypes.Annotation(name="nested", description="A nested field")))

function DoubleNestedSchema()
    return DoubleNestedSchema(
        1,
        ArraySchema(),
        EnumeratedSchema(apple),
        NestedSchema(),
    )
end
end

function test_json_schema_validation(obj::T) where {T}
    json_schema = DescribedTypes.schema(T)
    test_json_schema_validation(json_schema, obj)
end

function test_json_schema_validation(json_schema, obj)
    my_schema = JSONSchema.Schema(json_schema) # make a schema
    json_string = JSON.json(obj; omit_null=true) # omit_null replaces StructTypes.omitempties
    @test JSONSchema.validate(my_schema, JSON.parse(json_string)) === nothing # validation is OK
end

@testset "Basic Types" begin
    json_schema = DescribedTypes.schema(TestTypes.BasicSchema)
    @test json_schema["type"] == "object"
    object_properties = ["int", "float", "string"]
    @test all(x in object_properties for x in json_schema["required"])
    @test all(x in object_properties for x in keys(json_schema["properties"]))

    @test json_schema["properties"]["int"]["type"] == "integer"
    @test json_schema["properties"]["float"]["type"] == "number"
    @test json_schema["properties"]["string"]["type"] == "string"

    test_json_schema_validation(TestTypes.BasicSchema(1, 1.0, "a"))
end

@testset "Basic Types Annotated" begin
    json_schema = DescribedTypes.schema(TestTypes.BasicSchema, llm_adapter=DescribedTypes.OPENAI)
    # replicating the tests from above with the [parameters] additions before [properties]
    @test json_schema["schema"]["type"] == "object"
    object_properties = ["int", "float", "string"]
    @test all(x in object_properties for x in json_schema["schema"]["required"])
    @test all(x in object_properties for x in keys(json_schema["schema"]["properties"]))

    @test json_schema["schema"]["properties"]["int"]["type"] == "integer"
    @test json_schema["schema"]["properties"]["float"]["type"] == "number"
    @test json_schema["schema"]["properties"]["string"]["type"] == "string"

    test_json_schema_validation(TestTypes.BasicSchema(1, 1.0, "a"))

    # @info "Basic Types Annotated JSON"
    # (JSON3.pretty(json_schema))
end

@testset "Enumerators" begin
    json_schema = DescribedTypes.schema(TestTypes.EnumeratedSchema)
    enum_instances = ["apple", "orange"]
    fruit_json_enum = json_schema["properties"]["fruit"]["enum"]
    @test all(x in fruit_json_enum for x in enum_instances)

    test_json_schema_validation(TestTypes.EnumeratedSchema(TestTypes.apple))
end

@testset "Enumerators Annotated" begin
    json_schema = DescribedTypes.schema(TestTypes.EnumeratedSchema, llm_adapter=DescribedTypes.OPENAI)

    enum_instances = ["apple", "orange"]
    fruit_json_enum = json_schema["schema"]["properties"]["fruit"]["enum"]
    @test all(x in fruit_json_enum for x in enum_instances)

    test_json_schema_validation(TestTypes.EnumeratedSchema(TestTypes.apple))

    # @info "Enumerators Annotated JSON"
    # (JSON3.pretty(json_schema))
end

@testset "Optional Fields" begin
    json_schema = DescribedTypes.schema(TestTypes.OptionalFieldSchema)
    @test !("optional" in json_schema["required"])
    @test json_schema["required"] == ["int"]
    @test json_schema["properties"]["optional"]["type"] == "string"

    # and the JSONSchema validation works fine
    test_json_schema_validation(TestTypes.OptionalFieldSchema(1, nothing))
    test_json_schema_validation(TestTypes.OptionalFieldSchema(1, "foo"))

    #StructTypes.StructType(::Type{TestTypes.OptionalFieldSchema}) = StructTypes.Struct()
    # if StructType is defined, but omitempties is not defined for the optional field, then we should throw an error
    #@test_throws OmitEmptiesException json_schema = DescribedTypes.schema(TestTypes.OptionalFieldSchema)
    #StructTypes.omitempties(::Type{TestTypes.OptionalFieldSchema}) = (:optional,)
    #json_schema = DescribedTypes.schema(TestTypes.OptionalFieldSchema)
end

@testset "Optional Fields Annotated" begin
    json_schema = DescribedTypes.schema(TestTypes.OptionalFieldSchema, llm_adapter=DescribedTypes.OPENAI)
    @test ("optional" in json_schema["schema"]["required"])
    @test json_schema["schema"]["required"] == ["int", "optional"]
    @test json_schema["schema"]["properties"]["optional"]["type"] == ["string", "null"]

    # and the JSONSchema validation works fine
    test_json_schema_validation(TestTypes.OptionalFieldSchema(1, nothing))
    test_json_schema_validation(TestTypes.OptionalFieldSchema(1, "foo"))

    # @info "Optional Fields Annotated JSON"
    # (JSON3.pretty(json_schema))
end

@testset "Arrays" begin
    #=
        {
    "type": "array",
    "items": {
        "type": "object" # or "type": { "\$ref": "#/OptionalFieldSchema" }
    }
    }=#
    json_schema = DescribedTypes.schema(TestTypes.ArraySchema)
    # so behavior depends on the eltype of the array
    @test json_schema["properties"]["integers"]["type"] == "array"
    @test json_schema["properties"]["integers"]["items"]["type"] == "integer"

    opt_schema = DescribedTypes.schema(TestTypes.OptionalFieldSchema)
    @test json_schema["properties"]["types"]["items"] == opt_schema

    test_json_schema_validation(TestTypes.ArraySchema())
end

@testset "Arrays Annotated" begin
    json_schema = DescribedTypes.schema(TestTypes.ArraySchema, llm_adapter=DescribedTypes.OPENAI)
    # so behavior depends on the eltype of the array
    @test json_schema["schema"]["properties"]["integers"]["type"] == "array"
    @test json_schema["schema"]["properties"]["integers"]["items"]["type"] == "integer"

    opt_schema = DescribedTypes.schema(TestTypes.OptionalFieldSchema, llm_adapter=DescribedTypes.OPENAI)
    @test json_schema["schema"]["properties"]["types"]["items"]["properties"] == opt_schema["schema"]["properties"]
    @test json_schema["schema"]["properties"]["types"]["items"]["required"] == opt_schema["schema"]["required"]

    test_json_schema_validation(TestTypes.ArraySchema())

    # @info "Arrays Annotated JSON 1"
    # (JSON3.pretty(opt_schema["schema"]))

    # @info "Arrays Annotated JSON 2"
    # (JSON3.pretty(json_schema["schema"]["properties"]["types"]["items"]))
end

@testset "Nested Structs" begin
    nested_schema = DescribedTypes.schema(TestTypes.NestedSchema)
    optional_field_schema = DescribedTypes.schema(TestTypes.OptionalFieldSchema)
    # by default it's a nested JSON schema
    @test nested_schema["properties"]["optional"] == optional_field_schema

    test_json_schema_validation(TestTypes.NestedSchema())

    double_nested_schema = DescribedTypes.schema(TestTypes.DoubleNestedSchema)
    @test double_nested_schema["properties"]["nested"] == nested_schema

    test_json_schema_validation(TestTypes.DoubleNestedSchema())
end

@testset "Nested Structs Annotated" begin
    nested_schema = DescribedTypes.schema(TestTypes.NestedSchema, llm_adapter=DescribedTypes.OPENAI)
    optional_field_schema = DescribedTypes.schema(TestTypes.OptionalFieldSchema, llm_adapter=DescribedTypes.OPENAI)
    # by default it's a nested JSON schema
    nt1 = deepcopy(nested_schema["schema"]["properties"]["optional"])
    delete!(nt1, "description")
    nt2 = optional_field_schema["schema"]

    @test nt1 == nt2

    test_json_schema_validation(TestTypes.NestedSchema())

    double_nested_schema = DescribedTypes.schema(TestTypes.DoubleNestedSchema, llm_adapter=DescribedTypes.OPENAI)

    delete!(double_nested_schema["schema"]["properties"]["nested"], "description")

    @test double_nested_schema["schema"]["properties"]["nested"] == nested_schema["schema"]

    test_json_schema_validation(TestTypes.DoubleNestedSchema())

    # @info "Nested Structs Annotated JSON 1"
    # (JSON3.pretty(optional_field_schema["schema"]))

    # @info "Nested Structs Annotated JSON 2"
    # (JSON3.pretty(nested_schema["schema"]["properties"]["optional"]))
end

@testset "DataType gathering" begin
    types = DescribedTypes._gather_data_types(TestTypes.NestedSchema)
    expected_types = [
        TestTypes.OptionalFieldSchema
        TestTypes.EnumeratedSchema
    ]
    @test length(types) == length(expected_types)
    @test all(x in types for x in expected_types)

    types = DescribedTypes._gather_data_types(TestTypes.ArraySchema)
    expected_types = [
        TestTypes.OptionalFieldSchema
    ]
    @test length(types) == length(expected_types)
    @test all(x in types for x in expected_types)

    types = DescribedTypes._gather_data_types(TestTypes.DoubleNestedSchema)
    expected_types = [
        TestTypes.NestedSchema
        TestTypes.EnumeratedSchema
        TestTypes.OptionalFieldSchema
        TestTypes.ArraySchema
    ]
    @test length(types) == length(expected_types)
    @test all(x in types for x in expected_types)
end

@testset "Nested Structs using schema references" begin

    # now, for readability we want to make use of JSON schema references
    # it should resolve to something like this:
    """
    {
    "type": "object",
    "properties": {
        "int": { "type": "integer" },
        "optional": { "\$ref": "#/\$defs/OptionalFieldSchema" },
        "enum": { "\$ref": "#/\$defs/EnumeratedSchema" },
        "nested": { "\$ref": "#/\$defs/NestedSchema" }
    },
    "required": ["int", "optional", "enum", "nested"],

    "\$defs": {
        "NestedSchema": {
            "type": "object",
            "properties": {
                "int": { "type": "integer" },
                "optional": { "\$ref": "#/OptionalFieldSchema" },
                "enum": { "\$ref": "#/EnumeratedSchema" }
            },
            "required": ["int", "optional", "enum"],
        },
        "OptionalFieldSchema": {
            "type": "object",
            "properties": {
                "int": { "type": "integer" },
                "optional": { "type": "string" }
            },
            "required": ["int"],
        },
        "EnumeratedSchema": {
            "type": "object",
            "properties": {
                "fruit": { "enum": ["apple", "orange"] },
            },
            "required": ["fruit"],
        }
    }
    """

    json_schema = DescribedTypes.schema(TestTypes.DoubleNestedSchema, use_references=true)

    array_ref = json_schema["properties"]["arrays"]["\$ref"]
    @test startswith(array_ref, "#/\$defs/")
    type_name = split(array_ref, "#/\$defs/")[2]
    @test type_name == string(TestTypes.ArraySchema)

    @test length(json_schema["\$defs"]) == length(DescribedTypes._gather_data_types(TestTypes.DoubleNestedSchema))
    array_type_def = json_schema["\$defs"][string(TestTypes.ArraySchema)]
    array_optional_eltype = array_type_def["properties"]["types"]["items"]
    # this must also be a reference
    @test array_optional_eltype["\$ref"] == "#/\$defs/$(string(TestTypes.OptionalFieldSchema))"

    nested_def = json_schema["\$defs"][string(TestTypes.NestedSchema)]
    @test nested_def["properties"]["optional"]["\$ref"] == "#/\$defs/" * string(TestTypes.OptionalFieldSchema)

    # https://www.jsonschemavalidator.net/ succeeds, but JSONSchema fails to resolve references
    #test_json_schema_validation(json_schema, TestTypes.DoubleNestedSchema())

    # also for single nesting
    json_schema = DescribedTypes.schema(TestTypes.NestedSchema, use_references=true, dict_type=Dict)
    #@info json_schema
    #test_json_schema_validation(json_schema, TestTypes.NestedSchema())
end

# --- OPENAI_TOOLS tests (function-calling wrapper with "parameters" key) ---

@testset "Basic Types OPENAI_TOOLS" begin
    json_schema = DescribedTypes.schema(TestTypes.BasicSchema, llm_adapter=DescribedTypes.OPENAI_TOOLS)

    # Top-level wrapper uses "parameters" (not "schema")
    @test json_schema["type"] == "function"
    @test json_schema["name"] == "BasicSchema"
    @test json_schema["strict"] == true
    @test haskey(json_schema, "parameters")
    @test !haskey(json_schema, "schema")

    inner = json_schema["parameters"]
    @test inner["type"] == "object"
    object_properties = ["int", "float", "string"]
    @test all(x in object_properties for x in inner["required"])
    @test all(x in object_properties for x in keys(inner["properties"]))

    @test inner["properties"]["int"]["type"] == "integer"
    @test inner["properties"]["float"]["type"] == "number"
    @test inner["properties"]["string"]["type"] == "string"
    @test inner["additionalProperties"] == false
end

@testset "Optional Fields OPENAI_TOOLS" begin
    json_schema = DescribedTypes.schema(TestTypes.OptionalFieldSchema, llm_adapter=DescribedTypes.OPENAI_TOOLS)

    inner = json_schema["parameters"]
    # OpenAI tools mode requires all fields, optional uses ["type", "null"]
    @test ("optional" in inner["required"])
    @test inner["required"] == ["int", "optional"]
    @test inner["properties"]["optional"]["type"] == ["string", "null"]
    @test inner["additionalProperties"] == false
end

@testset "Enumerators OPENAI_TOOLS" begin
    json_schema = DescribedTypes.schema(TestTypes.EnumeratedSchema, llm_adapter=DescribedTypes.OPENAI_TOOLS)

    @test json_schema["type"] == "function"
    @test haskey(json_schema, "parameters")
    inner = json_schema["parameters"]
    enum_instances = ["apple", "orange"]
    fruit_json_enum = inner["properties"]["fruit"]["enum"]
    @test all(x in fruit_json_enum for x in enum_instances)
end

@testset "OPENAI vs OPENAI_TOOLS inner schema parity" begin
    # The inner schema content should be identical; only the wrapper key differs
    for T in [TestTypes.BasicSchema, TestTypes.OptionalFieldSchema, TestTypes.EnumeratedSchema]
        openai_schema = DescribedTypes.schema(T, llm_adapter=DescribedTypes.OPENAI)
        tools_schema = DescribedTypes.schema(T, llm_adapter=DescribedTypes.OPENAI_TOOLS)

        @test openai_schema["schema"] == tools_schema["parameters"]
        @test openai_schema["name"] == tools_schema["name"]
        @test openai_schema["description"] == tools_schema["description"]
        @test openai_schema["strict"] == tools_schema["strict"]
    end
end
