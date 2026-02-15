"""
    Avro.generate_code(schema_or_file; module_name=nothing) -> String

Generate Julia source code (struct definitions + StructTypes declarations) from
an Avro schema. The input can be:
- A file path to a `.avsc` file
- A JSON string containing an Avro schema
- An already-parsed `Avro.Schema` object

Returns a `String` of valid Julia code that defines structs corresponding to
all record and enum types in the schema, with appropriate `StructTypes`
declarations so they work directly with `Avro.read` and `Avro.write`.

# Examples

```julia
code = Avro.generate_code(\"\"\"
{
  "type": "record",
  "name": "SensorReading",
  "fields": [
    {"name": "sensor_id", "type": "long"},
    {"name": "temperature", "type": "double"},
    {"name": "location", "type": ["null", "string"]}
  ]
}
\"\"\")
println(code)
# struct SensorReading
#     sensor_id::Int64
#     temperature::Float64
#     location::Union{Missing, String}
# end
# StructTypes.StructType(::Type{SensorReading}) = StructTypes.Struct()

# Write to a file for your project
write("src/avro_types.jl", code)
```

See also [`Avro.generate_type`](@ref).
"""
function generate_code(schema_or_file; module_name::Union{Nothing, String}=nothing)
    sch = _to_schema(schema_or_file)
    # Collect all named types in dependency order
    named_types = OrderedTypeCollector()
    _collect_named_types!(named_types, sch)
    # Determine which imports are needed
    imports = _required_imports(named_types)
    # Generate code
    io = IOBuffer()
    # Imports
    if !isempty(imports)
        println(io, "using ", join(sort(collect(imports)), ", "))
        println(io)
    end
    # Module wrapper
    if module_name !== nothing
        println(io, "module $module_name")
        println(io)
        if !isempty(imports)
            println(io, "using ", join(sort(collect(imports)), ", "))
            println(io)
        end
    end
    # Emit types
    for (name, entry) in named_types.types
        _emit_type!(io, entry)
        println(io)
    end
    if module_name !== nothing
        println(io, "end # module $module_name")
    end
    return String(take!(io))
end

"""
    Avro.generate_type(schema_or_file) -> Type

Generate Julia types at runtime from an Avro schema file, JSON string, or
parsed `Avro.Schema` object. Returns the root Julia type, ready for use with
`Avro.read` and `Avro.write`.

Unlike [`Avro.generate_code`](@ref) which returns source code as a string,
this function evaluates the generated types immediately into an anonymous module,
making it convenient for interactive and scripting use.

# Examples

```julia
T = Avro.generate_type(\"\"\"
{
  "type": "record",
  "name": "Point",
  "fields": [
    {"name": "x", "type": "double"},
    {"name": "y", "type": "double"}
  ]
}
\"\"\")

buf = Avro.write((x = 1.0, y = 2.0))
p = Avro.read(buf, T)
p.x  # 1.0
p.y  # 2.0
```

See also [`Avro.generate_code`](@ref).
"""
function generate_type(schema_or_file)
    sch = _to_schema(schema_or_file)
    named_types = OrderedTypeCollector()
    _collect_named_types!(named_types, sch)

    # Create a fresh module to eval into
    mod = Module(gensym("AvroGenerated"))
    Base.eval(mod, :(using Avro, StructTypes, Dates, UUIDs))

    root_type = nothing
    for (name, entry) in named_types.types
        code = _emit_type_string(entry)
        T = Base.eval(mod, Meta.parse("begin\n$code\nend"))
        root_type = T  # last one is the root
    end

    # For non-record schemas, just return juliatype
    if isempty(named_types.types)
        return juliatype(sch)
    end

    # Return the root type (the top-level type from the schema)
    root_name = _root_type_name(sch)
    if root_name !== nothing
        return Base.eval(mod, Symbol(root_name))
    end
    return root_type
end

# ---------- Internal helpers ----------

function _to_schema(x)
    if x isa AbstractString
        # Determine if this is a file path or JSON text.
        # JSON schemas always start with '{', '[', or '"' (after whitespace).
        stripped = lstrip(x)
        is_json = !isempty(stripped) && stripped[1] in ('{', '[', '"')
        if !is_json && isfile(x)
            return parseschema(x)
        end
        # Parse as JSON directly
        return JSON3.read(codeunits(x), Schema)
    elseif x isa Schema
        return x
    else
        throw(ArgumentError("expected a file path, JSON string, or Avro.Schema; got $(typeof(x))"))
    end
end

function _root_type_name(sch)
    if sch isa RecordType
        return _sanitize_name(sch.name)
    elseif sch isa EnumType
        return _sanitize_name(sch.name)
    end
    return nothing
end

# Ordered collector to gather named types in dependency order
struct NamedTypeEntry
    schema::Union{RecordType, EnumType}
end

mutable struct OrderedTypeCollector
    types::Vector{Pair{String, NamedTypeEntry}}
    seen::Set{String}
