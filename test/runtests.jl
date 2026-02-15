using Test, Avro, UUIDs, Dates, StructTypes, JSON3, Tables, SentinelArrays

@testset "Avro.jl" begin

# missing
buf = Avro.write(missing)
@test isempty(buf)

# booleans
buf = Avro.write(true)
@test buf[1] == 0x01
buf = Avro.write(false)
@test buf[1] == 0x00

# integers
buf = Avro.write(1)
@test buf[1] == 0x02
buf = Avro.write(63)
@test buf[1] == 0x7e
buf = Avro.write(64)
@test buf == [0x80, 0x01]

x = typemax(UInt8)
@test Avro.read(Avro.write(x), UInt8) === x

buf = Avro.write(-1)
@test buf[1] == 0x01
buf = Avro.write(-63)
@test buf[1] == 0x7d
buf = Avro.write(-64)
@test buf[1] == 0x7f
buf = Avro.write(-65)
@test buf == [0x81, 0x01]

for i = typemin(Int16):typemax(Int16)
    @test i == Avro.read(Avro.write(i), Int)
end

# floats
for x in (-0.0001, 0.0, -0.0, 1.0, floatmin(Float32), floatmax(Float32), floatmin(Float64), floatmax(Float64))
    @test x === Avro.read(Avro.write(x), typeof(x))
end

# bytes
x = [UInt8(y) for y in "hey there stranger"]
@test x == Avro.read(Avro.write(x), typeof(x))

x = UInt8[]
@test x == Avro.read(Avro.write(x), typeof(x))

# strings
x = "hey there stranger"
@test x == Avro.read(Avro.write(x), typeof(x))

x = ""
@test x == Avro.read(Avro.write(x), typeof(x))

# array
x = [1, 2, 3, 4, 5]
@test x == Avro.read(Avro.write(x), typeof(x))

# array of strings
x = ["hey", "there", "stranger"]
@test x == Avro.read(Avro.write(x), typeof(x))

x = String[]
@test x == Avro.read(Avro.write(x), typeof(x))

# fixed
x = tuple(b"hey"...)
@test x == Avro.read(Avro.write(x), typeof(x))

x = ()
@test x == Avro.read(Avro.write(x), typeof(x))

# maps
x = Dict("hey" => 1, "there" => 2, "stranger" => 3)
@test x == Avro.read(Avro.write(x), typeof(x))

x = Dict{String, Int}()
@test x == Avro.read(Avro.write(x), typeof(x))

# enums
x = Avro.Enum{(:hey, :there, :stranger)}(0)
@test x == Avro.read(Avro.write(x), typeof(x))

# unions
x = 1
@test x == Avro.read(Avro.write(x; schema=Union{Int, String}), Union{Int, String})

# records
x = (a=1, b=3.4, c="hey")
@test x == Avro.read(Avro.write(x), typeof(x))

r = Avro.read(Avro.write(x), Avro.Record{(:a, :b, :c), Tuple{Int, Float64, String}})
@test r.a == 1
@test r.b == 3.4
@test r.c == "hey"

struct Person
    id::Int
    name::String
end

StructTypes.StructType(::Type{Person}) = StructTypes.Struct()

x = Person(10, "Valentin")
@test x == Avro.read(Avro.write(x), typeof(x))

x = [Person(1, "meg"), Person(2, "jo"), Person(3, "beth"), Person(4, "amy")]
@test x == Avro.read(Avro.write(x), typeof(x))

# logical
x = Avro.Decimal{0, 4}(Int128(1))
@test x == Avro.read(Avro.write(x), typeof(x))

x = UUID(rand(UInt128))
@test x == Avro.read(Avro.write(x), typeof(x))

x = Dates.today()
@test x == Avro.read(Avro.write(x), typeof(x))

x = Time(Dates.now())
@test x == Avro.read(Avro.write(x), typeof(x))

x = Dates.now()
@test x == Avro.read(Avro.write(x), typeof(x))

x = Avro.Duration(1, 2, 3)
@test x == Avro.read(Avro.write(x), typeof(x))

