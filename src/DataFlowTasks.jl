"""
    moduel DataFlowTask

Create `Task`s wich keep track of how data flows through it.
"""
module DataFlowTasks

const PROJECT_ROOT =  pkgdir(DataFlowTasks)

using Logging
using ThreadPools
using DataStructures
using GraphViz: Graph
using RecipesBase

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

# a module showcasing some usecases. To be removed eventually...
include("TiledFactorization/TiledFactorization.jl")

function __init__()
    # default scheduler
    capacity  = 20
    sch       = JuliaScheduler(capacity)
    setscheduler!(sch)
end

end # module
