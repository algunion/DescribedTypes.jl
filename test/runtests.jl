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

# ===================================================================
# Edge-case / coverage-gap tests
# ===================================================================

# --- Additional test types -----------------------------------------------------------

module EdgeTestTypes
using DescribedTypes

struct BooleanSchema
    flag::Bool
    name::String
end
DescribedTypes.annotate(::Type{BooleanSchema}) = DescribedTypes.Annotation(
    name="BooleanSchema",
    description="A schema with a boolean field.",
    parameters=Dict(
        :flag => DescribedTypes.Annotation(name="flag", description="A boolean flag"),
        :name => DescribedTypes.Annotation(name="name", description="A name"),
    ),
)

# Type with NO custom annotation — exercises the default `annotate` fallback
struct UnannotatedSchema
    x::Int
    y::String
end

# Type with an enum annotation on a *field* (not an enum Julia type)
struct EnumFieldAnnotated
    color::String
    size::Int
end
DescribedTypes.annotate(::Type{EnumFieldAnnotated}) = DescribedTypes.Annotation(
    name="EnumFieldAnnotated",
    description="Schema with an enum-annotated string field.",
    parameters=Dict(
        :color => DescribedTypes.Annotation(name="color", description="The color", enum=["red", "green", "blue"]),
        :size => DescribedTypes.Annotation(name="size", description="The size"),
    ),
)

# Type with an optional field that is itself a nested struct (for anyOf + $ref branch)
struct OptionalNestedSchema
    label::String
    child::Union{Nothing,BooleanSchema}
end
DescribedTypes.annotate(::Type{OptionalNestedSchema}) = DescribedTypes.Annotation(
    name="OptionalNestedSchema",
    description="Schema with an optional nested struct field.",
    parameters=Dict(
        :label => DescribedTypes.Annotation(name="label", description="Label"),
        :child => DescribedTypes.Annotation(name="child", description="Optional child"),
    ),
)

# Deeply nested with arrays of optional-field structs for reference gathering
struct MultiNestedSchema
    items::Vector{OptionalNestedSchema}
    primary::BooleanSchema
end
DescribedTypes.annotate(::Type{MultiNestedSchema}) = DescribedTypes.Annotation(
    name="MultiNestedSchema",
    description="Schema with arrays of nested types.",
    parameters=Dict(
        :items => DescribedTypes.Annotation(name="items", description="Items"),
        :primary => DescribedTypes.Annotation(name="primary", description="Primary"),
    ),
)

end # module EdgeTestTypes

# --- _json_type coverage ---

@testset "_json_type edge cases" begin
    @test DescribedTypes._json_type(Bool) == :boolean
    @test DescribedTypes._json_type(Nothing) == :null
    @test DescribedTypes._json_type(Missing) == :null
    @test DescribedTypes._json_type(Int32) == :integer
    @test DescribedTypes._json_type(Float32) == :number
    @test DescribedTypes._json_type(SubString{String}) == :string
    @test DescribedTypes._json_type(Vector{Int}) == :array
    @test DescribedTypes._json_type(Matrix{Float64}) == :array
    @test DescribedTypes._json_type(EdgeTestTypes.BooleanSchema) == :object
end

# --- _is_nothing_union coverage ---

@testset "_is_nothing_union edge cases" begin
    @test DescribedTypes._is_nothing_union(Nothing) == false
    @test DescribedTypes._is_nothing_union(Int) == false
    @test DescribedTypes._is_nothing_union(String) == false
    @test DescribedTypes._is_nothing_union(Union{Nothing,Int}) == true
    @test DescribedTypes._is_nothing_union(Union{Nothing,String}) == true
end

# --- _is_openai_mode coverage ---

@testset "_is_openai_mode" begin
    @test DescribedTypes._is_openai_mode(DescribedTypes.STANDARD) == false
    @test DescribedTypes._is_openai_mode(DescribedTypes.GEMINI) == false
    @test DescribedTypes._is_openai_mode(DescribedTypes.OPENAI) == true
    @test DescribedTypes._is_openai_mode(DescribedTypes.OPENAI_TOOLS) == true
end

# --- Annotation helpers ---

