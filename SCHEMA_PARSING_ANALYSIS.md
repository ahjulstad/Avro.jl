# Avro.jl Schema Parsing Analysis

## Issue Summary

When a schema is parsed from JSON using `Avro.parseschema()`, field types are stored as strings (e.g., "long", "string", "double") rather than converted to `SchemaType` objects. This causes `MethodError: no method matching nbytes(::String, ...)` when attempting to write data using a parsed schema.

## Root Cause

### How Schema Parsing Works

1. `Avro.parseschema()` uses `JSON3.read(buf, Avro.Schema)` to parse JSON
2. The returned schema contains `RecordType` objects with `FieldType` objects
3. Each `FieldType` has a `type::Schema` field, where `Schema = Union{String, LogicalType, SchemaType, UnionType}`
4. **When parsed from JSON, primitive types remain as strings** (e.g., "long", "string") rather than being converted to `PrimitiveType` objects

### The Missing Fallback Method

In [binary.jl](src/types/binary.jl), fallback methods exist for `readvalue` and `skipvalue` to handle String schemas:

```julia
readvalue(B::Binary, sch::String, ::Type{T}, buf, pos, len, opts) where {T} =
    readvalue(B, PrimitiveType(sch), T, buf, pos, len, opts)
skipvalue(B::Binary, sch::String, ::Type{T}, buf, pos, len, opts) where {T} =
    skipvalue(B, PrimitiveType(sch), T, buf, pos, len, opts)
```

However, **no corresponding fallback exists for `nbytes`**. This creates an asymmetry where:
- ✅ Reading works: `readvalue` converts string schemas to `PrimitiveType`
- ✅ Writing works: `writevalue` uses `schematype()` to convert schemas
- ❌ Byte counting fails: `nbytes` has no method for `String` schemas

### Where the Error Occurs

The error chain:
1. `Avro.write(row; schema=parsed_schema)` is called
2. `write()` calls `nbytes(sch, obj)` to allocate the buffer
3. For a `RecordType`, `nbytes` calls `NBytesClosure`, which iterates field types
4. For each field, it calls `nbytes(f.RT.fields[i].type, v)` where `.type` is a String
5. **No `nbytes` method matches `(String, value_type)` → MethodError**

## Reproduction

```julia
using Avro

sch = Avro.parseschema("""
{
  "type": "record",
  "name": "Test",
  "fields": [
    {"name": "id", "type": "long"},
    {"name": "name", "type": "string"}
  ]
}
""")

row = (id = Int64(42), name = "test")
buf = Avro.write(row; schema=sch)  # ❌ ERROR: MethodError: no method matching nbytes(::String, ::Int64)
```

## Analysis Summary

### Is this a Known Bug or Expected Behavior?

**This is a genuine bug**, not expected behavior. The documentation explicitly shows that parsed schemas should work seamlessly with `Avro.write()` and `Avro.read()`:

> Use [`Avro.parseschema`](@ref) to parse an Avro JSON schema string or `.avsc` file. The returned schema object can be passed to `Avro.write` (via `schema=` keyword) and `Avro.read`

The asymmetry between working `readvalue`/`writevalue` and missing `nbytes` indicates incomplete implementation of schema type normalization.

### How Schemas Are Supposed to Be Normalized

The codebase uses a **conversion-on-use approach** rather than post-parsing normalization:

1. `PrimitiveType(x::String)` converts string names to `SchemaType`:
   ```julia
   PrimitiveType(x::String) = schematype(juliatype(x))
   ```

2. Functions that need schema types use the pattern:
   ```julia
   function readvalue(B::Binary, sch::String, ::Type{T}, ...)
       readvalue(B, PrimitiveType(sch), T, ...)  # Convert on use
   end
   ```

3. This approach is applied consistently in `readvalue` and `skipvalue`, but **missing in `nbytes`**.

### The Fix

Add a fallback method for `nbytes` that mirrors existing fallbacks:

```julia
nbytes(sch::String, x) = nbytes(PrimitiveType(sch), x)
```

**Location**: [src/types/binary.jl](src/types/binary.jl), after line 83 (after the other fallback methods)

**Why this works**: 
- `PrimitiveType(sch)` converts "long", "string", etc. to proper `LongType`, `StringType` objects
- The corresponding `nbytes` method exists for all primitive types
- This follows the established pattern used successfully in `readvalue` and `skipvalue`

## Code Flow Implications

### Affected Code Paths

1. **Direct write with parsed schema** ❌ Currently broken
   ```julia
   sch = parseschema(json_str)
   Avro.write(data; schema=sch)  # Fails in nbytes
   ```

2. **Nested types** ❌ Arrays and Maps with parsed schemas fail similarly
   ```julia
   # When ArrayType.items or MapType.values is a string schema
   nbytes(A::ArrayType, x) → nbytes(A.items, y)  # Fails if A.items is String
   ```

3. **Read operations** ✅ Work fine (fallback exists in readvalue)

4. **Writing when schema derived from Julia type** ✅ Works fine (no string schemas)

## Recommendation

The fix should be implemented by adding one line to [src/types/binary.jl](src/types/binary.jl):

```julia
nbytes(sch::String, x) = nbytes(PrimitiveType(sch), x)
```

This maintains consistency with the existing `readvalue` and `skipvalue` fallback pattern and enables parsed schemas to work seamlessly throughout the library.

### Testing

After applying the fix, the reproduction case above should work:

```julia
sch = Avro.parseschema("""...""")
row = (id = Int64(42), name = "test")
buf = Avro.write(row; schema=sch)      # ✅ Should work
result = Avro.read(buf, sch)           # ✅ Already works
```
