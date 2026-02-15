#!/usr/bin/env python3
"""
Performance benchmark for the Python avro library (avro-python3).
Matches the operations tested in bench_julia.jl for fair comparison.
"""

import io
import json
import os
import sys
import tempfile
import time


def bench(f, n, warmup=3):
    """Time function f over n iterations, return total seconds."""
    for _ in range(warmup):
        f()
    t0 = time.perf_counter()
    for _ in range(n):
        f()
    t1 = time.perf_counter()
    return t1 - t0


def main():
    import avro.schema
    import avro.io
    import avro.datafile

    print("=" * 70)
    print("Python avro (avro-python3) Performance Benchmark")
    print("=" * 70)

    results = {}

    # =========================================================================
    # Benchmark 1: Simple record write/read (single record, many iterations)
    # =========================================================================
    print("\n--- Benchmark 1: Simple Record Serialization (single record) ---")

    simple_schema = avro.schema.parse(json.dumps({
        "type": "record",
        "name": "SimpleRecord",
        "fields": [
            {"name": "name", "type": "string"},
            {"name": "age", "type": "int"},
            {"name": "score", "type": "double"},
            {"name": "active", "type": "boolean"},
        ]
    }))
    simple_record = {"name": "Alice Johnson", "age": 30, "score": 95.5, "active": True}
    n_iters = 100_000

    # Write
    def write_simple():
        buf = io.BytesIO()
        encoder = avro.io.BinaryEncoder(buf)
        writer = avro.io.DatumWriter(simple_schema)
        writer.write(simple_record, encoder)
        return buf.getvalue()

    t = bench(write_simple, n_iters)
    rate_w = n_iters / t
    print(f"  Write: {n_iters} records in {t:.4f}s ({rate_w:.0f} records/s)")
    results["simple_write_rate"] = rate_w

    # Read
    encoded = write_simple()

    def read_simple():
        buf = io.BytesIO(encoded)
        decoder = avro.io.BinaryDecoder(buf)
        reader = avro.io.DatumReader(simple_schema)
        return reader.read(decoder)

    t = bench(read_simple, n_iters)
    rate_r = n_iters / t
    print(f"  Read:  {n_iters} records in {t:.4f}s ({rate_r:.0f} records/s)")
    results["simple_read_rate"] = rate_r

    # =========================================================================
    # Benchmark 2: Complex record with nested types
    # =========================================================================
    print("\n--- Benchmark 2: Complex Record Serialization ---")

    complex_schema = avro.schema.parse(json.dumps({
        "type": "record",
        "name": "ComplexRecord",
        "fields": [
            {"name": "id", "type": "long"},
            {"name": "name", "type": "string"},
            {"name": "email", "type": "string"},
            {"name": "age", "type": "int"},
            {"name": "salary", "type": "double"},
            {"name": "active", "type": "boolean"},
            {"name": "tags", "type": {"type": "array", "items": "string"}},
            {"name": "metadata", "type": {"type": "map", "values": "string"}},
        ]
    }))
    complex_record = {
        "id": 12345,
        "name": "Bob Smith",
        "email": "bob.smith@example.com",
        "age": 45,
        "salary": 85000.50,
        "active": True,
        "tags": ["engineer", "senior", "julia"],
        "metadata": {"dept": "R&D", "level": "5", "location": "NYC"},
    }
    n_iters_complex = 50_000

    # Write
    def write_complex():
        buf = io.BytesIO()
        encoder = avro.io.BinaryEncoder(buf)
        writer = avro.io.DatumWriter(complex_schema)
        writer.write(complex_record, encoder)
        return buf.getvalue()

    t = bench(write_complex, n_iters_complex)
    rate_w = n_iters_complex / t
    print(f"  Write: {n_iters_complex} records in {t:.4f}s ({rate_w:.0f} records/s)")
    results["complex_write_rate"] = rate_w

    # Read
    encoded = write_complex()

    def read_complex():
        buf = io.BytesIO(encoded)
        decoder = avro.io.BinaryDecoder(buf)
        reader = avro.io.DatumReader(complex_schema)
        return reader.read(decoder)

    t = bench(read_complex, n_iters_complex)
    rate_r = n_iters_complex / t
    print(f"  Read:  {n_iters_complex} records in {t:.4f}s ({rate_r:.0f} records/s)")
    results["complex_read_rate"] = rate_r

    # =========================================================================
    # Benchmark 3: Table / Object Container File (batch write/read)
    # =========================================================================
    print("\n--- Benchmark 3: Table Write/Read (Object Container File) ---")

    table_schema = avro.schema.parse(json.dumps({
        "type": "record",
        "name": "TableRow",
        "fields": [
            {"name": "id", "type": "int"},
            {"name": "name", "type": "string"},
            {"name": "value", "type": "double"},
            {"name": "active", "type": "boolean"},
        ]
    }))

    for n_rows in [1_000, 10_000, 100_000]:
        rows = [
            {"id": i, "name": f"user_{i}", "value": float(i) * 1.1, "active": i % 2 == 0}
            for i in range(1, n_rows + 1)
        ]

        tmpfile = tempfile.mktemp(suffix=".avro")

        # Write table
        def write_table():
            with open(tmpfile, "wb") as f:
                writer = avro.datafile.DataFileWriter(f, avro.io.DatumWriter(), table_schema)
                for row in rows:
                    writer.append(row)
                writer.close()

        t_write = bench(write_table, 5)
        avg_write = t_write / 5
        write_rate = n_rows / avg_write
        print(f"  Table Write ({n_rows} rows): {avg_write * 1000:.2f}ms ({write_rate:.0f} rows/s)")
        results[f"table_write_{n_rows}"] = write_rate

        # Write once for read benchmark
        write_table()

        # Read table
        def read_table():
            count = 0
            with open(tmpfile, "rb") as f:
                reader = avro.datafile.DataFileReader(f, avro.io.DatumReader())
                for _ in reader:
                    count += 1
                reader.close()
            return count

        t_read = bench(read_table, 5)
        avg_read = t_read / 5
        read_rate = n_rows / avg_read
        print(f"  Table Read  ({n_rows} rows): {avg_read * 1000:.2f}ms ({read_rate:.0f} rows/s)")
        results[f"table_read_{n_rows}"] = read_rate

        try:
            os.unlink(tmpfile)
        except OSError:
            pass

    # =========================================================================
    # Benchmark 4: Table with compression
    # =========================================================================
    print("\n--- Benchmark 4: Table Write with Compression (10,000 rows) ---")
    n_rows = 10_000
    rows = [
        {"id": i, "name": f"user_{i}", "value": float(i) * 1.1, "active": i % 2 == 0}
        for i in range(1, n_rows + 1)
    ]

    for codec in ["null", "deflate"]:
        tmpfile = tempfile.mktemp(suffix=".avro")

        def write_compressed(c=codec):
            with open(tmpfile, "wb") as f:
                writer = avro.datafile.DataFileWriter(f, avro.io.DatumWriter(), table_schema, codec=c)
                for row in rows:
                    writer.append(row)
                writer.close()

        t = bench(write_compressed, 5)
        avg = t / 5
        write_compressed()
        fsize = os.path.getsize(tmpfile)
        print(f"  Codec={codec}: {avg * 1000:.2f}ms, file={fsize / 1024:.1f}KB")

        try:
            os.unlink(tmpfile)
        except OSError:
            pass

    # =========================================================================
    # Benchmark 5: Raw binary encoding sizes
    # =========================================================================
    print("\n--- Benchmark 5: Serialization Sizes ---")

    int_schema = avro.schema.parse('"int"')
    long_schema = avro.schema.parse('"long"')
    double_schema = avro.schema.parse('"double"')
    string_schema = avro.schema.parse('"string"')

    def encode_datum(schema, datum):
        buf = io.BytesIO()
        encoder = avro.io.BinaryEncoder(buf)
        writer = avro.io.DatumWriter(schema)
        writer.write(datum, encoder)
        return buf.getvalue()

    for label, schema, val in [
        ("Int32(42)", int_schema, 42),
        ("Int64(1000000)", long_schema, 1000000),
        ("Float64(3.14)", double_schema, 3.14),
        ("String(100 chars)", string_schema, "x" * 100),
        ("Simple Record", simple_schema, simple_record),
        ("Complex Record", complex_schema, complex_record),
    ]:
        buf = encode_datum(schema, val)
        print(f"  {label} => {len(buf)} bytes")

    print("\n" + "=" * 70)
    print("Benchmark complete.")
    print("=" * 70)

    return results


if __name__ == "__main__":
    main()