@testset "Annotation single-arg constructor" begin
    a = DescribedTypes.Annotation("Foo")
    @test DescribedTypes.getname(a) == "Foo"
    @test DescribedTypes.getdescription(a) == "Semantic of Foo in the context of the schema"
    @test DescribedTypes.getenum(a) === nothing
    @test a.parameters === nothing
    @test a.markdown == ""
end

@testset "getdescription fallback for missing params/field" begin
    # parameters is nothing
    a = DescribedTypes.Annotation(name="T", description="top")
    @test DescribedTypes.getdescription(a, :nonexistent) == "Semantic of nonexistent in the context of the schema"

    # parameters exists but field is missing
    a2 = DescribedTypes.Annotation(
        name="T",
        description="top",
        parameters=Dict(:x => DescribedTypes.Annotation(name="x", description="X desc")),
    )
    @test DescribedTypes.getdescription(a2, :x) == "X desc"
    @test DescribedTypes.getdescription(a2, :missing_field) == "Semantic of missing_field in the context of the schema"
end

@testset "getenum helpers" begin
    # getenum on annotation with no enum
    a = DescribedTypes.Annotation(name="A", description="d")
    @test DescribedTypes.getenum(a) === nothing

    # getenum on annotation with enum
    a2 = DescribedTypes.Annotation(name="A", description="d", enum=["a", "b"])
    @test DescribedTypes.getenum(a2) == ["a", "b"]

    # getenum(a, field) when parameters is nothing
    @test DescribedTypes.getenum(a, :foo) === nothing

    # getenum(a, field) when field is missing
    a3 = DescribedTypes.Annotation(
        name="A",
        description="d",
        parameters=Dict(:x => DescribedTypes.Annotation(name="x", description="X")),
    )
    @test DescribedTypes.getenum(a3, :missing_field) === nothing

    # getenum(a, field) when field has enum
    a4 = DescribedTypes.Annotation(
        name="A",
        description="d",
        parameters=Dict(:c => DescribedTypes.Annotation(name="c", description="C", enum=["r", "g", "b"])),
    )
    @test DescribedTypes.getenum(a4, :c) == ["r", "g", "b"]
end

# --- Default annotate fallback ---

@testset "Default annotate (unannotated type)" begin
    a = DescribedTypes.annotate(EdgeTestTypes.UnannotatedSchema)
    @test DescribedTypes.getname(a) == string(EdgeTestTypes.UnannotatedSchema)
    @test contains(DescribedTypes.getdescription(a), "Semantic of")
end

@testset "Unannotated schema generation" begin
    json_schema = DescribedTypes.schema(EdgeTestTypes.UnannotatedSchema)
    @test json_schema["type"] == "object"
    @test "x" in json_schema["required"]
    @test "y" in json_schema["required"]
    @test json_schema["properties"]["x"]["type"] == "integer"
    @test json_schema["properties"]["y"]["type"] == "string"

    test_json_schema_validation(json_schema, EdgeTestTypes.UnannotatedSchema(1, "hi"))
end

# --- Bool field ---

@testset "Boolean field schema" begin
    json_schema = DescribedTypes.schema(EdgeTestTypes.BooleanSchema)
    @test json_schema["properties"]["flag"]["type"] == "boolean"
    @test json_schema["properties"]["name"]["type"] == "string"

    test_json_schema_validation(json_schema, EdgeTestTypes.BooleanSchema(true, "Alice"))
    test_json_schema_validation(json_schema, EdgeTestTypes.BooleanSchema(false, "Bob"))
end

@testset "Boolean field OPENAI" begin
    json_schema = DescribedTypes.schema(EdgeTestTypes.BooleanSchema, llm_adapter=DescribedTypes.OPENAI)
    inner = json_schema["schema"]
    @test inner["properties"]["flag"]["type"] == "boolean"
    @test inner["additionalProperties"] == false
end

# --- GEMINI adapter ---

