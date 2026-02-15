# Avro.jl

[![Stable](https://img.shields.io/badge/docs-stable-blue.svg)](https://juliadata.github.io/Avro.jl/stable)
[![Dev](https://img.shields.io/badge/docs-dev-blue.svg)](https://juliadata.github.io/Avro.jl/dev)
[![CI](https://github.com/JuliaData/Avro.jl/workflows/CI/badge.svg)](https://github.com/JuliaData/Avro.jl/actions?query=workflow%3ACI)
[![codecov](https://codecov.io/gh/JuliaData/Avro.jl/branch/main/graph/badge.svg)](https://codecov.io/gh/JuliaData/Avro.jl)

A pure Julia implementation of the [Apache Avro](https://avro.apache.org/docs/1.12.0/specification/) data serialization standard.

## What is Avro?

[Apache Avro](https://avro.apache.org/) is a compact, fast, schema-driven binary data format. Unlike columnar formats such as Arrow or Parquet, Avro is **row-oriented** — each record is serialized independently, making it a natural fit for streaming workloads like [Apache Kafka](https://kafka.apache.org/). Every piece of Avro data is written against a JSON schema, and Avro's *Object Container Files* embed the schema in the file itself so the data is fully self-describing. See the [Avro specification](https://avro.apache.org/docs/1.12.0/specification/) for full details.

## Installation

```julia
using Pkg
Pkg.add("Avro")
```

## Quick Start

### Simple round-trip (write → read)

```julia
using Avro

# --- Primitive values ---
buf = Avro.write(42)
Avro.read(buf, Int)  # 42

buf = Avro.write("hello, avro")
Avro.read(buf, String)  # "hello, avro"

# --- Named tuples (serialized as Avro records) ---
row = (id = Int32(1), name = "Alice", score = 95.5)
buf = Avro.write(row)
Avro.read(buf, typeof(row))  # (id = 1, name = "Alice", score = 95.5)

# --- Vectors / arrays ---
xs = [1, 2, 3]
Avro.read(Avro.write(xs), typeof(xs))  # [1, 2, 3]

# --- Custom structs (requires StructTypes) ---
using StructTypes

struct Sensor
    id::Int
    location::String
end
StructTypes.StructType(::Type{Sensor}) = StructTypes.Struct()

s = Sensor(7, "roof")
Avro.read(Avro.write(s), Sensor)  # Sensor(7, "roof")
```

### Object container files (Tables.jl integration)

Avro *object container files* bundle the schema together with the data and support compression. Any [Tables.jl](https://github.com/JuliaData/Tables.jl)-compatible source can be written, and the resulting `Avro.Table` can be sent to any Tables.jl sink.

```julia
using Avro

rows = [
    (id = Int32(1), name = "Alice", score = 95.5),
    (id = Int32(2), name = "Bob",   score = 87.0),
    (id = Int32(3), name = "Carol", score = 91.2),
]

# Write to an Avro container file with zstd compression
Avro.writetable("data.avro", rows; compress=:zstd)

# Read it back — schema is embedded in the file
tbl = Avro.readtable("data.avro")
tbl[1].name  # "Alice"

# Convert to other formats via Tables.jl
# using DataFrames; DataFrame(tbl)
# using CSV;        CSV.write("data.csv", tbl)
# using Arrow;      Arrow.write("data.arrow", tbl)
```

Supported compression codecs: `:deflate`, `:bzip2`, `:xz`, `:zstd`.

### Working with Avro schemas

Schemas can be derived automatically from Julia types, or parsed from JSON strings / `.avsc` files:

```julia
using Avro, JSON3

# Auto-derive an Avro schema from a Julia type
sch = Avro.schematype(typeof((id = Int32(1), name = "Alice")))
JSON3.write(sch)
# {"type":"record","name":"...","fields":[{"name":"id","type":"int"},{"name":"name","type":"string"}]}

# Parse an external Avro schema (JSON string or .avsc file)
sch = Avro.parseschema("""
{
  "type": "record",
  "name": "Sensor",
  "fields": [
    {"name": "id",       "type": "long"},
    {"name": "location", "type": "string"}
  ]
}
""")

# Use the parsed schema to read raw Avro bytes
buf = Avro.write((id = 7, location = "roof"))
Avro.read(buf, sch)
```

For the full schema-to-Julia-type mapping, Kafka integration examples, and more, see the **[full documentation](https://juliadata.github.io/Avro.jl/stable)**.

## Implementation status

Supported:

  * All primitive types
  * All nested/complex types (records, enums, arrays, maps, unions, fixed)
  * Logical types listed in the spec (Decimal, UUID, Date, Time, Timestamps, Duration)
  * Binary encoding/decoding
  * Reading/writing object container files via the Tables.jl interface
  * Compression codecs: xz, zstd, deflate, bzip2

Not yet supported:

  * JSON encoding/decoding of objects
  * Single object encoding or schema fingerprints
  * Schema resolution
  * Protocol messages, calls, handshakes
  * Snappy compression

## Why Avro?

  * **Compact** — binary encoding with optional compression yields very small files
  * **Fast** — minimal overhead for reading and writing
  * **Schema-enforced** — data always has a well-defined schema
  * **Row-oriented** — one of the few binary formats that stores data row-by-row, making it ideal for streaming and append-heavy workloads
  * **Self-describing** — object container files embed the schema, so any reader can process the data without external metadata
