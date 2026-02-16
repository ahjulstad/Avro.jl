```@meta
CurrentModule = Avro
DocTestSetup = :(using Avro, StructTypes)
```

# Avro.jl Documentation

Avro.jl is a pure Julia implementation of the [Apache Avro](https://avro.apache.org/docs/1.12.0/specification/) data serialization standard. It provides:

- **Binary encoding/decoding** of all Avro primitive, complex, and logical types
- **Object container files** with built-in schema and compression, accessible via the [Tables.jl](https://github.com/JuliaData/Tables.jl) interface
- **Automatic schema derivation** from Julia types, or parsing of external Avro JSON schemas
- **Code generation** from Avro JSON schemas to Julia struct definitions

If you are new to Avro, the key idea is simple: every value is written against a **schema** (defined in JSON), producing a very compact binary representation. Object container files embed the schema in the file header, making the data self-describing.

## Installation

```julia
using Pkg
Pkg.add("Avro")
```

---

## Quick Start: Round-Trip Examples

### Primitive types

```jldoctest
julia> buf = Avro.write(42);

julia> Avro.read(buf, Int)
42

julia> buf = Avro.write(3.14);

julia> Avro.read(buf, Float64)
3.14

julia> buf = Avro.write("hello");

julia> Avro.read(buf, String)
"hello"

julia> buf = Avro.write(true);

julia> Avro.read(buf, Bool)
true
```

### Records (NamedTuples)

Julia `NamedTuple`s map directly to Avro records:

```jldoctest
julia> row = (id = Int32(1), name = "Alice", score = 95.5);

julia> buf = Avro.write(row);

julia> Avro.read(buf, typeof(row))
(id = 1, name = "Alice", score = 95.5)
```

### Arrays and Maps

```jldoctest
julia> xs = [1, 2, 3];

julia> Avro.read(Avro.write(xs), typeof(xs))
3-element Vector{Int64}:
 1
 2
 3

julia> words = ["avro", "is", "fast"];

julia> Avro.read(Avro.write(words), typeof(words))
3-element Vector{String}:
 "avro"
 "is"
 "fast"
```

```julia
# Map (Dict with String keys) — output order may vary
d = Dict("a" => 1, "b" => 2)
Avro.read(Avro.write(d), typeof(d))     # Dict("a" => 1, "b" => 2)
```

### Custom structs

Any Julia struct can be serialized by declaring a [`StructTypes.jl`](https://github.com/JuliaData/StructTypes.jl) mapping:

```jldoctest sensor
julia> struct Sensor
           id::Int
           location::String
       end;

julia> StructTypes.StructType(::Type{Sensor}) = StructTypes.Struct();

julia> s = Sensor(7, "roof");

julia> buf = Avro.write(s);

julia> Avro.read(buf, Sensor)
Sensor(7, "roof")
```

Nested structs work too — just declare `StructTypes.StructType` for each type.

---

## Schema & Type Mapping

Avro schemas are defined in JSON. Avro.jl can **automatically derive** a schema from a Julia type, or **parse** an external JSON schema. This section shows how Avro types correspond to Julia types.

### Primitive types

| Avro type  | Julia type       | Example value |
|:-----------|:-----------------|:--------------|
| `null`     | `Missing`        | `missing`     |
| `boolean`  | `Bool`           | `true`        |
| `int`      | `Int32`          | `Int32(42)`   |
| `long`     | `Int64`          | `64`          |
| `float`    | `Float32`        | `Float32(1.5)`|
| `double`   | `Float64`        | `3.14`        |
| `bytes`    | `Vector{UInt8}`  | `UInt8[0x01]` |
| `string`   | `String`         | `"hello"`     |

### Complex types

| Avro type  | Julia type                         | Notes |
|:-----------|:-----------------------------------|:------|
| `record`   | `NamedTuple` or struct (with StructTypes) | Fields correspond to tuple/struct fields |
| `enum`     | `Avro.Enum{(:sym1, :sym2, ...)}`   | Zero-indexed by position |
| `array`    | `Vector{T}`                        | Element type `T` maps to the `items` schema |
| `map`      | `Dict{String, V}`                  | Keys are always strings; value type `V` maps to the `values` schema |
| `union`    | `Union{T1, T2, ...}`               | Written with a leading index to identify the branch |
| `fixed`    | `NTuple{N, UInt8}`                 | A fixed number of bytes |

### Logical types

Logical types are primitive/complex types annotated with a `logicalType` attribute to represent higher-level concepts:

| Avro logical type          | Julia type           | Underlying Avro type |
|:---------------------------|:---------------------|:---------------------|
| `date`                     | `Dates.Date`         | `int`                |
| `time-millis`              | `Dates.Time`         | `int`                |
| `time-micros`              | `Dates.Time`         | `long`               |
| `timestamp-millis`         | `Dates.DateTime`     | `long`               |
| `timestamp-micros`         | `Dates.DateTime`     | `long`               |
| `local-timestamp-millis`   | `Dates.DateTime`     | `long`               |
| `local-timestamp-micros`   | `Dates.DateTime`     | `long`               |
| `uuid`                     | `UUIDs.UUID`         | `string`             |
| `decimal`                  | `Avro.Decimal{S,P}`  | `fixed`              |
| `duration`                 | `Avro.Duration`      | `fixed` (12 bytes)   |

```jldoctest
julia> using Dates, UUIDs

julia> Avro.read(Avro.write(Date(2025, 6, 15)), Date)
2025-06-15

julia> Avro.read(Avro.write(Time(14, 30, 0)), Time)
14:30:00

julia> Avro.read(Avro.write(DateTime(2025, 6, 15, 14, 30)), DateTime)
2025-06-15T14:30:00

julia> dur = Avro.Duration(1, 15, 3600000);  # 1 month, 15 days, 3600000 ms

julia> Avro.read(Avro.write(dur), Avro.Duration)
Avro.Duration(1, 15, 3600000)
```

```julia
# UUIDs round-trip correctly (output varies)
u = uuid4()
Avro.read(Avro.write(u), UUID) == u  # true
```

### Enums

```jldoctest
julia> x = Avro.Enum{(:HEARTS, :DIAMONDS, :CLUBS)}(0);  # HEARTS (zero-indexed)

julia> buf = Avro.write(x);

julia> Avro.read(buf, typeof(x))
HEARTS = 0
```

### Unions

Use Julia `Union` types. When writing, you must pass the union type as the `schema` keyword so the encoder knows all possible branches:

```jldoctest
julia> buf = Avro.write(42; schema=Union{Int, String});

julia> Avro.read(buf, Union{Int, String})
42

julia> buf = Avro.write("hello"; schema=Union{Int, String});

julia> Avro.read(buf, Union{Int, String})
"hello"
```

Nullable values (common in Avro) use `Union{Missing, T}`:

```jldoctest
julia> Row = @NamedTuple{name::String, age::Union{Missing, Int64}};

julia> row = Row(("Alice", 30));

julia> Avro.read(Avro.write(row), typeof(row))
@NamedTuple{name::String, age::Union{Missing, Int64}}(("Alice", 30))

julia> row2 = Row(("Bob", missing));

julia> Avro.read(Avro.write(row2), typeof(row2))
@NamedTuple{name::String, age::Union{Missing, Int64}}(("Bob", missing))
```

---

## Working with Schemas

### Automatic schema derivation

`Avro.schematype(T)` derives an Avro schema from any supported Julia type. You can inspect it as JSON:

```julia
using JSON3

sch = Avro.schematype(typeof((id = Int32(1), name = "Alice")))
JSON3.write(sch)
# {"type":"record","name":"...","fields":[{"name":"id","type":"int"},{"name":"name","type":"string"}]}

# Works with custom structs too
sch = Avro.schematype(Sensor)  # assuming Sensor is defined with StructTypes
```

### Parsing external schemas

Use [`Avro.parseschema`](@ref) to parse an Avro JSON schema string or `.avsc` file. The returned schema object can be passed to `Avro.write` (via `schema=` keyword) and `Avro.read`:

```jldoctest
julia> sch = Avro.parseschema("""
       {
         "type": "record",
         "name": "Measurement",
         "fields": [
           {"name": "sensor_id", "type": "long"},
           {"name": "temp",      "type": "double"},
           {"name": "label",     "type": ["null", "string"]}
         ]
       }
       """);

julia> # Write data using a Julia type that matches the schema
       row = (sensor_id = 42, temp = 21.5, label = "normal");

julia> buf = Avro.write(row; schema=sch);

julia> # Read using the parsed schema — useful when receiver only has the schema
       result = Avro.read(buf, sch);

julia> result.sensor_id
42

julia> result.temp
21.5
```

Note: A `.avsc` file can also be parsed by passing the file path:

```julia
# sch = Avro.parseschema("schema.avsc")
```

### Schema examples in JSON

Here are some common schema patterns for reference. See the [Avro specification](https://avro.apache.org/docs/1.12.0/specification/#schema-declaration) for the full grammar.

**Primitive:**
```json
"string"
```

**Record with nullable field:**
```json
{
  "type": "record",
  "name": "User",
  "fields": [
    {"name": "id",    "type": "long"},
    {"name": "email", "type": ["null", "string"]}
  ]
}
```

**Array of records:**
```json
{
  "type": "array",
  "items": {
    "type": "record",
    "name": "Point",
    "fields": [
      {"name": "x", "type": "double"},
      {"name": "y", "type": "double"}
    ]
  }
}
```

**Enum:**
```json
{
  "type": "enum",
  "name": "Color",
  "symbols": ["RED", "GREEN", "BLUE"]
}
```

**Map (string → double):**
```json
{
  "type": "map",
  "values": "double"
}
```

---

## Code Generation from Schemas

When consuming data defined by external Avro schemas (e.g. `.avsc` files from
other teams or services), you can automatically generate matching Julia structs.

### `generate_code` — Source Code

Generate Julia source code as a `String`, suitable for writing to a file
and including in your project:

```julia
code = Avro.generate_code("""
{
  "type": "record",
  "name": "SensorReading",
  "doc": "A sensor measurement",
  "fields": [
    {"name": "sensor_id", "type": "long"},
    {"name": "temperature", "type": "double"},
    {"name": "location", "type": ["null", "string"]},
    {"name": "tags", "type": {"type": "array", "items": "string"}},
    {"name": "metadata", "type": {"type": "map", "values": "int"}}
  ]
}
""")
println(code)
```

Output:

```julia
using StructTypes

"""A sensor measurement"""
struct SensorReading
    sensor_id::Int64
    temperature::Float64
    location::Union{Missing, String}
    tags::Vector{String}
    metadata::Dict{String, Int32}
end
StructTypes.StructType(::Type{SensorReading}) = StructTypes.Struct()
```

Save to a file for your project:

```julia
write("src/avro_types.jl", code)
```

The input can be a JSON string, a `.avsc` file path, or a parsed schema.
Use `module_name` to wrap definitions in a module:

```julia
code = Avro.generate_code("schema.avsc"; module_name="MyTypes")
```

### `generate_type` — Live Type

Create a Julia type at runtime for interactive or scripting use:

```julia
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
result.x  # 1.0
```

### Nested Records, Enums, and Logical Types

Code generation handles the full Avro type system:

```julia
code = Avro.generate_code("""
{
  "type": "record",
  "name": "Event",
  "fields": [
    {"name": "ts", "type": {"type": "long", "logicalType": "timestamp-millis"}},
    {"name": "uid", "type": {"type": "string", "logicalType": "uuid"}},
    {"name": "status", "type": {"type": "enum", "name": "Status", "symbols": ["ACTIVE", "INACTIVE"]}},
    {"name": "payload", "type": {
      "type": "record",
      "name": "Payload",
      "fields": [{"name": "data", "type": "bytes"}]
    }}
  ]
}
""")
```

Produces structs in dependency order (inner types first), with the correct
`using` imports (`Dates`, `UUIDs`, etc.) automatically included.

---

## Object Container Files (Tables.jl)

Object container files are Avro's standard file format. They embed the schema in the file header and support block-level compression, making them fully self-describing.

### Writing

[`Avro.writetable`](@ref) writes any [Tables.jl](https://github.com/JuliaData/Tables.jl)-compatible source to an Avro container file:

```julia
rows = [
    (id = Int32(1), name = "Alice", score = 95.5),
    (id = Int32(2), name = "Bob",   score = 87.0),
    (id = Int32(3), name = "Carol", score = 91.2),
]

# Write with zstd compression
Avro.writetable("data.avro", rows; compress=:zstd)
```

You can also pass a column table (any Tables.jl source):

```julia
col_table = (id = Int32[1, 2, 3], name = ["Alice", "Bob", "Carol"], score = [95.5, 87.0, 91.2])
Avro.writetable("data.avro", col_table; compress=:deflate)
```

Supported compression codecs: `:deflate`, `:bzip2`, `:xz`, `:zstd`.

### Reading

[`Avro.readtable`](@ref) reads an Avro container file and returns an [`Avro.Table`](@ref), which implements the Tables.jl row interface:

```julia
tbl = Avro.readtable("data.avro")

# Index into rows
tbl[1]        # first record
tbl[1].name   # "Alice"

# Iterate
for row in tbl
    println(row.name, ": ", row.score)
end

length(tbl)   # number of records
```

### Converting to other formats

Because `Avro.Table` is a Tables.jl source, it plugs into the entire Julia data ecosystem:

```julia
using DataFrames
df = DataFrame(Avro.readtable("data.avro"))

using CSV
CSV.write("data.csv", Avro.readtable("data.avro"))

using Arrow
Arrow.write("data.arrow", Avro.readtable("data.avro"))
```

### In-memory round trip with `tobuffer`

[`Avro.tobuffer`](@ref) is a convenience function that writes to an `IOBuffer` instead of a file — useful for testing and in-memory pipelines:

```julia
io = Avro.tobuffer(rows; compress=:zstd)
tbl = Avro.readtable(io)
```

---

## Kafka Integration (with RDKafka.jl)

[Apache Kafka](https://kafka.apache.org/) is a distributed streaming platform frequently paired with Avro for compact, schema-aware message serialization. Julia's Kafka client is [RDKafka.jl](https://github.com/dfdx/RDKafka.jl), a wrapper around `librdkafka`.

Avro.jl does not depend on Kafka, but combined with RDKafka.jl you can produce and consume Avro-encoded messages with a few lines of code.

### Setup

```julia
using Pkg
Pkg.add("RDKafka")  # Kafka client (install once)
```

### Producer: serialize and publish

```julia
using Avro, RDKafka
import RDKafka: produce

# Define your schema / data type
struct SensorReading
    sensor_id::Int
    temperature::Float64
    timestamp::Int       # Unix millis
end
# (assumes StructTypes.StructType already declared for SensorReading)

# Serialize to Avro bytes
reading = SensorReading(42, 21.5, 1_718_400_000_000)
payload = Avro.write(reading)

# Publish to Kafka
p = KafkaProducer("localhost:9092")
produce(p, "sensor-readings", 0, "sensor-42", payload)
```

### Consumer: receive and deserialize

```julia
using Avro, RDKafka

c = KafkaConsumer("localhost:9092", "my-group")
subscribe(c, [("sensor-readings", 0)])

while true
    msg = poll(Vector{UInt8}, Vector{UInt8}, c, 1000)
    if msg !== nothing
        reading = Avro.read(msg.value, SensorReading)
        println("Sensor $(reading.sensor_id): $(reading.temperature)°C")
    end
end
```

### Using a shared schema

When producer and consumer are separate services, you typically share the Avro schema (a `.avsc` file) rather than Julia type definitions. The consumer can parse the schema and read any compliant data:

```julia
# Consumer side — no need for the SensorReading struct
sch = Avro.parseschema("sensor_reading.avsc")
reading = Avro.read(msg.value, sch)
# `reading` is an Avro.Record — access fields like reading.sensor_id
```

!!! note "Schema Registry"
    Avro.jl does **not** implement the [Confluent Schema Registry](https://docs.confluent.io/platform/current/schema-registry/) wire format (magic byte + 4-byte schema ID prefix). If your Kafka cluster uses Schema Registry, you will need to strip the 5-byte prefix before passing the payload to `Avro.read`, and prepend it when producing. A minimal helper:

    ```julia
    # Strip 5-byte Confluent header (byte 0x00 + 4-byte schema ID)
    raw_avro = msg.value[6:end]
    reading = Avro.read(raw_avro, sch)
    ```

---

## API Reference

```@index
```

```@autodocs
Modules = [Avro]
```
