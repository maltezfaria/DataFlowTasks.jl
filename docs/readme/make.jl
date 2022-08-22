cd(@__DIR__)
import Pkg; Pkg.activate("..")

using Literate
Literate.markdown("README.jl", pwd(),
                  flavor=Literate.CommonMarkFlavor())

@info "Running code in `README.jl`"
include("README.jl")

Literate.notebook("README.jl", pwd())

# Fix image paths for use in the root directory
contents = read("README.md", String)
contents = replace(contents, "![](" => "![](docs/readme/")
write("README.fixed.md", contents)



action = get(ARGS, 1, "preview")
if action == "preview"
    path = abspath("README.md")
    println("Preview available in $path")
elseif action == "check"
    println("Checking consistency with existing README")
    try
        run(`diff -q README.fixed.md ../../README.md`)
    catch
        @error "README.md out-of-date" msg="Please update it using `julia -t4 docs/readme/make.jl update`"
        exit(1)
    end
elseif action == "update"
    println("Updating README")
    if Threads.nthreads() != 4
        @error "Please use 4 threads when updating the README"
        exit(1)
    end
    cp("README.fixed.md", "../../README.md", force=true)
else
    @warn "Unknown action" action
end
