cd(@__DIR__)
include(joinpath(@__DIR__, "..", "..", "utils.jl"))

option = get(ARGS, 1, "")
option ∉ ("", "--check-only") && @warn "Unknown option: `$option`"

for example in ["cholesky", "blur-roberts"]
    hash_path = joinpath(example, "hashes.txt")
    hash_new, hash_old = hashes(hash_path, example)

    if hash_new == hash_old
        @info "Example up-to-date: `$example`"
        continue
    end

    if option == "--check-only"
        @error "Example out of date: `$example`"
        exit(1)
    end

    @info "Updating example: $example"
    julia = Base.julia_cmd() |> first
    run(`$julia -t4 $example/$example.jl`)

    @info "Saving new hashes for example: `$example`"
    write(hash_path, hash_new)
end
