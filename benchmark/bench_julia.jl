using Avro
using Dates
using UUIDs

# Utility: time a function over N iterations, return total seconds
function bench(f, n; warmup=3)
    # Warmup
    for _ in 1:warmup
        f()
    end
    GC.gc()
    t0 = time_ns()
    for _ in 1:n
        f()
    end
    t1 = time_ns()
    return (t1 - t0) / 1e9
end

function main()
    println("=" ^ 70)
    println("Avro.jl Performance Benchmark")
    println("=" ^ 70)

    results = Dict{String, Any}()

    # =========================================================================
    # Benchmark 1: Simple record write/read (single record, many iterations)
    # =========================================================================
    println("\n--- Benchmark 1: Simple Record Serialization (single record) ---")
    simple_record = (name = "Alice Johnson", age = Int32(30), score = 95.5, active = true)
    n_iters = 100_000

    # Write
    t = bench(n_iters) do
        Avro.write(simple_record)
    end
    rate_w = n_iters / t
    println("  Write: $n_iters records in $(round(t, digits=4))s ($(round(Int, rate_w)) records/s)")
    results["simple_write_rate"] = rate_w

    # Read
    buf = Avro.write(simple_record)
    T = typeof(simple_record)
    t = bench(n_iters) do
        Avro.read(buf, T)
    end
    rate_r = n_iters / t
    println("  Read:  $n_iters records in $(round(t, digits=4))s ($(round(Int, rate_r)) records/s)")
    results["simple_read_rate"] = rate_r

    # =========================================================================
    # Benchmark 2: Complex record with nested types
    # =========================================================================
    println("\n--- Benchmark 2: Complex Record Serialization ---")
    complex_record = (
        id = Int64(12345),
        name = "Bob Smith",
        email = "bob.smith@example.com",
        age = Int32(45),
        salary = 85000.50,
        active = true,
        tags = ["engineer", "senior", "julia"],
        metadata = Dict{String, String}("dept" => "R&D", "level" => "5", "location" => "NYC"),
    )
    n_iters_complex = 50_000

    # Write
    t = bench(n_iters_complex) do
        Avro.write(complex_record)
    end
    rate_w = n_iters_complex / t
    println("  Write: $n_iters_complex records in $(round(t, digits=4))s ($(round(Int, rate_w)) records/s)")
    results["complex_write_rate"] = rate_w

    # Read
    buf = Avro.write(complex_record)
    T = typeof(complex_record)
    t = bench(n_iters_complex) do
        Avro.read(buf, T)
    end
    rate_r = n_iters_complex / t
    println("  Read:  $n_iters_complex records in $(round(t, digits=4))s ($(round(Int, rate_r)) records/s)")
    results["complex_read_rate"] = rate_r

    # =========================================================================
    # Benchmark 3: Table / Object Container File (batch write/read)
    # =========================================================================
    println("\n--- Benchmark 3: Table Write/Read (Object Container File) ---")
    for n_rows in [1_000, 10_000, 100_000]
        rows = [(
            id = Int32(i),
            name = "user_$i",
            value = Float64(i) * 1.1,
            active = i % 2 == 0,
        ) for i in 1:n_rows]

        tmpfile = tempname() * ".avro"

        # Write table
        t_write = bench(5) do
            Avro.writetable(tmpfile, rows)
        end
        avg_write = t_write / 5
        write_rate = n_rows / avg_write
        println("  Table Write ($n_rows rows): $(round(avg_write * 1000, digits=2))ms ($(round(Int, write_rate)) rows/s)")
        results["table_write_$(n_rows)"] = write_rate

        # Write once for read benchmark
        Avro.writetable(tmpfile, rows)

        # Read table
        t_read = bench(5) do
            tbl = Avro.readtable(tmpfile)
            # Force materialization by accessing data
            length(tbl)
        end
        avg_read = t_read / 5
        read_rate = n_rows / avg_read
        println("  Table Read  ($n_rows rows): $(round(avg_read * 1000, digits=2))ms ($(round(Int, read_rate)) rows/s)")
        results["table_read_$(n_rows)"] = read_rate

        rm(tmpfile, force=true)
    end

    # =========================================================================
    # Benchmark 4: Table with compression
    # =========================================================================
    println("\n--- Benchmark 4: Table Write with Compression (10,000 rows) ---")
    n_rows = 10_000
    rows = [(
        id = Int32(i),
        name = "user_$i",
        value = Float64(i) * 1.1,
        active = i % 2 == 0,
    ) for i in 1:n_rows]

    for codec in [:null, :deflate, :zstd]
        tmpfile = tempname() * ".avro"
        if codec == :null
            t = bench(5) do
                Avro.writetable(tmpfile, rows)
            end
        else
            t = bench(5) do
                Avro.writetable(tmpfile, rows; compress=codec)
            end
        end
        avg = t / 5
        # Get file size
        if codec == :null
            Avro.writetable(tmpfile, rows)
        else
            Avro.writetable(tmpfile, rows; compress=codec)
        end
        fsize = filesize(tmpfile)
        println("  Codec=$codec: $(round(avg * 1000, digits=2))ms, file=$(round(fsize / 1024, digits=1))KB")
        rm(tmpfile, force=true)
    end

    # =========================================================================
    # Benchmark 5: Raw binary encoding sizes
    # =========================================================================
    println("\n--- Benchmark 5: Serialization Sizes ---")
    for (label, val) in [
        ("Int32(42)", Int32(42)),
        ("Int64(1000000)", Int64(1000000)),
        ("Float64(3.14)", 3.14),
        ("String(100 chars)", "x" ^ 100),
        ("Simple Record", simple_record),
        ("Complex Record", complex_record),
    ]
        buf = Avro.write(val)
        println("  $label => $(length(buf)) bytes")
    end

    println("\n" * "=" ^ 70)
    println("Benchmark complete.")
    println("=" ^ 70)

    return results
end

main()
