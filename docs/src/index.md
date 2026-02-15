```@meta
CurrentModule = Avro
DocTestSetup = :(using Avro, StructTypes)
```

# Avro.jl

A pure Julia implementation of the [Apache Avro](https://avro.apache.org/) data serialization format.

## What is Avro?

Apache Avro is a compact binary serialization format where every piece of data has a well-defined **schema**.
Key properties:

- **Schema-driven** — data structure is always known, enabling validation and evolution
- **Compact binary encoding** — smaller and faster than JSON or XML
- **Row-oriented** — efficient for streaming and message passing (e.g. Kafka)
- **Language-neutral** — schemas in JSON, implementations in many languages

## Quick Start

### Primitives

Write any Julia value to Avro binary and read it back:

```jldoctest
julia> buf = Avro.write(42);

julia> Avro.read(buf, Int)
42

julia> buf = Avro.write("hello, Avro!");

julia> Avro.read(buf, String)
"hello, Avro!"
```

### Records (NamedTuples)

NamedTuples map directly to Avro records:

```jldoctest
julia> record = (name = "Alice", age = Int32(30));

julia> buf = Avro.write(record);

julia> Avro.read(buf, typeof(record))
(name = "Alice", age = 30)
```

### Arrays

```jldoctest
julia> data = [1.0, 2.0, 3.0];

julia> Avro.read(Avro.write(data), Vector{Float64})
3-element Vector{Float64}:
 1.0
 2.0
 3.0
```

### Custom Structs

Use [StructTypes.jl](https://github.com/JuliaData/StructTypes.jl) to make your own types Avro-compatible:

```jldoctest sensor
julia> using StructTypes

julia> struct Sensor
           id::String
           value::Float64
       end

julia> StructTypes.StructType(::Type{Sensor}) = StructTypes.Struct()

julia> s = Sensor("temp-1", 23.5);

julia> Avro.read(Avro.write(s), Sensor)
Sensor("temp-1", 23.5)
```

## Schema & Type Mapping

Avro schemas (JSON) map to Julia types as follows:

| Avro type    | Julia type                      |
|:-------------|:--------------------------------|
| `null`       | `Missing`                       |
| `boolean`    | `Bool`                          |
| `int`        | `Int32`                         |
| `long`       | `Int64` / `Int`                 |
| `float`      | `Float32`                       |
| `double`     | `Float64`                       |
| `bytes`      | `Vector{UInt8}`                 |
| `string`     | `String`                        |
| `enum`       | `Avro.Enum{(:SYM1, :SYM2)}`    |
| `array`      | `Vector{T}`                     |
| `map`        | `Dict{String, T}`              |
| `fixed`      | `NTuple{N, UInt8}`              |
| `record`     | `NamedTuple` or custom struct   |
| `union`      | `Union{T1, T2, ...}`           |

### Logical Types

| Avro logical type       | Julia type            |
|:------------------------|:----------------------|
| `date`                  | `Dates.Date`          |
| `time-millis`           | `Dates.Time`          |
| `time-micros`           | `Dates.Time`          |
| `timestamp-millis`      | `Dates.DateTime`      |
| `timestamp-micros`      | `Dates.DateTime`      |
| `uuid`                  | `UUIDs.UUID`          |
| `decimal`               | `Avro.Decimal{S,P}`   |
| `duration`              | `Avro.Duration`       |

### Logical Types Example

```jldoctest
julia> using Dates

julia> d = Date(2024, 6, 15);

julia> Avro.read(Avro.write(d), Date)
2024-06-15
```

### Enums

```jldoctest
julia> color = Avro.Enum{(:RED, :GREEN, :BLUE)}(0);  # RED

julia> Avro.read(Avro.write(color), typeof(color))
RED = 0
```

### Unions (Nullable Fields)

Avro `["null", "string"]` maps to `Union{Missing, String}`:

```jldoctest
julia> record = @NamedTuple{name::String, email::Union{Missing, String}}(("Alice", "alice@example.com"));

julia> Avro.read(Avro.write(record), typeof(record))
@NamedTuple{name::String, email::Union{Missing, String}}(("Alice", "alice@example.com"))
```

```jldoctest
julia> empty = @NamedTuple{name::String, email::Union{Missing, String}}(("Bob", missing));

julia> result = Avro.read(Avro.write(empty), typeof(empty));

julia> ismissing(result.email)
true
```

## Working with Schemas

### Parsing Schemas

Parse an Avro JSON schema and use it to read data:

```julia
schema = Avro.parseschema("""
{
  "type": "record",
  "name": "User",
  "fields": [
    {"name": "name", "type": "string"},
    {"name": "age", "type": "int"},
    {"name": "email", "type": ["null", "string"]}
  ]
}
""")

# Read data using the parsed schema
user = Avro.read(buf, schema)
```

### Deriving Schemas from Julia Types

Avro.jl can derive a schema from any Julia type:

```julia
schema = Avro.schematype(typeof((name="Alice", age=Int32(30))))
# RecordType with fields name::string, age::int
```

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

\"\"\"A sensor measurement\"\"\"
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

## Object Container Files (Tables.jl)

Avro [object container files](https://avro.apache.org/docs/1.12.0/specification/#object-container-files)
embed the schema alongside the data. Avro.jl provides a Tables.jl interface:

```julia
using Tables

# Write table data (any Tables.jl source)
data = [(name="Alice", score=95), (name="Bob", score=87)]
io = Avro.tobuffer(data)                                # in-memory
Avro.writetable("data.avro", data)                      # to a file
Avro.writetable("data.avro", data; compress=:zstd)      # compressed

# Read back
tbl = Avro.readtable("data.avro")   # returns a Tables.jl-compatible table
```

Supported compression codecs: `:deflate`, `:bzip2`, `:xz`, `:zstd`.

### Integration with DataFrames

```julia
using DataFrames
df = DataFrame(Avro.readtable("data.avro"))
```

## Kafka Integration (RDKafka.jl)

Avro is the standard serialization format for Apache Kafka.
Use [RDKafka.jl](https://github.com/zendesk/RDKafka.jl) alongside Avro.jl:

### Producer

```julia
using RDKafka, Avro, StructTypes

struct SensorReading
    sensor_id::String
    temperature::Float64
end
StructTypes.StructType(::Type{SensorReading}) = StructTypes.Struct()

producer = RDKafka.Producer("localhost:9092")
topic = RDKafka.Topic(producer, "sensor-data")

reading = SensorReading("temp-1", 23.5)
payload = Avro.write(reading)
RDKafka.produce(topic, payload)
```

### Consumer

```julia
consumer = RDKafka.KafkaConsumer("localhost:9092", "my-group")
RDKafka.subscribe(consumer, ["sensor-data"])

for msg in consumer
    reading = Avro.read(msg.payload, SensorReading)
    println("Sensor \$(reading.sensor_id): \$(reading.temperature)°C")
end
```

!!! note "Schema Registry"
    In production Kafka deployments you'd typically use a Confluent Schema Registry
    to manage schema evolution. The producer prepends a 5-byte header
    (magic byte + 4-byte schema ID) to each message. Schema registry support is
    planned for a future Avro.jl release.

## API Reference

```@index
```

```@autodocs
Modules = [Avro]
```
