module DataFlowScheduler

const PROJECT_ROOT =  pkgdir(DataFlowScheduler)

using MacroTools
using ThreadPools

import GraphRecipes: graphplot

"""
    @enum DependencyType

Determines how two codelets depend on each other in a [`TaskGraph`](@ref). If we
assume that `cdlt1` comes before `cdlt2` in a sequential execution, the possibilities are:
- `InferredIndependent` : data flow analysis detected independency
- `Independent` : user specified independency
- `Sequential`  : sequential dependency; that is `cldt1` must finish before
  `cldt2` starts
- `InferredMutex`  : data analysis determined that the two `codelets` can be
    executed in any order, but not simultaneously
- `Mutex` : like `InferredMutex`, but specificied manually by the user
"""
@enum DependencyType begin
    InferredIndependent = -2
    Independent = -1
    InferredSequential = 1
    Sequential = 2
    InferredMutex = 3
    Mutex = 4
end

isindependent(dep::DependencyType) = Int(dep) < 0

"""
    @enum AccessMode READ WRITE READWRITE NOCHECK

How a codelet access the data in its arguments.

!!! note
    Use `NOCHECK` if you want to bypass the data-flow checks used by the
    scheduler to determine the dependency between codelets.
"""
@enum AccessMode begin
    READ
    WRITE
    READWRITE
    NOCHECK
end

const R  = READ
const W  = WRITE
const RW = READWRITE
const X  = NOCHECK

"""
    @enum CodeletStatus

The status of the codelet. Options are:
- `NOSCHEDULER` : the codelet has not been added to a scheduler
- `PROCESING` : the codelet has been added to a scheduler but its dependencies
  have not been analyzed
- `WAITING` : the codelet is waiting of other codelets to finish
- `READY` : it is safe to execute the codelet
- `RUNNING` : the codelet is being executed
- `FINISHED` : execution has finished and all dependencies updated
"""
@enum CodeletStatus begin
    NOSCHEDULER
    PROCESSING
    WAITING
    READY
    RUNNING
    FINISHED
end

const CODELET_DICT = Dict(
    (:+, 2)        => (R, R),
    (:rmul!, 2)    => (RW, X),
    (:axpy!, 3)    => (X, R, RW),
    (:mul!, 3)     => (W, R, R),
    (:mul!, 5)     => (RW, R, R, X, X),
    (:ldiv!, 2)    => (R, RW),
    (:rdiv!, 2)    => (RW, R),
    (:lu!,2)       => (RW,X),
    (:identity, 1) => (R,)
)

"""
    debug(flag=true)

Activate debugging messages by setting the environment variable `JULIA_DEBUG` to
`DataFlowScheduler`. If `flag=false` deactive debugging messages.
"""
function debug(flag::Bool=true)
    if flag
        ENV["JULIA_DEBUG"] = "DataFlowScheduler"
    else
        ENV["JULIA_DEBUG"] = ""
    end
end

include("utils.jl")
include("codelet.jl")
include("arrayinterface.jl")
include("dag.jl")
include("taskgraph.jl")
# include("scheduler.jl")

const TASKGRAPH = TaskGraph()

export  Codelet,
        TaskGraph,
        execute,
        @codelet,
        @schedule

end # module