# combinations
cases = [
    # arrays
    [missing, missing, missing],
    [true, false, true],
    [1.2, 3.4, 5.6],
    [Vector{UInt8}("hey"), Vector{UInt8}("there"), Vector{UInt8}("stranger")],
    [Avro.Enum{(:a, :b, :c)}(0), Avro.Enum{(:a, :b, :c)}(1), Avro.Enum{(:a, :b, :c)}(2)],
    [[1, 2], [3, 4, 5], [6, 7, 8, 9]],
    [Dict(:a => Float32(1)), Dict(:b => Float32(2)), Dict(:c => Float32(3))],
    [(a=Date(2021, 1, 1), b=true), (a=Date(2021, 1, 2), b=false), (a=Date(2021, 1, 3), b=true)],
    Union{Missing, UUID, Avro.Duration}[UUID(rand(UInt128)), missing, Avro.Duration(4, 5, 6)],
    Union{Missing, Int32, Vector{UInt8}, Date, UUID, Dict{String, NamedTuple{(:a,), Tuple{Union{Int64, Float32}}}}, Vector{Union{NamedTuple{(:a,), Tuple{Int64}}, Avro.Enum{(:a, :b)}}}}[missing, Int32(4), Vector{UInt8}("hey"), Date(2021, 2, 1), UUID(rand(UInt128)), Dict{String, NamedTuple{(:a,), Tuple{Union{Int64, Float32}}}}("a" => (a=Int64(1),), "b" => (a=Float32(3.14),)), Union{NamedTuple{(:a,), Tuple{Int64}}, Avro.Enum{(:a, :b)}}[(a=1001,), Avro.Enum{(:a, :b)}(0), Avro.Enum{(:a, :b)}(1)]],
    # maps
    Dict("a" => missing),
    Dict("a" => true, "b" => false),
    Dict("a" => 1.2, "b" => 3.4),
    Dict("a" => Vector{UInt8}("hey"), "b" => Vector{UInt8}("there")),
    Dict("a" => Avro.Enum{(:a, :b, :c)}(0), "b" => Avro.Enum{(:a, :b, :c)}(1)),
    Dict("a" => [1, 2], "b" => [3, 4, 5]),
    Dict("a" => Dict(:a => Float32(1)), "b" => Dict(:b => Float32(2))),
    Dict("a" => (a=Time(1, 2, 3), b=UUID(rand(UInt128))), "b" => (a=Time(4, 5, 6), b=UUID(rand(UInt128)))),
    Dict{String, Union{Missing, DateTime, Avro.Decimal{1, 4}}}("a" => missing, "b" => Dates.now(), "c" => Avro.Decimal{1, 4}(12345)),
    # records
    (a=missing,),
    (a=[missing, missing],),
    (a=Dict("a" => missing),),
    (a=Dict("a" => [missing, missing]),),
    (a=true, b=false),
    (a=[true, false], b=[false, false]),
    (a=Dict("a" => true),),
    (a=Dict("a" => [true, false], "b" => [false, false]),),
    (a=1.2,),
    (a=[1.2, 3.4],),
    (a=Dict("a" => 4.5),),
    (a=Dict("a" => [6.7, 8.9]),),
    (a=Vector{UInt8}("hey"), b=Avro.Enum{(:a, :b)}(0), c=[1, 2]),
    (a=Dict('a' => Float32(1.2)),),
    (a=(a=Date(2021, 1, 1), b=Time(1, 2, 3), c=UUID(rand(UInt128))),),
    NamedTuple{(:a,), Tuple{Union{Missing, UUID, Dict{String, Float32}}}}((Dict("a" => Float32(1.4)),)),
]

