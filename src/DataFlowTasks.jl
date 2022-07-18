"""
    moduel DataFlowTask

Create `Task`s wich keep track of how data flows through it.
"""
module DataFlowTasks

const PROJECT_ROOT =  pkgdir(DataFlowTasks)

using ThreadPools
using DataStructures
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
    # Makie conditionnal loading
    @require Makie="ee78f7c6-11fb-53f2-987a-cfe4a2b5a57a" begin 
        @require GraphViz="f526b714-d49f-11e8-06ff-31ed36ee7ee0" begin
            @require Cairo="159f3aea-2a34-519c-b102-8c37f9878175" begin
                @require FileIO="5789e2e9-d7fb-5bc7-8068-2c6fae9b9549" include("plot.jl")
            end
        end
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
