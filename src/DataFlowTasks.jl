"""
    module DataFlowTask

Create `Task`s which can keep track of how data flows through it.
"""
module DataFlowTasks

const PROJECT_ROOT =  pkgdir(DataFlowTasks)

using DataStructures
using Compat
import Pkg

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

"""
    DataFlowTasks.@using_opt pkgnames

Load `pkgnames` from optional dependencies.

## Examples:
```example
using DataFlowTasks
DataFlowTasks.@using_opt GraphViz
```
"""
macro using_opt(pkgnames)
    if pkgnames isa Symbol
        pkgnames = [pkgnames]
    else
        @assert pkgnames.head == :tuple
        pkgnames = pkgnames.args
    end

    using_expr = Expr(:using)
    using_expr.args = [Expr(:., pkg) for pkg in pkgnames]

    dft_path = joinpath(@__DIR__, "..", "ext")
    quote
        const cpp = $Pkg.project().path
        $Pkg.activate($dft_path, io=devnull)
        try
            $Pkg.resolve(io=devnull)
            $using_expr
        finally
            $Pkg.activate(cpp, io=devnull)
        end
    end
end

function savedag end

end # module
