"""
    struct TaskLog

Logs the execution trace of a [`DataFlowTask`](@ref).

## Fields:
- `tag`         : task id in DAG
- `time_start`  : time the task started running
- `time_finish` : time the task finished running
- `tid`         : thread on which the task ran
- `inneighbors` : vector of incoming neighbors in DAG
- `label`       : a string used for displaying and/or postprocessing tasks
"""
struct TaskLog
    tag::Int64
    time_start::UInt64
    time_finish::UInt64
    tid::Int
    inneighbors::Vector{Int64}
    label::String
end

tag(t::TaskLog) = t.tag
label(t::TaskLog) = t.label
task_duration(t::TaskLog) = t.time_finish - t.time_start

"""
    struct InsertionLog

Logs the execution trace of a [`DataFlowTask`](@ref) insertion.

## Fields:
- `time_start`  : time the insertion began
- `time_finish` : time the insertion finished
- `taskid`      : the task it is inserting
- `tid`         : the thread on which the insertion is happening
"""
struct InsertionLog
    time_start::UInt64
    time_finish::UInt64
    gc_time::Int64
    taskid::Int
    tid::Int
end

"""
    struct LogInfo

Contains informations on the program's progress. For thread-safety, the
`LogInfo` structure uses one vector of [`TaskLog`](@ref) per thread.

You can visualize and postprocess a `LogInfo` using [`plot_dag`](@ref) and
[`plot_traces`](@ref).
"""
struct LogInfo
    tasklogs::Vector{Vector{TaskLog}}
    insertionlogs::Vector{Vector{InsertionLog}}
    function LogInfo()
        # internal constructor to guarantee that there is always one vector per
        # thread to do the logging
        new(
            [Vector{TaskLog}()      for _ ∈ 1:Threads.nthreads()],
            [Vector{InsertionLog}() for _ ∈ 1:Threads.nthreads()]
        )
    end
end

#TODO: show more relevant information
function Base.show(io::IO,l::LogInfo)
    nodes = topological_sort(l)
    n     = length(nodes)
    cp    = longest_path(l)
    ctasks = filter(t->tag(t) ∈ cp,nodes)
    ct    = sum(weight(t) for t in ctasks) # critical time
    println(io,"LogInfo with $n logged task",n==1 ? "" : "s")
    print(io,"\t critical time: $(round(ct,sigdigits=2)) seconds")
end

"""
    const LOGINFO::Ref{LogInfo}

Global `LogInfo` being used to record the events. Can be changed using
[`_setloginfo!`](@ref).
"""
const LOGINFO = Ref{Maybe{LogInfo}}()

"""
    _setloginfo!(l::LogInfo)

Set the active logger to `l`.
"""
function _setloginfo!(l::Maybe{LogInfo})
    LOGINFO[] = l
end

"""
    _getloginfo()

Return the active logger.
"""
function _getloginfo()
    LOGINFO[]
end

function haslogger()
    !isnothing(_getloginfo())
end

#= Utility function to get number of task nodes of the logger =#
function nbtasknodes(logger)
    sum(length(threadlog) for threadlog ∈ logger.tasklogs)
end

"""
    with_logging!(f,l::LogInfo)

Similar to [`with_logging`](@ref), but append events to `l`.
"""
function with_logging!(f,l::LogInfo)
    _log_mode() == true || error("you must run `enable_log()` to activate the logger before profiling")
    old_logger = _getloginfo()
    _setloginfo!(l)
    res = f()
    _setloginfo!(old_logger)
    return res,l
end

"""
    with_logging(f) --> f(),loginfo

Execute `f()` and log `DataFlowTask`s into the `loginfo` object.

## Examples:

```jldoctest; output = false
using DataFlowTasks

A,B = zeros(2), ones(2);

out,loginfo = DataFlowTasks.with_logging() do
    @dspawn fill!(@W(A),1)
    @dspawn fill!(@W(B),1)
    res = @dspawn sum(@R(A)) + sum(@R(B))
    fetch(res)
end

#

out

# output

4.0
```

See also: [`LogInfo`](@ref)
"""
function with_logging(f)
    l = LogInfo()
    with_logging!(f,l)
end

"""
    DataFlowTasks.@log expr --> LogInfo

Execute `expr` and return a [`LogInfo`](@ref) instance with the recorded
events.

!!! warning
    The returned `LogInfo` instance may be incomplete if `block` returns before all
    `DataFlowTasks` spawened inside of it are completed. Typically `expr`
    should `fetch` the outcome before returning to properly benchmark the code
    that it runs (and not merely the tasks that it spawns).

See also: [`with_logging`](@ref), [`with_logging!`](@ref)
"""
macro log(ex)
    quote
        f = () -> $(esc(ex))
        out,loginfo = with_logging(f)
        loginfo
    end
end

# These implement the required interface to consider a Logger as a graph and
# compute its longest path

Base.isless(t1::TaskLog,t2::TaskLog) = isless(t1.tag,t2.tag)

function topological_sort(l::LogInfo)
    tlogs = Iterators.flatten(l.tasklogs) |> collect
    sort!(tlogs)
end

intags(t::TaskLog) = t.inneighbors
weight(t::TaskLog) = task_duration(t) * 1e-9
