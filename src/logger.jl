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

You can visualize and postprocess a `LogInfo` using `GraphViz.Graph` and
`Makie.plot`.
"""
struct LogInfo
    tasklogs::Vector{Vector{TaskLog}}
    insertionlogs::Vector{Vector{InsertionLog}}
    function LogInfo()
        # internal constructor to guarantee that there is always one vector per
        # thread to do the logging
        return new(
            [Vector{TaskLog}() for _ in 1:Threads.nthreads()],
            [Vector{InsertionLog}() for _ in 1:Threads.nthreads()],
        )
    end
end

#TODO: show more relevant information
function Base.show(io::IO, l::LogInfo)
    n = nbtasknodes(l)
    return println(io, "LogInfo with $n logged task", n == 1 ? "" : "s")
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
    return LOGINFO[] = l
end

"""
    _getloginfo()

Return the active logger.
"""
function _getloginfo()
    return LOGINFO[]
end

function haslogger()
    return !isnothing(_getloginfo())
end

#= Utility function to get number of task nodes of the logger =#
function nbtasknodes(logger)
    return sum(length(threadlog) for threadlog in logger.tasklogs)
end

"""
    with_logging!(f,l::LogInfo)

Similar to [`with_logging`](@ref), but append events to `l`.
"""
function with_logging!(f, l::LogInfo)
    # taskgraph must be empty before starting, or we may log dependencies on
    # tasks that are not in the logger
    tg = get_active_taskgraph()
    if !isempty(tg)
        msg = """logging requires an empty taskgraph to start. Waiting for
        pending tasks to be completed...
        """
        @warn msg
        wait(tg)
        @warn "done."
    end
    # check if logger is already active, switch to new logger, record, and
    # switch back
    _log_mode() == true ||
        error("you must run `enable_log()` to activate the logger before profiling")
    old_logger = _getloginfo()
    _setloginfo!(l)
    res = f()
    _setloginfo!(old_logger)
    return res, l
end

"""
    with_logging(f) --> f(),loginfo

Execute `f()` and log `DataFlowTask`s into the `loginfo` object.

## Examples:

