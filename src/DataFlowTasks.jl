"""
    module DataFlowTask

Create `Task`s which can keep track of how data flows through it.
"""
module DataFlowTasks

const PROJECT_ROOT = pkgdir(DataFlowTasks)

using OrderedCollections
using Printf

export @dspawn, @dasync

"""
    @enum AccessMode READ WRITE READWRITE

Describe how a `DataFlowTask` access its `data`.
"""
@enum AccessMode::UInt8 begin
    READ
    WRITE
    READWRITE
end

const R = READ
const W = WRITE
const RW = READWRITE

const Maybe{T} = Union{T, Nothing}

include("utils.jl")
include("logger.jl")
include("dataflowtask.jl")
include("dag.jl")
include("taskgraph.jl")
include("arrayinterface.jl")

function __init__()
    # default scheduler
    capacity = 50
    tg = TaskGraph(capacity)
    set_active_taskgraph!(tg)
    # no logger by default
    return _setloginfo!(nothing)
end

"""
    DataFlowTasks.savedag(filepath, graph)

Save `graph` as an SVG image at `filepath`. This requires `GraphViz` to be
available.
"""
function savedag end

end # module
