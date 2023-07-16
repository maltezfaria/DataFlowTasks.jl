"""
    module DataFlowTask

Create `Task`s which can keep track of how data flows through it.
"""
module DataFlowTasks

const PROJECT_ROOT =  pkgdir(DataFlowTasks)

using DataStructures
using Compat
import Pkg
import TOML
import Scratch

"""
    @enum AccessMode READ WRITE READWRITE

Describe how a `DataFlowTask` access its `data`.
"""
@enum AccessMode::UInt8 begin
    READ
    WRITE
    READWRITE
end

const R  = READ
const W  = WRITE
const RW = READWRITE

const Maybe{T} = Union{T,Nothing}

include("utils.jl")
include("logger.jl")
include("dataflowtask.jl")
include("arrayinterface.jl")
include("dag.jl")
include("scheduler.jl")
# include("otherschedulers.jl")

export
    @dtask,
    @dasync,
    @dspawn

function __init__()
    # default scheduler
    capacity  = 50
    sch       = JuliaScheduler(capacity)
    setscheduler!(sch)

    # no logger by default
    _setloginfo!(nothing)
end


const WEAKDEPS_PROJ = let
    deps = TOML.parse(read(joinpath(@__DIR__, "..", "ext", "Project.toml"), String))["deps"]
    filter!(deps) do (pkg, _)
        pkg != String(nameof(@__MODULE__))
    end
    compat = Dict{String, Any}()
    for (pkg, bound) in TOML.parse(read(joinpath(@__DIR__, "..", "Project.toml"), String))["compat"]
        pkg ∈ keys(deps) || continue
        compat[pkg] = bound
    end
    Dict("deps" => deps, "compat" => compat)
end

"""
    DataFlowTasks.stack_weakdeps_env!(; verbose = false)

Push to the load stack an environment providing the weak dependencies of
DataFlowTasks. During the development stage, this allows benefiting from the
profiling / debugging features of DataFlowTasks without having to install
`GraphViz` or `Makie` in the project environment.

This can take quite some time if packages have to be installed or
precompiled. Run in `verbose` mode to see what happens.

!!! warning

    This feature is experimental and might break in the future.

## Examples:
```example
DataFlowTasks.stack_weakdeps_env!()
using GraphViz
```
"""
function stack_weakdeps_env!(; verbose = false)
    weakdeps_env = Scratch.@get_scratch!("weakdeps-$(VERSION.major).$(VERSION.minor)")
    open(joinpath(weakdeps_env, "Project.toml"), "w") do f
        TOML.print(f, WEAKDEPS_PROJ)
    end

    cpp = Pkg.project().path
    io = verbose ? stderr : devnull

    try
        Pkg.activate(weakdeps_env; io)
        Pkg.resolve(; io)
        Pkg.instantiate(; io)
        Pkg.status()
    finally
        Pkg.activate(cpp; io)
    end

    push!(LOAD_PATH, weakdeps_env)
    nothing
end


"""
    DataFlowTasks.savedag(filepath, graph)

Save `graph` as an SVG image at `filepath`. This requires `GraphViz` to be
available.
"""
function savedag end

end # module