@testset "GEMINI adapter" begin
    json_schema = DescribedTypes.schema(TestTypes.BasicSchema, llm_adapter=DescribedTypes.GEMINI)
    # GEMINI currently returns plain schema (same as STANDARD)
    @test json_schema["type"] == "object"
    @test json_schema["properties"]["int"]["type"] == "integer"
    @test !haskey(json_schema, "additionalProperties")

    json_schema2 = DescribedTypes.schema(TestTypes.OptionalFieldSchema, llm_adapter=DescribedTypes.GEMINI)
    @test json_schema2["type"] == "object"
    @test json_schema2["required"] == ["int"]
end

# --- Enum annotation on a field (OpenAI mode) ---

@testset "Enum annotation on field (OPENAI)" begin
    json_schema = DescribedTypes.schema(EdgeTestTypes.EnumFieldAnnotated, llm_adapter=DescribedTypes.OPENAI)
    inner = json_schema["schema"]
    @test inner["properties"]["color"]["enum"] == ["red", "green", "blue"]
    @test inner["properties"]["color"]["type"] == "string"
    @test inner["properties"]["color"]["description"] == "The color"
    # field without enum annotation should NOT have "enum" key
    @test !haskey(inner["properties"]["size"], "enum")
end

@testset "Enum annotation on field (OPENAI_TOOLS)" begin
    json_schema = DescribedTypes.schema(EdgeTestTypes.EnumFieldAnnotated, llm_adapter=DescribedTypes.OPENAI_TOOLS)
    inner = json_schema["parameters"]
    @test inner["properties"]["color"]["enum"] == ["red", "green", "blue"]
    @test inner["properties"]["color"]["type"] == "string"
    @test !haskey(inner["properties"]["size"], "enum")
end

@testset "Enum annotation on field (STANDARD)" begin
    # In STANDARD mode the enum annotation is NOT emitted (only OpenAI modes add it)
    json_schema = DescribedTypes.schema(EdgeTestTypes.EnumFieldAnnotated)
    @test !haskey(json_schema["properties"]["color"], "enum")
    @test json_schema["properties"]["color"]["type"] == "string"
end

# --- Optional nested struct + references + OpenAI (anyOf branch) ---

@testset "Optional nested field (STANDARD)" begin
    json_schema = DescribedTypes.schema(EdgeTestTypes.OptionalNestedSchema)
    @test json_schema["required"] == ["label"]
    @test json_schema["properties"]["child"]["type"] == "object"
    @test json_schema["properties"]["child"]["properties"]["flag"]["type"] == "boolean"

    test_json_schema_validation(json_schema, EdgeTestTypes.OptionalNestedSchema("a", nothing))
    test_json_schema_validation(json_schema, EdgeTestTypes.OptionalNestedSchema("a", EdgeTestTypes.BooleanSchema(true, "b")))
end

@testset "Optional nested field (OPENAI)" begin
    json_schema = DescribedTypes.schema(EdgeTestTypes.OptionalNestedSchema, llm_adapter=DescribedTypes.OPENAI)
    inner = json_schema["schema"]
    # OpenAI mode: optional fields become required with ["type", "null"] or anyOf
    @test "child" in inner["required"]
    @test "label" in inner["required"]
    # child should have type = ["object", "null"] or similar
    child_prop = inner["properties"]["child"]
    if haskey(child_prop, "type")
        @test child_prop["type"] == ["object", "null"] || "null" in child_prop["type"]
    end
end

@testset "Optional nested field + references (OPENAI) — anyOf branch" begin
    json_schema = DescribedTypes.schema(
        EdgeTestTypes.OptionalNestedSchema,
        llm_adapter=DescribedTypes.OPENAI,
        use_references=true,
    )
    inner = json_schema["schema"]
    child_prop = inner["properties"]["child"]
    # Should use "anyOf" with a $ref and a null type
    @test haskey(child_prop, "anyOf")
    any_of = child_prop["anyOf"]
    @test length(any_of) == 2
    ref_entry = filter(x -> haskey(x, "\$ref"), any_of)
    null_entry = filter(x -> get(x, "type", nothing) == "null", any_of)
    @test length(ref_entry) == 1
    @test length(null_entry) == 1
    @test haskey(child_prop, "description")
end

@testset "Optional nested field + references (OPENAI_TOOLS) — anyOf branch" begin
    json_schema = DescribedTypes.schema(
        EdgeTestTypes.OptionalNestedSchema,
        llm_adapter=DescribedTypes.OPENAI_TOOLS,
        use_references=true,
    )
    inner = json_schema["parameters"]
    child_prop = inner["properties"]["child"]
    @test haskey(child_prop, "anyOf")
