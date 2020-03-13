module HScheduler

@enum AccessMode READ WRITE READWRITE

const R  = READ
const W  = WRITE
const RW = READWRITE

using LightGraphs

import LightGraphs: nv,ne,has_edge,add_edge!, transitivereduction
import GraphRecipes: graphplot

include("codelet.jl")
include("htask.jl")
include("taskgraph.jl")
include("dependencies.jl")
include("scheduler.jl")
include("test_utils.jl")

export GenericCodelet, Codelet, HTask, TaskGraph, Scheduler

end # module