for case in cases
    @test isequal(case, Avro.read(Avro.write(case), typeof(case)))
    # write out schema, object to file from julia
    # sch = Avro.schematype(typeof(case))
    # JSON3.write("schema.avsc", sch)
    # Avro.write("x.avro", case)
    # js = """
    #     let avro = require('avro-js');
    #     let fs = require('fs');
    #     // read schema, object from file in node
    #     let sch = avro.parse('./schema.avsc');
    #     let x = sch.fromBuffer(fs.readFileSync('./x.avro'));
    #     // write out schema, object to file from node
    #     fs.writeFileSync('jsschema.avsc', sch.getSchema());
    #     fs.writeFileSync('jsx.avro', sch.toBuffer(x));
    # """
    # run(`node -e $js`)
    # # read in schema, object from file in julia
    # sch2 = Avro.parseschema("jsschema.avsc"))
    # case2 = Avro.read(Base.read("jsx.avro"), sch)
    # @test sch == sch2
    # @test isequal(case, case2)
end

nt = (a=1, b=2, c=3)
rt = [nt, nt, nt]
for comp in (:deflate, :bzip2, :xz, :zstd)
    io = Avro.tobuffer(rt; compress=comp)
    tbl = Avro.readtable(io)
    @test length(tbl) == 3
    @test tbl[1].a == nt.a
    @test tbl[1].b == nt.b
    @test tbl[1].c == nt.c
end

nt = (a=[1, 2, 3], b=[4.0, 5.0, 6.0], c=["7", "8", "9"])
io = Avro.tobuffer(nt)
tbl = Avro.readtable(io)
@test length(tbl) == 3
@test tbl.sch == Tables.Schema((:a, :b, :c), (Int, Float64, String))

rt = [(a=1, b=4.0, c="7"), (a=2.0, b=missing, c="8"), (a=3, b=6.0, c="9")]
io = Avro.tobuffer(rt)
tbl = Avro.readtable(io)
@test length(tbl) == 3

rt = [
    (a=1, b=2, c=3),
    (b=4.0, c=missing, d=5),
    (a=6, d=7),
    (a=8, b=9, c=10, d=missing),
    (d=11, c=10, b=9, a=8)
]

dct = Tables.dictcolumntable(rt)
io = Avro.tobuffer(dct)
tbl = Avro.readtable(io)
@test length(tbl) == 5

end

@testset "Code generation" begin

@testset "generate_code: simple record" begin
    code = Avro.generate_code("""
    {
      "type": "record",
      "name": "Point",
      "fields": [
        {"name": "x", "type": "double"},
        {"name": "y", "type": "double"}
      ]
    }
    """)
    @test occursin("struct Point", code)
    @test occursin("x::Float64", code)
    @test occursin("y::Float64", code)
    @test occursin("StructTypes.StructType(::Type{Point}) = StructTypes.Struct()", code)
    @test occursin("using StructTypes", code)
end

@testset "generate_code: nested records" begin
    code = Avro.generate_code("""
    {
      "type": "record",
      "name": "Outer",
      "fields": [
        {"name": "id", "type": "long"},
        {"name": "inner", "type": {
          "type": "record",
          "name": "Inner",
          "fields": [
            {"name": "value", "type": "double"}
          ]
        }}
      ]
    }
    """)
    @test occursin("struct Inner", code)
    @test occursin("struct Outer", code)
    @test occursin("inner::Inner", code)
    # Inner must appear before Outer (dependency order)
    @test findfirst("struct Inner", code)[1] < findfirst("struct Outer", code)[1]
end

@testset "generate_code: enum" begin
    code = Avro.generate_code("""
    {"type": "enum", "name": "Color", "symbols": ["RED", "GREEN", "BLUE"]}
    """)
    @test occursin("const Color = Avro.Enum{(:RED, :GREEN, :BLUE,)}", code)
end

@testset "generate_code: logical types" begin
    code = Avro.generate_code("""
    {
      "type": "record",
      "name": "Event",
      "fields": [
        {"name": "ts", "type": {"type": "long", "logicalType": "timestamp-millis"}},
        {"name": "d", "type": {"type": "int", "logicalType": "date"}},
        {"name": "uid", "type": {"type": "string", "logicalType": "uuid"}}
      ]
    }
    """)
    @test occursin("ts::DateTime", code)
    @test occursin("d::Date", code)
    @test occursin("uid::UUID", code)
    @test occursin("using Dates", code)
    @test occursin("UUIDs", code)
