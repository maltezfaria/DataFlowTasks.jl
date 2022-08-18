"""
    moduel DataFlowTask

Create `Task`s wich keep track of how data flows through it.
"""
module DataFlowTasks

const PROJECT_ROOT =  pkgdir(DataFlowTasks)

using ThreadPools
using DataStructures
using Requires
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
include("otherschedulers.jl")

export
    @dtask,
    @dasync,
    @dspawn

function __init__()
    # Makie conditionnal loading
    @require Makie="ee78f7c6-11fb-53f2-987a-cfe4a2b5a57a" include("plotgeneral.jl")
    @require GraphViz="f526b714-d49f-11e8-06ff-31ed36ee7ee0" include("plotdag.jl")

    # default scheduler
    capacity  = 50
    sch       = JuliaScheduler(capacity)
    setscheduler!(sch)

    # default logger
    logger    = Logger()
    setlogger!(logger)
end

macro using_opt(pkgnames)
    if pkgnames isa Symbol
        pkgnames = [pkgnames]
    else
        @assert pkgnames.head == :tuple
        pkgnames = pkgnames.args
    end

    using_expr = Expr(:using)
    using_expr.args = [Expr(:., pkg) for pkg in pkgnames]

    dft_path = joinpath(@__DIR__, "..", "optional-deps")
    quote
        const cpp = $Pkg.project().path
        $Pkg.activate($dft_path, io=devnull)
        try
            $Pkg.instantiate()
            $using_expr
        finally
            $Pkg.activate(cpp, io=devnull)
        end
    end
end

end # module