```jldoctest; output = false
using DataFlowTasks: @spawn

A,B = zeros(2), ones(2);

out,loginfo = DataFlowTasks.with_logging() do
    @spawn fill!(@W(A),1)
    @spawn fill!(@W(B),1)
    res = @spawn sum(@R(A)) + sum(@R(B))
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
    return with_logging!(f, l)
end

"""
    DataFlowTasks.@log expr --> LogInfo

Execute `expr` and return a [`LogInfo`](@ref) instance with the recorded events.
The `Logger` waits for the current taskgraph (see [`get_active_taskgraph`](@ref)
to be empty before starting.

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
        out, loginfo = with_logging(f)
        loginfo
    end
end

# These implement the required interface to consider a Logger as a graph and
# compute its longest path

Base.isless(t1::TaskLog, t2::TaskLog) = isless(t1.tag, t2.tag)

function topological_sort(l::LogInfo)
    tlogs = Iterators.flatten(l.tasklogs) |> collect
    return sort!(tlogs)
end

intags(t::TaskLog) = t.inneighbors
weight(t::TaskLog) = task_duration(t) * 1e-9

#= Contains data to plot the Gantt Chart (parallel trace).
It's a Struct of Array paradigm where all the entries i
of all the arrays tells us information about a same task. =#
"""
    struct Gantt

Structured used ton produce a [`Gantt
chart`](https://en.wikipedia.org/wiki/Gantt_chart) of the parallel traces of the
tasks recorded in a [`LogInfo`](@ref) instance. This structure is used when
plotting the parallel trace with `Makie.plot`.

See [`extractloggerinfo`](@ref) for more information on how to create an `Gantt`
instance.
"""
struct Gantt
    threads::Vector{Int64}      # Thread on wich the task ran
    jobids::Vector{Int64}       # Task type
    starts::Vector{Float64}     # Start time
    stops::Vector{Float64}      # End time

    function Gantt()
        threads = Vector{Int64}()
        jobids = Vector{Int64}()
        starts = Vector{Float64}()
        stops = Vector{Float64}()
        return new(threads, jobids, starts, stops)
    end
end

#= Contains additional post-processed informations on the LogInfo =#
"""
    struct ExtendedLogInfo

Appends informations to [`LogInfo`](@ref) to make it easier to visualize and
exctract useful information.

See [`extractloggerinfo`](@ref) for more information on how to create an
`ExtendedLogInfo` instance.
"""
mutable struct ExtendedLogInfo
    firsttime::Float64              # First measured time
    lasttime::Float64               # Last measured time
    computingtime::Float64          # Cumulative time spent computing
    insertingtime::Float64          # Cumulative time spent inserting
    othertime::Float64              # Cumulative other time
    t∞::Float64                     # Inf. proc time
    t_nowait::Float64               # Time if we didn't wait at all
    timespercat::Vector{Float64}    # timespercat[i] cumulative time for category i
    categories::Vector{Pair{String,Regex}} # (label => regex) pairs for categories
    path::Vector{Int64}             # Critical Path

    function ExtendedLogInfo(logger::LogInfo, categories, path)
        (firsttime, lasttime) = timelimits(logger) .* 10^(-9)
        othertime = (lasttime - firsttime) * length(logger.tasklogs)

        normalize_category(x) = x
        normalize_category(x::String) = (x => Regex(x))

        return new(
            firsttime,
            lasttime,
            0,
            0,
            othertime,
            0,
            0,
            zeros(length(categories) + 1),
            normalize_category.(categories),
            path,
        )
    end
end

function Base.show(io::IO, ::MIME"text/plain", extloginfo::ExtendedLogInfo)
    println(io, "ExtendedLogInfo")
    get(io, :compact, false) && return

    # format the output below using printf style. Right align so that all
    # numbers are aligned
    elapsed = extloginfo.lasttime - extloginfo.firsttime
    @printf(io, "• Elapsed time %-10s: %.3f\n", "", elapsed)
    @printf(io, "  ├─ %-20s: %.3f\n", "Critical path", extloginfo.t∞)
    @printf(io, "  ╰─ %-20s: %.3f\n", "No-wait", extloginfo.t_nowait)
    @printf(io, "\n")

    runtime = extloginfo.computingtime + extloginfo.insertingtime + extloginfo.othertime
    @printf(io, "• Run time %-14s: %.3f\n", "", runtime)
    @printf(io, "  ├─ %-20s:   %.3f\n", "Computing", extloginfo.computingtime)
    for i in eachindex(extloginfo.categories)
        (title, _) = extloginfo.categories[i]
        @printf(io, "  │  ├─ %-17s:     %.3f\n", title, extloginfo.timespercat[i])
    end
    @printf(io, "  │  ╰─ %-17s:     %.3f\n", "unlabeled", extloginfo.timespercat[end])
    @printf(io, "  ├─ %-20s:   %.3f\n", "Task insertion", extloginfo.insertingtime)
    @printf(io, "  ╰─ %-20s:   %.3f", "Other (waiting)", extloginfo.othertime)
end

#= Gives minimum and maximum times the logger has measured. =#
function timelimits(logger::LogInfo)
    iter = Iterators.flatten(logger.tasklogs)
    return minimum(t -> t.time_start, iter), maximum(t -> t.time_finish, iter)
end

#= Considering a `label` and a the full list of labels `categories`,
gives the index of the occurence of label in `categories`. Uses
`length(categories) + 1` when `label` is not presentin `categories`=#
function jobid(label::String, categories)
    for i in eachindex(categories)
        (title, rx) = categories[i]
        occursin(rx, label) && return i  # find first
    end
    return length(categories) + 1
end

"""
    extractloggerinfo(loginfo::LogInfo; categories = String[]) -->
    ExtendedLogInfo, Gantt

Analyses the information contained in `loginfo` and returns an
[`ExtendedLogInfo`](@ref) instance and a [`Gantt`](@ref) instance. Passing a
`categories` argument allows to group tasks by category. The `categories` can be
a vector of `String`s or a vector of `String => Regex` pairs, which will be
matched against the tasks' labels.
"""
function extractloggerinfo(loginfo::LogInfo; categories = String[])
    extloginfo = ExtendedLogInfo(loginfo, categories, longest_path(loginfo))
    gantt = Gantt()
    extractloggerinfo!(loginfo, extloginfo, gantt)
    return extloginfo, gantt
end

#= Initialize gantt and loginfo structures from logger. =#
function extractloggerinfo!(logger::LogInfo, loginfo::ExtendedLogInfo, gantt::Gantt)
    # Gantt data : Initialization TASKLOGS
    # ------------------------------------
    for tasklog in Iterators.flatten(logger.tasklogs)
        # Gantt data
        # ----------
        push!(gantt.threads, tasklog.tid)
        push!(gantt.jobids, jobid(tasklog.label, loginfo.categories))
        push!(gantt.starts, tasklog.time_start * 10^(-9) - loginfo.firsttime)
        push!(gantt.stops, tasklog.time_finish * 10^(-9) - loginfo.firsttime)

        # General Informations
        # --------------------
        task_duration = (tasklog.time_finish - tasklog.time_start) * 10^(-9)
        # ----
        loginfo.othertime     -= task_duration
        loginfo.computingtime += task_duration
        # ----
        loginfo.timespercat[jobid(tasklog.label, loginfo.categories)] += task_duration
        # ----
        tasklog.tag ∈ loginfo.path && (loginfo.t∞ += task_duration)
        loginfo.t_nowait += task_duration
    end

    # Gantt data : Initialization INSERTIONLOGS
    # -----------------------------------------
    for insertionlog in Iterators.flatten(logger.insertionlogs)
        if insertionlog.gc_time != 0
            gc_start = insertionlog.time_start * 10^(-9) - loginfo.firsttime
            gc_finish = gc_start + insertionlog.gc_time * 10^(-9)
            insertion_start = gc_finish
            insertion_finish = insertionlog.time_finish * 10^(-9) - loginfo.firsttime

            # GC Task
            push!(gantt.threads, insertionlog.tid)
            push!(gantt.jobids, length(loginfo.categories) + 3)
            push!(gantt.starts, gc_start)
            push!(gantt.stops, gc_finish)
        else
            insertion_start = insertionlog.time_start * 10^(-9) - loginfo.firsttime
            insertion_finish = insertionlog.time_finish * 10^(-9) - loginfo.firsttime
        end

        # Gantt data
        # ----------
        push!(gantt.threads, insertionlog.tid)
        push!(gantt.jobids, length(loginfo.categories) + 2)
        push!(gantt.starts, insertion_start)
        push!(gantt.stops, insertion_finish)

        # General Informations
        # --------------------
        task_duration         = (insertionlog.time_finish - insertionlog.time_start) * 10^(-9)
        loginfo.othertime     -= task_duration
        loginfo.insertingtime += task_duration
    end

    loginfo.t_nowait /= length(logger.tasklogs)

    return gantt
end
