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
    struct Logger

Contains informations on the program's progress. For thread-safety, the `Logger`
structure uses one vector of [`TaskLog`](@ref) per thread.
"""
struct Logger
    tasklogs::Vector{Vector{TaskLog}}
    insertionlogs::Vector{Vector{InsertionLog}}
    function Logger()
        # internal constructor to guarantee that there is always one vector per
        # thread to do the logging
        new(
            [Vector{TaskLog}()      for _ ∈ 1:Threads.nthreads()],
            [Vector{InsertionLog}() for _ ∈ 1:Threads.nthreads()]
        )
    end
end

"""
    const LOGGER::Ref{Logger}

Global `Logger` being used to record the events. Can be changed using [`setlogger!`](@ref).
"""
const LOGGER = Ref{Maybe{Logger}}()

"""
    setlogger!(l::Logger)

Set the global (default) logger to `l`.
"""
function setlogger!(l::Maybe{Logger})
    LOGGER[] = l
end

"""
    getlogger()

Return the global logger.
"""
function getlogger()
    LOGGER[]
end

function haslogger()
    !isnothing(getlogger())
end

"""
    resetlogger(logger)

Clear the `logger`'s memory, logging states, and reset environnement for new
measures.
"""
function resetlogger!(logger)
    map(empty!, logger.tasklogs)
    map(empty!, logger.insertionlogs)
    # FIXME: this should not be called here, but for the moment some graph
    # algorithm assume the logged tasks start with taskid=1.
    # TASKCOUNTER[] = 0
end

#= Utility function to get number of task nodes of the logger =#
function nbtasknodes(logger)
    sum(length(threadlog) for threadlog ∈ logger.tasklogs)
end

"""
    DataFlowTasks.@log expr --> logger
    DataFlowTasks.@log logger expr --> logger

Execute `expr` and return a `logger::[`Logger`](@ref)` with the recorded events.

If called with a `Logger` as a first argument, append the events to the it
instead of creating a new one.
"""
macro log(logger,ex)
    quote
        _log_mode() == true || error("you must run `enable_log()` to activate the logger before profiling")
        old_logger = getlogger()
        setlogger!($logger)
        $(esc(ex))
        setlogger!(old_logger)
        $logger
    end
end

macro log(ex)
    quote
        logger = Logger()
        @log logger $(esc(ex))
    end
end

# These implement the required interface to consider a Logger as a graph and
# compute its longest path

Base.isless(t1::TaskLog,t2::TaskLog) = isless(t1.tag,t2.tag)

function topological_sort(l::Logger)
    tlogs = Iterators.flatten(l.tasklogs) |> collect
    sort!(tlogs)
end

inneighbors(t::TaskLog) = t.inneighbors
weight(t::TaskLog) = (t.time_finish - t.time_start) * 10^(-9)