end

@testset "generate_code: union / nullable" begin
    code = Avro.generate_code("""
    {
      "type": "record",
      "name": "R",
      "fields": [
        {"name": "opt", "type": ["null", "string"]},
        {"name": "multi", "type": ["null", "int", "double"]}
      ]
    }
    """)
    @test occursin("opt::Union{Missing, String}", code)
    @test occursin("multi::Union{Missing, Int32, Float64}", code)
end

@testset "generate_code: arrays and maps" begin
    code = Avro.generate_code("""
    {
      "type": "record",
      "name": "Container",
      "fields": [
        {"name": "items", "type": {"type": "array", "items": "long"}},
        {"name": "labels", "type": {"type": "map", "values": "string"}}
      ]
    }
    """)
    @test occursin("items::Vector{Int64}", code)
    @test occursin("labels::Dict{String, String}", code)
end

@testset "generate_code: fixed" begin
    code = Avro.generate_code("""
    {
      "type": "record",
      "name": "HasFixed",
      "fields": [
        {"name": "checksum", "type": {"type": "fixed", "name": "MD5", "size": 16}}
      ]
    }
    """)
    @test occursin("checksum::NTuple{16, UInt8}", code)
end

@testset "generate_code: doc strings" begin
    code = Avro.generate_code("""
    {
      "type": "record",
      "name": "Documented",
      "doc": "A documented record",
      "fields": [
        {"name": "x", "type": "int", "doc": "the x value"}
      ]
    }
    """)
    @test occursin("\"\"\"A documented record\"\"\"", code)
    @test occursin("# the x value", code)
end

@testset "generate_code: field name sanitization" begin
    code = Avro.generate_code("""
    {
      "type": "record",
      "name": "Weird",
      "fields": [
        {"name": "my-field", "type": "int"},
        {"name": "end", "type": "string"}
      ]
    }
    """)
    @test occursin("my_field::Int32", code)
    @test occursin("end_::String", code)
    # StructTypes.names mapping for sanitized field names
    @test occursin("StructTypes.names", code)
end

@testset "generate_code: namespace stripping" begin
    code = Avro.generate_code("""
    {
      "type": "record",
      "name": "com.example.MyRecord",
      "fields": [
        {"name": "val", "type": "int"}
      ]
    }
    """)
    @test occursin("struct MyRecord", code)
    @test !occursin("com.example", code)
end

@testset "generate_code: module wrapper" begin
    code = Avro.generate_code("""
    {"type": "record", "name": "P", "fields": [{"name": "x", "type": "int"}]}
    """; module_name="MyModule")
    @test occursin("module MyModule", code)
    @test occursin("end # module MyModule", code)
end

@testset "generate_type: round-trip simple record" begin
    T = Avro.generate_type("""
    {
      "type": "record",
      "name": "Point",
      "fields": [
        {"name": "x", "type": "double"},
        {"name": "y", "type": "double"}
      ]
    }
    """)
    obj = T(1.0, 2.0)
    buf = Avro.write(obj)
    result = Avro.read(buf, T)
    @test result.x === 1.0
    @test result.y === 2.0
end

@testset "generate_type: round-trip nested records" begin
    T = Avro.generate_type("""
    {
      "type": "record",
      "name": "Outer",
      "fields": [
        {"name": "id", "type": "long"},
        {"name": "inner", "type": {
          "type": "record",
          "name": "Inner",
          "fields": [{"name": "value", "type": "double"}]
        }}
      ]
    }
    """)
    Inner = fieldtype(T, :inner)
    obj = T(42, Inner(3.14))
    buf = Avro.write(obj)
    result = Avro.read(buf, T)
    @test result.id === Int64(42)
    @test result.inner.value === 3.14
end

