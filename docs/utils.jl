function hashes(hash_path=nothing, example=nothing)
    rootdir = joinpath(@__DIR__, "..") |> abspath
    julia = first(Base.julia_cmd())
    prog = quote
        using SHA
        hashes = IOBuffer()

        function f(_, path)
            hash = open(sha1, path) |> bytes2hex
            fname = relpath(path, $rootdir)
            println("$hash $fname")
        end
        push!(Base.include_callbacks, f)

        include($(joinpath(rootdir, "src", "DataFlowTasks.jl")))
        f(Main, $example)
    end
    cmd = `$julia --project=$rootdir -e $prog`

    buf = IOBuffer()
    run(pipeline(cmd, buf))
    hash_new = take!(buf) |> String

    hash_old = try
        read(hash_path, String)
    catch e
        display(e)
        @show pwd()
        @warn "Could not read hash file: `$hash_path`"
        "<unknown>"
    end

    return (hash_new, hash_old)
end
