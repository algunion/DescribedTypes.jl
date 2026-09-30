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

# `true` when `json_string` is valid against `json_schema`; used to check rejections too
validates(json_schema, json_string) =
    JSONSchema.validate(JSONSchema.Schema(json_schema), JSON.parse(json_string)) === nothing

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

struct SymbolEnumFieldAnnotated
    color::String
    size::Int
end
DescribedTypes.annotate(::Type{SymbolEnumFieldAnnotated}) = DescribedTypes.Annotation(
    name="SymbolEnumFieldAnnotated",
    description="Schema with a symbol-enum-annotated string field.",
    parameters=Dict(
        :color => DescribedTypes.Annotation(name="color", description="The color", enum=[:red, :green, :blue]),
        :size => DescribedTypes.Annotation(name="size", description="The size"),
    ),
)

struct SymbolStringDuplicateEnumFieldAnnotated
    color::String
end
DescribedTypes.annotate(::Type{SymbolStringDuplicateEnumFieldAnnotated}) = DescribedTypes.Annotation(
    name="SymbolStringDuplicateEnumFieldAnnotated",
    description="Schema with duplicate enum labels after symbol/string normalization.",
    parameters=Dict(
        :color => DescribedTypes.Annotation(
            name="color",
            description="The color",
            enum=[:red, "red", :green, "green", :red],
        ),
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

# --- _is_nullable coverage ---

@testset "_is_nullable edge cases" begin
    @test DescribedTypes._is_nullable(Nothing) == false
    @test DescribedTypes._is_nullable(Missing) == false
    @test DescribedTypes._is_nullable(Any) == false
    @test DescribedTypes._is_nullable(Int) == false
    @test DescribedTypes._is_nullable(String) == false
    @test DescribedTypes._is_nullable(Union{Nothing,Missing}) == false
    @test DescribedTypes._is_nullable(Union{Nothing,Int}) == true
    @test DescribedTypes._is_nullable(Union{Nothing,String}) == true
    @test DescribedTypes._is_nullable(Union{Missing,Int}) == true
    @test DescribedTypes._nonnull_type(Union{Nothing,Missing,Int}) == Int
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

    # getenum on annotation with symbol enum
    a2s = DescribedTypes.Annotation(name="A", description="d", enum=[:a, :b])
    @test DescribedTypes.getenum(a2s) == [:a, :b]

    # getenum on annotation with mixed string/symbol enum
    a2m = DescribedTypes.Annotation(name="A", description="d", enum=[:a, "a", :b])
    @test DescribedTypes.getenum(a2m) == [:a, "a", :b]

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

    # getenum(a, field) when field has symbol enum
    a5 = DescribedTypes.Annotation(
        name="A",
        description="d",
        parameters=Dict(:c => DescribedTypes.Annotation(name="c", description="C", enum=[:r, :g, :b])),
    )
    @test DescribedTypes.getenum(a5, :c) == [:r, :g, :b]
end

@testset "_normalize_enum_values helper" begin
    @test DescribedTypes._normalize_enum_values(["a", "b"]) == ["a", "b"]
    @test DescribedTypes._normalize_enum_values([:a, :b]) == ["a", "b"]
    @test DescribedTypes._normalize_enum_values([:a, "a", :b, "b", :a]) == ["a", "b"]
    @test DescribedTypes._normalize_enum_values([:a, "a", :b, "b", :a], :dedupe) == ["a", "b"]
    @test_throws ArgumentError DescribedTypes._normalize_enum_values([:a, "a"], :error)
    @test_throws ArgumentError DescribedTypes._normalize_enum_values(Any[:ok, 1])
    @test_throws ArgumentError DescribedTypes._normalize_enum_values(["a"], :invalid_policy)
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

@testset "Symbol enum annotation on field (OPENAI)" begin
    json_schema = DescribedTypes.schema(EdgeTestTypes.SymbolEnumFieldAnnotated, llm_adapter=DescribedTypes.OPENAI)
    inner = json_schema["schema"]
    @test inner["properties"]["color"]["enum"] == ["red", "green", "blue"]
    @test inner["properties"]["color"]["type"] == "string"
    @test inner["properties"]["color"]["description"] == "The color"
    @test !haskey(inner["properties"]["size"], "enum")
end

@testset "Symbol enum annotation on field (OPENAI_TOOLS)" begin
    json_schema = DescribedTypes.schema(EdgeTestTypes.SymbolEnumFieldAnnotated, llm_adapter=DescribedTypes.OPENAI_TOOLS)
    inner = json_schema["parameters"]
    @test inner["properties"]["color"]["enum"] == ["red", "green", "blue"]
    @test inner["properties"]["color"]["type"] == "string"
    @test !haskey(inner["properties"]["size"], "enum")
end

@testset "Mixed symbol/string duplicate enum normalization (OPENAI)" begin
    json_schema = DescribedTypes.schema(
        EdgeTestTypes.SymbolStringDuplicateEnumFieldAnnotated,
        llm_adapter=DescribedTypes.OPENAI,
    )
    inner = json_schema["schema"]
    @test inner["properties"]["color"]["enum"] == ["red", "green"]
end

@testset "Mixed symbol/string duplicate enum normalization (OPENAI_TOOLS)" begin
    json_schema = DescribedTypes.schema(
        EdgeTestTypes.SymbolStringDuplicateEnumFieldAnnotated,
        llm_adapter=DescribedTypes.OPENAI_TOOLS,
    )
    inner = json_schema["parameters"]
    @test inner["properties"]["color"]["enum"] == ["red", "green"]
end

@testset "Duplicate enum policy :error (OPENAI)" begin
    @test_throws ArgumentError DescribedTypes.schema(
        EdgeTestTypes.SymbolStringDuplicateEnumFieldAnnotated,
        llm_adapter=DescribedTypes.OPENAI,
        enum_duplicate_policy=:error,
    )
end

@testset "Duplicate enum policy :error (OPENAI_TOOLS)" begin
    @test_throws ArgumentError DescribedTypes.schema(
        EdgeTestTypes.SymbolStringDuplicateEnumFieldAnnotated,
        llm_adapter=DescribedTypes.OPENAI_TOOLS,
        enum_duplicate_policy=:error,
    )
end

@testset "Duplicate enum policy validation" begin
    @test_throws ArgumentError DescribedTypes.schema(
        EdgeTestTypes.SymbolEnumFieldAnnotated,
        llm_adapter=DescribedTypes.OPENAI,
        enum_duplicate_policy=:invalid_policy,
    )
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
    @test s.enum_duplicate_policy == :dedupe
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

# ===================================================================
# Function schema + JSON invocation tests
# ===================================================================

module FunctionTestTypes
using DescribedTypes

struct Point
    x::Int
    y::Int
end

"""
Weather lookup helper.
"""
function weather(city::String, days::Int=3; unit::String="celsius", include_humidity::Bool=false)
    return (; city, days, unit, include_humidity)
end

function optional_union(name::String, limit::Union{Nothing,Int}=nothing; top::Union{Nothing,Int}=nothing)
    return (; name, limit, top)
end

function score_point(point::Point, scale::Float64=1.0)
    return (point.x + point.y) * scale
end

DescribedTypes.annotate(::typeof(weather), ms::DescribedTypes.MethodSignature) = DescribedTypes.MethodAnnotation(
    name=:weather_tool,
    description="Look up weather data.",
    argsannot=Dict(
        :city => DescribedTypes.ArgAnnotation(name=:city, description="City name", required=true),
        :days => DescribedTypes.ArgAnnotation(name=:days, description="Forecast horizon in days", required=false),
        :unit => DescribedTypes.ArgAnnotation(name=:unit, description="Temperature unit", enum=["celsius", "fahrenheit"], required=false),
        :include_humidity => DescribedTypes.ArgAnnotation(name=:include_humidity, description="Include humidity signal", required=false),
    ),
)

end # module FunctionTestTypes

@testset "extractsignature for functions" begin
    sig = DescribedTypes.extractsignature(FunctionTestTypes.weather)
    @test sig.name == :weather
    @test sig.description == "Weather lookup helper."
    @test length(sig.args) == 4
    @test sig.args[1] isa DescribedTypes.PositionalArg
    @test sig.args[2] isa DescribedTypes.PositionalArg
    @test sig.args[3] isa DescribedTypes.KeywordArg
    @test sig.args[4] isa DescribedTypes.KeywordArg

    @test sig.args[1].name == :city
    @test sig.args[1].type == String
    @test sig.args[1].required == true

    @test sig.args[2].name == :days
    @test sig.args[2].type == Int
    @test sig.args[2].required == false

    @test sig.args[3].name == :unit
    @test sig.args[3].type == String
    @test sig.args[3].required == false
end

@testset "extractsignature handles Union{Nothing,T}=nothing defaults" begin
    sig = DescribedTypes.extractsignature(FunctionTestTypes.optional_union)
    @test length(sig.args) == 3
    @test sig.args[2].type == Union{Nothing,Int}
    @test sig.args[2].required == false
    @test sig.args[3].type == Union{Nothing,Int}
    @test sig.args[3].required == false
end

@testset "function schema (STANDARD)" begin
    s = DescribedTypes.schema(FunctionTestTypes.weather)
    @test s["type"] == "object"
    @test Set(keys(s["properties"])) == Set(["city", "days", "unit", "include_humidity"])
    @test Set(s["required"]) == Set(["city"])
    @test s["properties"]["city"]["type"] == "string"
    @test s["properties"]["days"]["type"] == "integer"
end

@testset "function schema (OPENAI_TOOLS)" begin
    s = DescribedTypes.schema(FunctionTestTypes.weather, llm_adapter=DescribedTypes.OPENAI_TOOLS)
    @test s["type"] == "function"
    @test s["name"] == "weather_tool"
    @test s["description"] == "Look up weather data."
    @test s["strict"] == true

    inner = s["parameters"]
    @test inner["type"] == "object"
    @test Set(inner["required"]) == Set(["city", "days", "unit", "include_humidity"])
    @test inner["properties"]["days"]["type"] == ["integer", "null"]
    @test inner["properties"]["unit"]["type"] == ["string", "null"]
    # null must be an enum member too, or the "use the default" value is unreachable
    @test inner["properties"]["unit"]["enum"] == ["celsius", "fahrenheit", nothing]
    @test inner["additionalProperties"] == false

    @test validates(inner, """{"city":"Rome","days":null,"unit":null,"include_humidity":null}""")
    @test validates(inner, """{"city":"Rome","days":2,"unit":"fahrenheit","include_humidity":true}""")
    @test !validates(inner, """{"city":"Rome","days":null,"unit":"kelvin","include_humidity":null}""")
end

@testset "function schema (OPENAI)" begin
    s = DescribedTypes.schema(FunctionTestTypes.weather, llm_adapter=DescribedTypes.OPENAI)
    @test haskey(s, "schema")
    @test s["name"] == "weather_tool"
    @test s["schema"]["properties"]["city"]["description"] == "City name"
end

@testset "annotate! safety for method signatures" begin
    sig = DescribedTypes.extractsignature(FunctionTestTypes.weather)
    bad = DescribedTypes.MethodAnnotation(
        name=:weather,
        argsannot=Dict(
            :city => DescribedTypes.ArgAnnotation(name=:city, required=true),
        ),
    )
    @test_throws ArgumentError DescribedTypes.annotate!(sig, bad)
end

@testset "callfunction from Dict and JSON" begin
    res1 = DescribedTypes.callfunction(
        FunctionTestTypes.weather,
        Dict("city" => "Paris"),
    )
    @test res1 == (city="Paris", days=3, unit="celsius", include_humidity=false)

    res2 = DescribedTypes.callfunction(
        FunctionTestTypes.weather,
        Dict("city" => "Berlin", "days" => 1, "unit" => "fahrenheit", "include_humidity" => true),
    )
    @test res2 == (city="Berlin", days=1, unit="fahrenheit", include_humidity=true)

    # null optional/defaulted positional argument means "use default"
    res3 = DescribedTypes.callfunction(
        FunctionTestTypes.weather,
        "{\"city\":\"Rome\",\"days\":null,\"unit\":\"celsius\"}",
    )
    @test res3 == (city="Rome", days=3, unit="celsius", include_humidity=false)

    # OpenAI-like wrapper payload
    wrapped = Dict("arguments" => "{\"city\":\"Madrid\",\"unit\":\"fahrenheit\"}")
    res4 = DescribedTypes.callfunction(FunctionTestTypes.weather, wrapped)
    @test res4 == (city="Madrid", days=3, unit="fahrenheit", include_humidity=false)
end

@testset "callfunction validation and coercion" begin
    # enum validation from ArgAnnotation
    @test_throws ArgumentError DescribedTypes.callfunction(
        FunctionTestTypes.weather,
        Dict("city" => "Paris", "unit" => "kelvin"),
    )

    # missing required argument
    @test_throws ArgumentError DescribedTypes.callfunction(
        FunctionTestTypes.weather,
        Dict("days" => 2),
    )

    # unexpected argument
    @test_throws ArgumentError DescribedTypes.callfunction(
        FunctionTestTypes.weather,
        Dict("city" => "Paris", "extra" => 1),
    )

    # nested struct coercion from JSON object
    point_score = DescribedTypes.callfunction(
        FunctionTestTypes.score_point,
        Dict("point" => Dict("x" => 2, "y" => 3), "scale" => 2.0),
    )
    @test point_score == 10.0
end

# ===================================================================
# Type coverage: common Julia types that used to crash or emit wrong schemas
# ===================================================================

module WideTypes
using DescribedTypes

struct SymbolField
    mode::Symbol
end

struct AnyField
    payload::Any
end

struct DictField
    counts::Dict{String,Int}
end

struct FreeDictField
    meta::Dict{String,Any}
end

struct UnionField
    id::Union{Int,String}
end

struct MissingField
    score::Union{Missing,Float64}
end

struct NullableItems
    values::Vector{Union{Nothing,Int}}
end

struct TupleField
    point::NTuple{2,Float64}
end

struct MixedTupleField
    pair::Tuple{Int,String}
end

struct SetField
    tags::Set{String}
end

struct EmptyStruct end

struct HasEmpty
    marker::EmptyStruct
end

abstract type Shape end

struct AbstractField
    shape::Shape
end

struct UnionAllField
    values::Vector{<:Real}
end

struct Node
    label::String
    children::Vector{Node}
end

@enum Fruit apple orange

struct OptionalEnum
    fruit::Union{Nothing,Fruit}
end

struct OptionalAnnotatedEnum
    color::Union{Nothing,String}
end
DescribedTypes.annotate(::Type{OptionalAnnotatedEnum}) = DescribedTypes.Annotation(
    name="OptionalAnnotatedEnum",
    description="Optional color constrained by an annotation enum.",
    parameters=Dict(
        :color => DescribedTypes.Annotation(name="color", description="The color", enum=["red", "green"]),
    ),
)

struct A1
    x::Int
end
struct A2
    x::Int
end
struct A3
    x::Int
end
struct A4
    x::Int
end
struct A5
    x::Int
end
struct ManyNested
    a::A1
    b::A2
    c::A3
    d::A4
    e::A5
end

end # module WideTypes

@testset "Symbol fields map to strings" begin
    s = DescribedTypes.schema(WideTypes.SymbolField)
    @test s["properties"]["mode"] == Dict("type" => "string")
    test_json_schema_validation(s, WideTypes.SymbolField(:fast))
end

@testset "Any fields accept any JSON value (STANDARD only)" begin
    s = DescribedTypes.schema(WideTypes.AnyField)
    @test isempty(s["properties"]["payload"])
    @test validates(s, """{"payload": [1, "two", {"three": null}]}""")
    @test_throws ArgumentError DescribedTypes.schema(WideTypes.AnyField, llm_adapter=DescribedTypes.OPENAI)
end

@testset "Dict fields map to JSON maps" begin
    s = DescribedTypes.schema(WideTypes.DictField)
    counts = s["properties"]["counts"]
    @test counts == Dict("type" => "object", "additionalProperties" => Dict("type" => "integer"))
    test_json_schema_validation(s, WideTypes.DictField(Dict("a" => 1, "b" => 2)))
    @test !validates(s, """{"counts": {"a": "not an integer"}}""")

    free = DescribedTypes.schema(WideTypes.FreeDictField)
    @test free["properties"]["meta"] == Dict("type" => "object")

    # strict mode cannot express open-ended objects: fail loudly instead of leaking Dict internals
    for adapter in (DescribedTypes.OPENAI, DescribedTypes.OPENAI_TOOLS)
        @test_throws "additionalProperties" DescribedTypes.schema(WideTypes.DictField, llm_adapter=adapter)
    end
end

@testset "General unions map to anyOf" begin
    s = DescribedTypes.schema(WideTypes.UnionField)
    branches = s["properties"]["id"]["anyOf"]
    @test Set(b["type"] for b in branches) == Set(["integer", "string"])
    test_json_schema_validation(s, WideTypes.UnionField(7))
    test_json_schema_validation(s, WideTypes.UnionField("seven"))
    @test !validates(s, """{"id": 7.5}""")

    o = DescribedTypes.schema(WideTypes.UnionField, llm_adapter=DescribedTypes.OPENAI)
    @test length(o["schema"]["properties"]["id"]["anyOf"]) == 2
end

@testset "Union{Missing,T} is optional like Union{Nothing,T}" begin
    s = DescribedTypes.schema(WideTypes.MissingField)
    @test isempty(s["required"])
    @test s["properties"]["score"]["type"] == "number"
    test_json_schema_validation(s, WideTypes.MissingField(0.5))

    o = DescribedTypes.schema(WideTypes.MissingField, llm_adapter=DescribedTypes.OPENAI)
    @test o["schema"]["required"] == ["score"]
    @test o["schema"]["properties"]["score"]["type"] == ["number", "null"]
end

@testset "Nullable element types" begin
    s = DescribedTypes.schema(WideTypes.NullableItems)
    @test s["properties"]["values"]["items"]["type"] == ["integer", "null"]
    @test validates(s, """{"values": [1, null, 3]}""")
    @test !validates(s, """{"values": [1, "x"]}""")
end

@testset "Tuples map to fixed-length arrays" begin
    s = DescribedTypes.schema(WideTypes.TupleField)
    point = s["properties"]["point"]
    @test point["type"] == "array"
    @test point["items"] == Dict("type" => "number")
    @test point["minItems"] == 2 && point["maxItems"] == 2
    test_json_schema_validation(s, WideTypes.TupleField((1.0, 2.0)))
    @test !validates(s, """{"point": [1.0, 2.0, 3.0]}""")

    @test_throws "Tuple{Int64, String}" DescribedTypes.schema(WideTypes.MixedTupleField)
end

@testset "Sets map to arrays" begin
    s = DescribedTypes.schema(WideTypes.SetField)
    @test s["properties"]["tags"] == Dict("type" => "array", "items" => Dict("type" => "string"))
    test_json_schema_validation(s, WideTypes.SetField(Set(["a", "b"])))
end

@testset "Empty structs" begin
    # JSON.jl writes singleton types as strings, so validate the object form directly
    s = DescribedTypes.schema(WideTypes.EmptyStruct)
    @test s["type"] == "object"
    @test isempty(s["properties"]) && isempty(s["required"])
    @test validates(s, "{}")

    nested = DescribedTypes.schema(WideTypes.HasEmpty)
    @test validates(nested, """{"marker": {}}""")
    @test !validates(nested, """{"marker": "EmptyStruct()"}""")
end

@testset "Abstract field types fail with an actionable error" begin
    @test_throws ArgumentError DescribedTypes.schema(WideTypes.AbstractField)
    @test_throws "Shape" DescribedTypes.schema(WideTypes.AbstractField)
end

@testset "UnionAll field types use their upper bound" begin
    s = DescribedTypes.schema(WideTypes.UnionAllField)
    @test s["properties"]["values"]["items"] == Dict("type" => "number")
end

@testset "Recursive types" begin
    # inlining a recursive type cannot terminate; say how to fix it instead of overflowing the stack
    @test_throws "use_references=true" DescribedTypes.schema(WideTypes.Node)

    ref = "#/\$defs/" * string(WideTypes.Node)
    s = DescribedTypes.schema(WideTypes.Node, use_references=true)
    @test s["properties"]["children"]["items"] == Dict("\$ref" => ref)
    @test s["\$defs"][string(WideTypes.Node)]["properties"]["children"]["items"] == Dict("\$ref" => ref)

    o = DescribedTypes.schema(WideTypes.Node, use_references=true, llm_adapter=DescribedTypes.OPENAI)
    @test o["schema"]["properties"]["children"]["items"]["\$ref"] == ref
end

@testset "\$defs follow declaration order" begin
    s = DescribedTypes.schema(WideTypes.ManyNested, use_references=true)
    expected = string.([WideTypes.A1, WideTypes.A2, WideTypes.A3, WideTypes.A4, WideTypes.A5])
    @test collect(keys(s["\$defs"])) == expected
end

@testset "Nullable enums admit null (OpenAI modes)" begin
    for adapter in (DescribedTypes.OPENAI, DescribedTypes.OPENAI_TOOLS)
        wrapper_key = adapter == DescribedTypes.OPENAI ? "schema" : "parameters"

        inner = DescribedTypes.schema(WideTypes.OptionalEnum, llm_adapter=adapter)[wrapper_key]
        fruit = inner["properties"]["fruit"]
        @test fruit["type"] == ["string", "null"]
        @test fruit["enum"] == ["apple", "orange", nothing]
        @test validates(inner, """{"fruit": null}""")
        @test validates(inner, """{"fruit": "apple"}""")
        @test !validates(inner, """{"fruit": "banana"}""")

        inner = DescribedTypes.schema(WideTypes.OptionalAnnotatedEnum, llm_adapter=adapter)[wrapper_key]
        @test inner["properties"]["color"]["enum"] == ["red", "green", nothing]
        @test validates(inner, """{"color": null}""")
        @test !validates(inner, """{"color": "blue"}""")
    end
end

# ===================================================================
# Function extraction robustness
# ===================================================================

module WideFunctions
using DescribedTypes
using ..WideTypes: Fruit

untyped(x) = x
with_symbol(mode::Symbol) = mode
with_dict(opts::Dict{String,Any}) = opts
required_kw(a::Int; n::Int) = a + n
bounded(x::T) where {T<:Integer} = x
scaled(xs::Vector{T}; scale::T=one(T)) where {T<:Real} = xs .* scale
@inline function inlined(x::Int)
    return x + 1
end
Base.@constprop :aggressive constprop(x::Int) = x * 2
total(xs::Vector{Int}) = sum(xs; init=0)
maybe_missing(x::Union{Missing,Int}) = x
choose(fruit::Union{Nothing,Fruit}=nothing) = fruit
pick(fruit::Union{Nothing,String}) = fruit
point_tuple(p::NTuple{2,Float64}) = p[1] + p[2]
tags(t::Set{String}) = sort(collect(t))

"""
    forecast(city)

Return the forecast for `city`.
"""
forecast(city::String) = city

"Area of a square."
area(side::Int) = side^2
"Area of a rectangle."
area(w::Int, h::Int) = w * h

struct Point
    x::Int
    y::Int
end
struct Segment
    a::Point
    b::Point
end
seglen(s::Segment, p::Point) = 0.0
nearest(p::Point, hint::Union{Nothing,Point}=nothing) = p

DescribedTypes.annotate(::typeof(pick), ms::DescribedTypes.MethodSignature) = DescribedTypes.MethodAnnotation(
    name=:pick,
    description="Pick a fruit, or nothing.",
    argsannot=Dict(
        :fruit => DescribedTypes.ArgAnnotation(name=:fruit, description="Fruit", enum=["apple", "orange"], required=true),
    ),
)

# No source file: forces the method-table (runtime) extraction path
eval(Meta.parse("runtime_bounded(x::T; k::T=one(T)) where {T<:Integer} = x + k"))

end # module WideFunctions

@testset "Untyped (Any) arguments" begin
    s = DescribedTypes.schema(WideFunctions.untyped)
    @test isempty(s["properties"]["x"])
    @test s["required"] == ["x"]
    @test_throws ArgumentError DescribedTypes.schema(WideFunctions.untyped, llm_adapter=DescribedTypes.OPENAI_TOOLS)
    @test DescribedTypes.callfunction(WideFunctions.untyped, Dict("x" => [1, "a"])) == [1, "a"]
end

@testset "Symbol arguments" begin
    s = DescribedTypes.schema(WideFunctions.with_symbol)
    @test s["properties"]["mode"] == Dict("type" => "string")
    @test DescribedTypes.callfunction(WideFunctions.with_symbol, Dict("mode" => "fast")) === :fast
end

@testset "Dict arguments" begin
    s = DescribedTypes.schema(WideFunctions.with_dict)
    @test s["properties"]["opts"] == Dict("type" => "object")
    res = DescribedTypes.callfunction(WideFunctions.with_dict, """{"opts": {"a": 1, "b": [1, 2]}}""")
    @test res isa Dict{String,Any}
    @test res["a"] == 1 && res["b"] == [1, 2]
    @test_throws ArgumentError DescribedTypes.schema(WideFunctions.with_dict, llm_adapter=DescribedTypes.OPENAI_TOOLS)
end

@testset "Required typed keyword arguments" begin
    sig = DescribedTypes.extractsignature(WideFunctions.required_kw)
    kw = only(filter(a -> a isa DescribedTypes.KeywordArg, sig.args))
    @test (kw.name, kw.type, kw.required) == (:n, Int, true)
    @test Set(DescribedTypes.schema(WideFunctions.required_kw)["required"]) == Set(["a", "n"])
    @test DescribedTypes.callfunction(WideFunctions.required_kw, Dict("a" => 1, "n" => 2)) == 3
    @test_throws ArgumentError DescribedTypes.callfunction(WideFunctions.required_kw, Dict("a" => 1))
end

@testset "Methods with where clauses" begin
    sig = DescribedTypes.extractsignature(WideFunctions.bounded)
    @test only(sig.args).type == Integer
    @test DescribedTypes.schema(WideFunctions.bounded)["properties"]["x"]["type"] == "integer"
    @test DescribedTypes.callfunction(WideFunctions.bounded, Dict("x" => 3)) == 3

    s = DescribedTypes.schema(WideFunctions.scaled)
    @test s["properties"]["xs"]["items"]["type"] == "number"
    @test s["properties"]["scale"]["type"] == "number"
    @test DescribedTypes.callfunction(WideFunctions.scaled, Dict("xs" => [1, 2], "scale" => 3)) == [3, 6]

    # same method shape, but without source code available
    rsig = DescribedTypes.extractsignature(WideFunctions.runtime_bounded)
    @test [(a.name, a.type) for a in rsig.args] == [(:x, Integer), (:k, Integer)]
    @test DescribedTypes.callfunction(WideFunctions.runtime_bounded, Dict("x" => 1, "k" => 2)) == 3
end

@testset "Macro-wrapped definitions" begin
    @test [a.name for a in DescribedTypes.extractsignature(WideFunctions.inlined).args] == [:x]
    @test DescribedTypes.callfunction(WideFunctions.inlined, Dict("x" => 1)) == 2
    @test DescribedTypes.callfunction(WideFunctions.constprop, Dict("x" => 2)) == 4
end

@testset "Docstrings become tool descriptions" begin
    sig = DescribedTypes.extractsignature(WideFunctions.forecast)
    @test occursin("Return the forecast for `city`.", sig.description)
    s = DescribedTypes.schema(WideFunctions.forecast, llm_adapter=DescribedTypes.OPENAI_TOOLS)
    @test occursin("Return the forecast for `city`.", s["description"])

    # each method keeps its own docstring
    square = first(methods(WideFunctions.area, (Int,)))
    rectangle = first(methods(WideFunctions.area, (Int, Int)))
    @test DescribedTypes.extractsignature(WideFunctions.area, square).description == "Area of a square."
    @test DescribedTypes.extractsignature(WideFunctions.area, rectangle).description == "Area of a rectangle."

    # undocumented functions keep the generic fallback
    @test DescribedTypes.extractsignature(WideFunctions.untyped).description === nothing
end

@testset "use_references for function schemas" begin
    point_ref = "#/\$defs/" * string(WideFunctions.Point)
    segment_ref = "#/\$defs/" * string(WideFunctions.Segment)

    s = DescribedTypes.schema(WideFunctions.seglen, use_references=true)
    @test collect(keys(s["\$defs"])) == [string(WideFunctions.Segment), string(WideFunctions.Point)]
    @test s["properties"]["s"] == Dict("\$ref" => segment_ref)
    @test s["properties"]["p"] == Dict("\$ref" => point_ref)
    @test s["\$defs"][string(WideFunctions.Segment)]["properties"]["a"]["\$ref"] == point_ref

    # without references nothing leaks a `$defs` key into argument schemas
    for adapter in (DescribedTypes.STANDARD, DescribedTypes.OPENAI_TOOLS)
        @test !occursin("\$defs", JSON.json(DescribedTypes.schema(WideFunctions.seglen, llm_adapter=adapter)))
    end

    t = DescribedTypes.schema(WideFunctions.nearest, use_references=true, llm_adapter=DescribedTypes.OPENAI_TOOLS)
    params = t["parameters"]
    @test haskey(params, "\$defs")
    hint = params["properties"]["hint"]
    @test haskey(hint, "description")
    @test Set(keys(b) for b in hint["anyOf"]) == Set([Set(["\$ref"]), Set(["type"])])
end

@testset "Nullable enum arguments" begin
    s = DescribedTypes.schema(WideFunctions.choose)
    @test s["properties"]["fruit"]["enum"] == ["apple", "orange", nothing]
    @test validates(s, """{"fruit": null}""")
    @test DescribedTypes.callfunction(WideFunctions.choose, Dict("fruit" => "orange")) == WideTypes.orange

    t = DescribedTypes.schema(WideFunctions.pick, llm_adapter=DescribedTypes.OPENAI_TOOLS)
    @test t["parameters"]["properties"]["fruit"]["enum"] == ["apple", "orange", nothing]
    @test DescribedTypes.callfunction(WideFunctions.pick, Dict("fruit" => nothing)) === nothing
    @test DescribedTypes.callfunction(WideFunctions.pick, Dict("fruit" => "apple")) == "apple"
    @test_throws ArgumentError DescribedTypes.callfunction(WideFunctions.pick, Dict("fruit" => "kiwi"))
end

@testset "callfunction coercion edge cases" begin
    # element type must not depend on type inference (failed on Julia 1.11)
    @test DescribedTypes.callfunction(WideFunctions.total, Dict("xs" => [])) == 0
    @test DescribedTypes.callfunction(WideFunctions.total, """{"xs": []}""") == 0

    @test DescribedTypes.callfunction(WideFunctions.maybe_missing, Dict("x" => nothing)) === missing
    @test DescribedTypes.callfunction(WideFunctions.maybe_missing, Dict("x" => 4)) == 4
    @test DescribedTypes.schema(WideFunctions.maybe_missing)["properties"]["x"]["type"] == ["integer", "null"]

    @test DescribedTypes.callfunction(WideFunctions.point_tuple, Dict("p" => [1, 2])) == 3.0
    @test_throws ArgumentError DescribedTypes.callfunction(WideFunctions.point_tuple, Dict("p" => [1, 2, 3]))
    @test DescribedTypes.callfunction(WideFunctions.tags, Dict("t" => ["b", "a", "b"])) == ["a", "b"]
end

@testset "ArgAnnotation exclusion flags imply optional" begin
    excluded = DescribedTypes.ArgAnnotation(name=:x, llmexclude=true)
    @test !excluded.required && excluded.llmexclude
    provided = DescribedTypes.ArgAnnotation(name=:x, userprovided=true)
    @test !provided.required && provided.userprovided
    @test DescribedTypes.ArgAnnotation(name=:x).required
    # an explicit contradiction is still rejected
    @test_throws ArgumentError DescribedTypes.ArgAnnotation(name=:x, required=true, llmexclude=true)
end