@testset "generate_type: round-trip with nullable" begin
    T = Avro.generate_type("""
    {
      "type": "record",
      "name": "Nullable",
      "fields": [
        {"name": "name", "type": "string"},
        {"name": "age", "type": ["null", "int"]}
      ]
    }
    """)
    # Present value
    obj1 = T("Alice", Int32(30))
    buf1 = Avro.write(obj1)
    r1 = Avro.read(buf1, T)
    @test r1.name == "Alice"
    @test r1.age === Int32(30)
    # Missing value
    obj2 = T("Bob", missing)
    buf2 = Avro.write(obj2)
    r2 = Avro.read(buf2, T)
    @test r2.name == "Bob"
    @test ismissing(r2.age)
end

@testset "generate_type: round-trip with arrays and maps" begin
    T = Avro.generate_type("""
    {
      "type": "record",
      "name": "Container",
      "fields": [
        {"name": "items", "type": {"type": "array", "items": "long"}},
        {"name": "labels", "type": {"type": "map", "values": "string"}}
      ]
    }
    """)
    obj = T([1, 2, 3], Dict("a" => "x", "b" => "y"))
    buf = Avro.write(obj)
    result = Avro.read(buf, T)
    @test result.items == [1, 2, 3]
    @test result.labels == Dict("a" => "x", "b" => "y")
end

@testset "generate_type: enum" begin
    T = Avro.generate_type("""{"type":"enum","name":"Status","symbols":["ACTIVE","INACTIVE"]}""")
    @test T === Avro.Enum{(:ACTIVE, :INACTIVE)}
end

@testset "generate_type: .avsc file" begin
    # Write a temp .avsc file and read it
    path = tempname() * ".avsc"
    write(path, """{"type":"record","name":"FromFile","fields":[{"name":"n","type":"int"}]}""")
    T = Avro.generate_type(path)
    obj = T(Int32(7))
    buf = Avro.write(obj)
    result = Avro.read(buf, T)
    @test result.n === Int32(7)

    code = Avro.generate_code(path)
    @test occursin("struct FromFile", code)
    rm(path; force=true)
end

@testset "generate_code: all primitive field types" begin
    code = Avro.generate_code("""
    {
      "type": "record",
      "name": "AllPrims",
      "fields": [
        {"name": "a", "type": "null"},
        {"name": "b", "type": "boolean"},
        {"name": "c", "type": "int"},
        {"name": "d", "type": "long"},
        {"name": "e", "type": "float"},
        {"name": "f", "type": "double"},
        {"name": "g", "type": "bytes"},
        {"name": "h", "type": "string"}
      ]
    }
    """)
    @test occursin("a::Missing", code)
    @test occursin("b::Bool", code)
    @test occursin("c::Int32", code)
    @test occursin("d::Int64", code)
    @test occursin("e::Float32", code)
    @test occursin("f::Float64", code)
    @test occursin("g::Vector{UInt8}", code)
    @test occursin("h::String", code)
end

@testset "generate_type: record with enum field" begin
    T = Avro.generate_type("""
    {
      "type": "record",
      "name": "WithEnum",
      "fields": [
        {"name": "status", "type": {"type": "enum", "name": "Status", "symbols": ["ON", "OFF"]}},
        {"name": "count", "type": "int"}
      ]
    }
    """)
    obj = T(Avro.Enum{(:ON, :OFF)}(0), Int32(5))
    buf = Avro.write(obj)
    result = Avro.read(buf, T)
    @test result.status == Avro.Enum{(:ON, :OFF)}(0)
    @test result.count === Int32(5)
end

end # @testset "Code generation"


# using CSV, Dates, Tables, Test
# const dir = joinpath(dirname(pathof(CSV)), "..", "test", "testfiles")
# include(joinpath(dirname(pathof(CSV)), "..", "test", "testfiles.jl"))
# for (i, test) in enumerate(testfiles)
#     file, kwargs, expected_sz, expected_sch, testfunc = test
#     println("testing $file, i = $i")
#     f = CSV.File(file isa IO ? file : joinpath(dir, file); kwargs...)
#     buf = Avro.tobuffer(f)
#     tbl = Avro.readtable(buf)
#     @test isequal(columntable(f), columntable(tbl))
# end