end
OrderedTypeCollector() = OrderedTypeCollector(Pair{String, NamedTypeEntry}[], Set{String}())

function _add_type!(c::OrderedTypeCollector, name::String, entry::NamedTypeEntry)
    if name ∉ c.seen
        push!(c.seen, name)
        push!(c.types, name => entry)
    end
end

# Recursively collect all named types in dependency-first order
function _collect_named_types!(c::OrderedTypeCollector, sch::RecordType)
    # First collect dependencies from fields
    for field in sch.fields
        _collect_named_types!(c, field.type)
    end
    # Then add self
    _add_type!(c, sch.name, NamedTypeEntry(sch))
end

function _collect_named_types!(c::OrderedTypeCollector, sch::EnumType)
    _add_type!(c, sch.name, NamedTypeEntry(sch))
end

function _collect_named_types!(c::OrderedTypeCollector, sch::ArrayType)
    _collect_named_types!(c, sch.items)
end

function _collect_named_types!(c::OrderedTypeCollector, sch::MapType)
    _collect_named_types!(c, sch.values)
end

function _collect_named_types!(c::OrderedTypeCollector, sch::FixedType)
    # No code generation needed for fixed types (NTuple{N, UInt8})
end

function _collect_named_types!(c::OrderedTypeCollector, sch::UnionType)
    for branch in sch
        _collect_named_types!(c, branch)
    end
end

function _collect_named_types!(c::OrderedTypeCollector, sch::LogicalType)
    # Logical types map to built-in Julia types; no codegen needed
end

function _collect_named_types!(c::OrderedTypeCollector, sch::PrimitiveType)
    # Nothing to collect
end

function _collect_named_types!(c::OrderedTypeCollector, sch::String)
    # Primitive type name string; nothing to collect
end

# Map a schema to a Julia type string for use in struct fields
function _julia_type_str(sch::Schema)::String
    return _julia_type_str_impl(sch)
end

function _julia_type_str_impl(sch::String)
    sch == "null"    && return "Missing"
    sch == "boolean" && return "Bool"
    sch == "int"     && return "Int32"
    sch == "long"    && return "Int64"
    sch == "float"   && return "Float32"
    sch == "double"  && return "Float64"
    sch == "bytes"   && return "Vector{UInt8}"
    sch == "string"  && return "String"
    # Could be a named type reference
    return _sanitize_name(sch)
end

function _julia_type_str_impl(::NullType)
    return "Missing"
end

function _julia_type_str_impl(::BooleanType)
    return "Bool"
end

function _julia_type_str_impl(::IntType)
    return "Int32"
end

function _julia_type_str_impl(::LongType)
    return "Int64"
end

function _julia_type_str_impl(::FloatType)
    return "Float32"
end

function _julia_type_str_impl(::DoubleType)
    return "Float64"
end

function _julia_type_str_impl(::BytesType)
    return "Vector{UInt8}"
end

function _julia_type_str_impl(::StringType)
    return "String"
end

function _julia_type_str_impl(sch::RecordType)
    return _sanitize_name(sch.name)
end

function _julia_type_str_impl(sch::EnumType)
    return _sanitize_name(sch.name)
end

function _julia_type_str_impl(sch::ArrayType)
    return "Vector{$(_julia_type_str(sch.items))}"
end

function _julia_type_str_impl(sch::MapType)
    return "Dict{String, $(_julia_type_str(sch.values))}"
end

function _julia_type_str_impl(sch::FixedType)
    return "NTuple{$(sch.size), UInt8}"
end

function _julia_type_str_impl(sch::UnionType)
    parts = [_julia_type_str(s) for s in sch]
    if length(parts) == 1
        return parts[1]
    end
    return "Union{$(join(parts, ", "))}"
end

# Logical types
_julia_type_str_impl(::UUIDType) = "UUID"
_julia_type_str_impl(::DateType) = "Date"
_julia_type_str_impl(::TimeMillisType) = "Time"
_julia_type_str_impl(::TimeMicrosType) = "Time"
_julia_type_str_impl(::TimestampMillisType) = "DateTime"
_julia_type_str_impl(::TimestampMicrosType) = "DateTime"
_julia_type_str_impl(::LocalTimestampMillisType) = "DateTime"
_julia_type_str_impl(::LocalTimestampMicrosType) = "DateTime"
_julia_type_str_impl(::DurationType) = "Avro.Duration"

function _julia_type_str_impl(sch::DecimalType)
    return "Avro.Decimal{$(sch.scale), $(sch.precision)}"
end

# Sanitize an Avro name to be a valid Julia identifier.
# Strips namespace prefix (everything up to the last dot).
function _sanitize_name(name::String)
    # Use only the short name (after last dot)
    idx = findlast('.', name)
    short = idx === nothing ? name : name[idx+1:end]
    # Replace any non-identifier characters with underscore
    s = replace(short, r"[^A-Za-z0-9_]" => "_")
    # Ensure it starts with a letter or underscore
    if !isempty(s) && !occursin(r"^[A-Za-z_]", s)
        s = "_" * s
    end
    return s
