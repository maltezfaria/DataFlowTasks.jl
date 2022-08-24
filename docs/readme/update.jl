cd(@__DIR__)
include(joinpath(@__DIR__, "..", "utils.jl"))

option = get(ARGS, 1, "")
option ∉ ("", "--check-only") && @warn "Unknown option: `$option`"

hash_path = "hash.txt"
hash_new, hash_old = hashes(hash_path, "README.jl")

if hash_new == hash_old
    @info "README up-to-date"
    exit(0)
end

if option == "--check-only"
    @error "README.md out-of-date"
    exit(1)
end

import Pkg
Pkg.activate("..")

using Literate
Literate.markdown("README.jl", pwd(),
                  flavor=Literate.CommonMarkFlavor())

@info "Running code in `README.jl`"
julia = Base.julia_cmd() |> first
run(`$julia -t4 README.jl`)

Literate.notebook("README.jl", pwd())

# Fix image paths for use in the root directory
contents = read("README.md", String)
contents = replace(contents, "![](" => "![](docs/readme/")

write(joinpath("..", "..", "README.md"), contents)
write(hash_path, hash_new)