end

# --- use_references + OpenAI modes ---

@testset "References with OPENAI mode" begin
    json_schema = DescribedTypes.schema(
        TestTypes.DoubleNestedSchema,
        llm_adapter=DescribedTypes.OPENAI,
        use_references=true,
    )
    inner = json_schema["schema"]
    @test haskey(inner, "\$defs")
    @test inner["additionalProperties"] == false
    # Nested fields should use $ref
    @test haskey(inner["properties"]["arrays"], "\$ref")
end

@testset "References with OPENAI_TOOLS mode" begin
    json_schema = DescribedTypes.schema(
        TestTypes.DoubleNestedSchema,
        llm_adapter=DescribedTypes.OPENAI_TOOLS,
        use_references=true,
    )
    inner = json_schema["parameters"]
    @test haskey(inner, "\$defs")
    @test inner["additionalProperties"] == false
    @test haskey(inner["properties"]["nested"], "\$ref")
end

# --- OPENAI_TOOLS with nested/array types ---

@testset "Nested Structs OPENAI_TOOLS" begin
    json_schema = DescribedTypes.schema(TestTypes.NestedSchema, llm_adapter=DescribedTypes.OPENAI_TOOLS)
    @test json_schema["type"] == "function"
    inner = json_schema["parameters"]
    @test inner["type"] == "object"
    @test inner["additionalProperties"] == false
    @test "int" in inner["required"]
    @test "optional" in inner["required"]
    @test "enum" in inner["required"]
    # nested object should also have additionalProperties: false
    @test inner["properties"]["optional"]["additionalProperties"] == false
end

@testset "Arrays OPENAI_TOOLS" begin
    json_schema = DescribedTypes.schema(TestTypes.ArraySchema, llm_adapter=DescribedTypes.OPENAI_TOOLS)
    inner = json_schema["parameters"]
    @test inner["properties"]["integers"]["type"] == "array"
    @test inner["properties"]["integers"]["items"]["type"] == "integer"
    @test inner["properties"]["types"]["type"] == "array"
    @test inner["properties"]["types"]["items"]["type"] == "object"
end

# --- _gather_data_types edge cases ---

@testset "_gather_data_types edge cases" begin
    # Type with no nested structs should return empty set
    types = DescribedTypes._gather_data_types(TestTypes.BasicSchema)
    @test isempty(types)

    # OptionalNestedSchema has BooleanSchema via Union{Nothing, BooleanSchema}
    types = DescribedTypes._gather_data_types(EdgeTestTypes.OptionalNestedSchema)
    @test EdgeTestTypes.BooleanSchema in types

    # MultiNestedSchema: array of OptionalNestedSchema + BooleanSchema
    types = DescribedTypes._gather_data_types(EdgeTestTypes.MultiNestedSchema)
    @test EdgeTestTypes.OptionalNestedSchema in types
    @test EdgeTestTypes.BooleanSchema in types
end

# --- dict_type parameter ---

@testset "dict_type=Dict" begin
    json_schema = DescribedTypes.schema(TestTypes.BasicSchema, dict_type=Dict)
    @test json_schema isa Dict{String,Any}
    @test json_schema["type"] == "object"

    json_schema2 = DescribedTypes.schema(TestTypes.BasicSchema, dict_type=Dict, llm_adapter=DescribedTypes.OPENAI)
    @test json_schema2 isa Dict{String,Any}
    @test json_schema2["schema"] isa Dict{String,Any}
end

# --- compare_dicts edge cases ---