end

# Determine which packages need to be imported
function _required_imports(c::OrderedTypeCollector)
    imports = Set{String}(["StructTypes"])
    for (_, entry) in c.types
        _scan_imports!(imports, entry.schema)
    end
    return imports
end

function _scan_imports!(imports::Set{String}, sch::RecordType)
    for field in sch.fields
        _scan_imports!(imports, field.type)
    end
end

function _scan_imports!(imports::Set{String}, sch::EnumType)
    # Enums need Avro for Avro.Enum if we use that, but we generate @enum instead
end

function _scan_imports!(imports::Set{String}, sch::ArrayType)
    _scan_imports!(imports, sch.items)
end

function _scan_imports!(imports::Set{String}, sch::MapType)
    _scan_imports!(imports, sch.values)
end

function _scan_imports!(imports::Set{String}, sch::UnionType)
    for branch in sch
        _scan_imports!(imports, branch)
    end
end

function _scan_imports!(imports::Set{String}, sch::FixedType) end
function _scan_imports!(imports::Set{String}, sch::PrimitiveType) end
function _scan_imports!(imports::Set{String}, sch::String) end

# Logical types require specific imports
function _scan_imports!(imports::Set{String}, ::UUIDType)
    push!(imports, "UUIDs")
end

function _scan_imports!(imports::Set{String}, ::DateType)
    push!(imports, "Dates")
end

function _scan_imports!(imports::Set{String}, ::TimeMillisType)
    push!(imports, "Dates")
end

function _scan_imports!(imports::Set{String}, ::TimeMicrosType)
    push!(imports, "Dates")
end

function _scan_imports!(imports::Set{String}, ::TimestampMillisType)
    push!(imports, "Dates")
end

function _scan_imports!(imports::Set{String}, ::TimestampMicrosType)
    push!(imports, "Dates")
end

function _scan_imports!(imports::Set{String}, ::LocalTimestampMillisType)
    push!(imports, "Dates")
end

function _scan_imports!(imports::Set{String}, ::LocalTimestampMicrosType)
    push!(imports, "Dates")
end

function _scan_imports!(imports::Set{String}, ::DurationType) end
function _scan_imports!(imports::Set{String}, ::DecimalType) end

# Emit code for a named type entry
function _emit_type!(io::IO, entry::NamedTypeEntry)
    _emit_type_to_io!(io, entry.schema)
end

function _emit_type_string(entry::NamedTypeEntry)
    io = IOBuffer()
    _emit_type_to_io!(io, entry.schema)
    return String(take!(io))
end

function _emit_type_to_io!(io::IO, sch::RecordType)
    name = _sanitize_name(sch.name)
    # Docstring
    if sch.doc !== nothing && !isempty(sch.doc)
        println(io, "\"\"\"", sch.doc, "\"\"\"")
    end
    # Struct definition
    println(io, "struct $name")
    for field in sch.fields
        field_name = _sanitize_field_name(field.name)
        field_type = _julia_type_str(field.type)
        if field.doc !== nothing && !isempty(field.doc)
            println(io, "    # ", field.doc)
        end
        println(io, "    $field_name::$field_type")
    end
    println(io, "end")
    # StructTypes declaration
    println(io, "StructTypes.StructType(::Type{$name}) = StructTypes.Struct()")
    # If any field name was sanitized, emit a name mapping
    mappings = Pair{String, String}[]
    for field in sch.fields
        sanitized = _sanitize_field_name(field.name)
        if sanitized != field.name
            push!(mappings, sanitized => field.name)
        end
    end
    if !isempty(mappings)
        pairs_str = join(["$(Symbol(m.first)) = :$(Symbol(m.second))" for m in mappings], ", ")
        println(io, "StructTypes.names(::Type{$name}) = (($pairs_str),)")
    end
end

function _emit_type_to_io!(io::IO, sch::EnumType)
    name = _sanitize_name(sch.name)
    if sch.doc !== nothing && !isempty(sch.doc)
        println(io, "\"\"\"", sch.doc, "\"\"\"")
    end
    syms = join(sch.symbols, ", ")
    println(io, "const $name = Avro.Enum{($(join([":" * s for s in sch.symbols], ", ")),)}")
    println(io, "# Symbols: $syms")
end

# Sanitize field names
function _sanitize_field_name(name::String)
    s = replace(name, r"[^A-Za-z0-9_]" => "_")
    if !isempty(s) && !occursin(r"^[A-Za-z_]", s)
        s = "_" * s
    end
    # Avoid Julia reserved words
    if s in ("end", "begin", "function", "macro", "module", "struct",
             "abstract", "mutable", "primitive", "type", "if", "else",
             "elseif", "for", "while", "try", "catch", "finally",
             "return", "break", "continue", "import", "using", "export",
             "const", "let", "do", "in", "global", "local", "true", "false")
        s = s * "_"
    end
    return s
end
