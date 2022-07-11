"""
    moduel DataFlowTask

Create `Task`s wich keep track of how data flows through it.
"""
module DataFlowTasks

const PROJECT_ROOT =  pkgdir(DataFlowTasks)

using Logging
using ThreadPools
using DataStructures
using RecipesBase
using Requires

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
    # GLMakie conditionnal loading
    @require GLMakie="e9467ef8-e4e7-5192-8a1a-b1aee30e663a" begin 
        @require GraphViz="f526b714-d49f-11e8-06ff-31ed36ee7ee0" include("plot.jl")
    end

    # default scheduler
    capacity  = 50
    sch       = JuliaScheduler(capacity)
    setscheduler!(sch)

    # default logger
    logger    = Logger()
    setlogger!(logger)
end

end # module