@testset "compare_dicts utility" begin
    d1 = JSON.Object("a" => 1, "b" => 2)
    d2 = JSON.Object("a" => 1, "b" => 2)
    @test TestTypes.compare_dicts(d1, d2) === nothing

    # different value
    d3 = JSON.Object("a" => 1, "b" => 3)
    res = TestTypes.compare_dicts(d1, d3)
    @test res !== nothing
    @test res[1] == "b"

    # missing key in d2
    d4 = JSON.Object("a" => 1, "c" => 2)
    res = TestTypes.compare_dicts(d1, d4)
    @test res !== nothing

    # nested dict comparison
    d5 = JSON.Object("inner" => JSON.Object("x" => 1))
    d6 = JSON.Object("inner" => JSON.Object("x" => 2))
    res = TestTypes.compare_dicts(d5, d6)
    @test res !== nothing
    @test res[1] == "x"

    # different lengths
    d7 = JSON.Object("a" => 1)
    @test_throws ArgumentError TestTypes.compare_dicts(d1, d7)

    # different types
    @test_throws ArgumentError TestTypes.compare_dicts(d1, Dict("a" => 1, "b" => 2))

    # key in d2 missing from d1
    d8 = JSON.Object("a" => 1, "z" => 9)
    res = TestTypes.compare_dicts(d1, d8)
    @test res !== nothing
end

# --- SchemaSettings defaults ---

@testset "SchemaSettings defaults" begin
    s = DescribedTypes.SchemaSettings()
    @test s.toplevel == true
    @test s.use_references == false
    @test isempty(s.reference_types)
    @test s.llm_adapter == DescribedTypes.STANDARD
    @test s.dict_type == JSON.Object
end

# --- JSON round-trip validation (serialize → validate) for edge types ---

@testset "JSON validation for edge types" begin
    for (T, instance) in [
        (EdgeTestTypes.BooleanSchema, EdgeTestTypes.BooleanSchema(true, "x")),
        (EdgeTestTypes.UnannotatedSchema, EdgeTestTypes.UnannotatedSchema(42, "hello")),
        (EdgeTestTypes.EnumFieldAnnotated, EdgeTestTypes.EnumFieldAnnotated("red", 5)),
        (EdgeTestTypes.OptionalNestedSchema, EdgeTestTypes.OptionalNestedSchema("lbl", nothing)),
        (EdgeTestTypes.OptionalNestedSchema, EdgeTestTypes.OptionalNestedSchema("lbl", EdgeTestTypes.BooleanSchema(false, "c"))),
    ]
        json_schema = DescribedTypes.schema(T)
        test_json_schema_validation(json_schema, instance)
    end
end

# --- Annotation field validation ---

module InvalidAnnotationTypes
using DescribedTypes

struct SimpleStruct
    x::Int
    y::String
end

# Annotation references a field `z` that does not exist on SimpleStruct
DescribedTypes.annotate(::Type{SimpleStruct}) = DescribedTypes.Annotation(
    name="SimpleStruct",
    description="A struct with x and y.",
    parameters=Dict(
        :x => DescribedTypes.Annotation(name="x", description="An integer"),
        :z => DescribedTypes.Annotation(name="z", description="Does not exist"),
    )
)

struct AllBogusFields
    a::Int
end

# Annotation has only non-existent fields
DescribedTypes.annotate(::Type{AllBogusFields}) = DescribedTypes.Annotation(
    name="AllBogusFields",
    description="One real field, annotation mentions none of them.",
    parameters=Dict(
        :foo => DescribedTypes.Annotation(name="foo", description="Nope"),
        :bar => DescribedTypes.Annotation(name="bar", description="Also nope"),
    )
)

struct CorrectlyAnnotated
    a::Int
    b::String
end

DescribedTypes.annotate(::Type{CorrectlyAnnotated}) = DescribedTypes.Annotation(
    name="CorrectlyAnnotated",
    description="All annotations match real fields.",
    parameters=Dict(
        :a => DescribedTypes.Annotation(name="a", description="An integer"),
        :b => DescribedTypes.Annotation(name="b", description="A string"),
    )
)
end

@testset "Annotation field validation" begin
    # Extra field in annotation → ArgumentError
    @test_throws ArgumentError DescribedTypes.schema(InvalidAnnotationTypes.SimpleStruct)
    @test_throws ArgumentError DescribedTypes.schema(InvalidAnnotationTypes.AllBogusFields)

    # Correctly annotated → no error
    json_schema = DescribedTypes.schema(InvalidAnnotationTypes.CorrectlyAnnotated)
    @test json_schema["type"] == "object"
    @test Set(json_schema["required"]) == Set(["a", "b"])
end
