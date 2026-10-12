"""
    struct TaskLog

Logs the execution trace of a [`DataFlowTask`](@ref).

## Fields:
- `tag`          : task id in DAG
- `time_start`   : time the task body started running (after waiting for its dependencies)
- `time_finish`  : time the task body finished running
- `running_time` : time the task body spent actually running on a thread, i.e.
  excluding the time it was descheduled (sleeping, waiting on I/O or locks...)
- `tid`          : thread on which the task body started
- `tid_finish`   : thread on which the task body finished (a task may migrate
  between threads when it is descheduled)
- `inneighbors`  : vector of incoming neighbors in DAG
- `label`        : a string used for displaying and/or postprocessing tasks
- `failed`       : whether the task threw an error

All times are in nanoseconds.
"""
struct TaskLog
    tag::Int64
    time_start::UInt64
    time_finish::UInt64
    running_time::UInt64
    tid::Int
    tid_finish::Int
    inneighbors::Vector{Int64}
    label::String
    failed::Bool
end

tag(t::TaskLog) = t.tag
label(t::TaskLog) = t.label
task_duration(t::TaskLog) = t.time_finish - t.time_start

"""
    struct InsertionLog

Logs the execution trace of a [`DataFlowTask`](@ref) insertion.

## Fields:
- `time_request` : time the insertion was requested, before waiting for the
  DAG to be available (i.e. not locked, and not at full capacity)
- `time_start`   : time the insertion began, i.e. the data-flow analysis
- `time_finish`  : time the insertion finished
- `gc_time`      : time spent in garbage collection during the insertion
- `taskid`       : the task it is inserting
- `tid`          : the thread on which the insertion is happening

All times are in nanoseconds.
"""
struct InsertionLog
    time_request::UInt64
    time_start::UInt64
    time_finish::UInt64
    gc_time::Int64
    taskid::Int
    tid::Int
end

"""
    struct CleanupLog

Logs the removal of a finished [`DataFlowTask`](@ref) from its DAG by the
`dag_cleaner`.

## Fields:
- `tag`         : task id in DAG
- `time_start`  : time the removal began (the task waits to be removed since it
  finished, see [`TaskLog`](@ref))
- `time_finish` : time the removal finished

All times are in nanoseconds.
"""
struct CleanupLog
    tag::Int64
    time_start::UInt64
    time_finish::UInt64
end

tag(c::CleanupLog) = c.tag

#=
Data accesses of a `DataFlowTask`, recorded at its insertion while logging, from
which the complete dependency graph of the logged tasks is computed (see
`dependencies`). `graph` identifies the DAG the task was inserted in.
=#
struct LoggedAccess
    tag::Int64
    graph::UInt
    data::Tuple
    access_mode::Tuple
    linear::Bool
end

tag(a::LoggedAccess) = a.tag
Base.isless(a::LoggedAccess, b::LoggedAccess) = isless(a.tag, b.tag)
function data_dependency(a::LoggedAccess, b::LoggedAccess)
    return _data_dependency(a.data, a.access_mode, b.data, b.access_mode)
end

"""
    mutable struct LogInfo

Contains informations on the program's progress. Events are appended to the
logs under `lock`, so that a `LogInfo` can be safely shared by all threads.

Besides the logs of the tasks, of their insertion and of their removal from the
DAG, a `LogInfo` records the
logging window (`time_start` and `time_finish`, in nanoseconds), the number of
threads available to run the tasks (`nworkers`), and the time spent in garbage
collection and compilation during the window (`gc_time` and `compile_time`, in
seconds).

Use [`DataFlowTasks.describe`](@ref) or [`DataFlowTasks.summarize`](@ref) to
analyze a `LogInfo`, and `GraphViz.Graph` or `Makie.plot` to visualize it.

!!! note
    The removals from the DAG are only recorded during the logging window: the
    last tasks to finish are usually removed after the window closes, and have no
    [`CleanupLog`](@ref).

!!! note
    A `LogInfo` keeps references to the data accessed by the logged tasks until
    their dependencies are first needed (e.g. by `describe`), so that the
    complete dependency graph of the tasks can be computed.
"""
mutable struct LogInfo
    const tasklogs::Vector{TaskLog}
    const insertionlogs::Vector{InsertionLog}
    const cleanuplogs::Vector{CleanupLog}
    const lock::ReentrantLock
    # tasks scheduled while logging, which the logging window waits for
    const tasks::Vector{Task}
    # data accesses of the tasks inserted while logging, released once the
    # dependencies are computed
    const accesses::Vector{LoggedAccess}
    # complete dependencies of the logged tasks (tag => tags of predecessors),
    # computed lazily
    dependencies::Dict{Int64, Vector{Int64}}
    # number of open logging windows: removals from the DAG, which happen
    # asynchronously, are only recorded while a window is open
    active::Int
    time_start::UInt64
    time_finish::UInt64
    nworkers::Int
    gc_time::Float64
    compile_time::Float64
end

function LogInfo()
    return LogInfo(
        TaskLog[],
        InsertionLog[],
        CleanupLog[],
        ReentrantLock(),
        Task[],
        LoggedAccess[],
        Dict{Int64, Vector{Int64}}(),
        0,
        0,
        0,
        0,
        0.0,
        0.0,
    )
end

#= Append `log` to the logs of `l` in a thread-safe manner =#
# tasks scheduled after the logging window are neither waited for nor logged
function record!(l::LogInfo, log::TaskLog)
    @lock l.lock l.active > 0 && push!(l.tasklogs, log)
    return l
end
function record!(l::LogInfo, log::InsertionLog)
    @lock l.lock push!(l.insertionlogs, log)
    return l
end
function record!(l::LogInfo, log::CleanupLog)
    @lock l.lock l.active > 0 && push!(l.cleanuplogs, log)
    return l
end
function record!(l::LogInfo, t::Task)
    @lock l.lock l.active > 0 && push!(l.tasks, t)
    return l
end
function record!(l::LogInfo, a::LoggedAccess)
    @lock l.lock push!(l.accesses, a)
    return l
end

#=
Complete dependencies of the logged tasks, as a `Dict` mapping the tag of each
task to the tags of its direct predecessors.

The edges recorded during the execution only connect each task to the tasks
still in the DAG when it was inserted: a task already finished and removed from
the DAG is missing. Here, the same data-flow analysis (`update_edges!`) is
replayed for all the logged tasks of each DAG, in insertion order, so that the
result is the DAG that an unbounded `TaskGraph` without cleaning would have
built.

The accesses are released once analysed. Dependencies between tasks logged
before and after a call to `dependencies` (e.g. in separate `with_logging!`
calls on the same `LogInfo`) are therefore not found.
=#
function dependencies(l::LogInfo)
    @lock l.lock begin
        isempty(l.accesses) && return l.dependencies
        accesses = sort(l.accesses; by = tag)
        for graph in unique(a.graph for a in accesses)
            dag = DAG{LoggedAccess}()
            for a in accesses
                a.graph == graph || continue
                push!(dag.inoutlist, a => (Set{LoggedAccess}(), Set{LoggedAccess}()))
                update_edges!(dag, a, a.linear)
                l.dependencies[tag(a)] = [tag(p) for p in inneighbors(dag, a)]
            end
        end
        empty!(l.accesses)
        return l.dependencies
    end
end

#= Wait for all the tasks recorded in `l`, including the ones recorded while
waiting. Errors of failed tasks are not rethrown: they are reported when the
tasks are fetched. =#
function wait_logged_tasks(l::LogInfo)
    i = 1
    while true
        t = @lock l.lock (i <= length(l.tasks) ? l.tasks[i] : nothing)
        isnothing(t) && return l
        try
            wait(t)
        catch e
            e isa TaskFailedException || rethrow()
        end
        i += 1
    end
    return
end

#=
Running time (in nanoseconds) of the current task so far, or `nothing` if task
metrics are not enabled for it (see `Base.Experimental.task_metrics`).

NOTE: this reads internal fields of `Task` (Julia ≥ 1.12), since the public
`Base.Experimental.task_running_time_ns` only accounts for completed running
periods.
=#
function running_time_ns(t::Task = current_task())
    t.metrics_enabled || return nothing
    running = @atomic :monotonic t.running_time_ns
    started = @atomic :monotonic t.last_started_running_at
    return running + (time_ns() - started)
end

#TODO: show more relevant information
function Base.show(io::IO, l::LogInfo)
    n = nbtasknodes(l)
    return println(io, "LogInfo with $n logged task", n == 1 ? "" : "s")
end

# The `LogInfo` of the innermost enclosing logging block (if any). As a
# `ScopedValue`, it is seen by the code running inside the block and by the tasks
# created inside the block, so that only those are logged.
const LOGINFO = ScopedValue{Maybe{LogInfo}}(nothing)

#= Return the active logger (or `nothing`) =#
function _getloginfo()
    return LOGINFO[]
end

#= Utility function to get number of task nodes of the logger =#
function nbtasknodes(logger)
    return length(logger.tasklogs)
end

"""
    with_logging!(f,l::LogInfo)

Similar to [`with_logging`](@ref), but append events to `l`.
"""
function with_logging!(f, l::LogInfo)
    _log_mode() == true ||
        error("you must run `enable_log()` to activate the logger before profiling")
    # task metrics are enabled for the tasks created while they are on, which
    # gives the running time of the tasks (calls are counted, so this nests)
    Base.Experimental.task_metrics(true)
    l.nworkers = Threads.nthreads(:default)
    @lock l.lock begin
        l.active += 1
        l.time_start == 0 && (l.time_start = time_ns())
    end
    try
        stats = @timed with(LOGINFO => l) do
            res = f()
            # the logging window ends when all the logged tasks are done
            wait_logged_tasks(l)
            return res
        end
        l.gc_time += stats.gctime
        l.compile_time += stats.compile_time
        return stats.value, l
    finally
        @lock l.lock begin
            l.active -= 1
            l.time_finish = time_ns()
        end
        Base.Experimental.task_metrics(false)
    end
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
    return with_logging!(f, l)
end

"""
    DataFlowTasks.@log expr --> LogInfo

Execute `expr` and return a [`LogInfo`](@ref) instance with the recorded events.
The `DataFlowTask`s created by `expr` (directly, or by the tasks it creates) are
logged, and `@log` waits for them to be completed before returning. A task
created by `expr` but scheduled after `@log` returns (see [`@dtask`](@ref)) is
not logged.

Tasks which are not logged (e.g. spawned before `@log`, or by other code running
concurrently) may still run during the logging window: the time the workers
spend on them is reported as idle. For clean measurements, wait for such tasks
before logging, e.g. with `wait(get_active_taskgraph())`.

See also: [`with_logging`](@ref), [`with_logging!`](@ref)
"""
macro log(ex)
    return quote
        f = () -> $(esc(ex))
        out, loginfo = with_logging(f)
        loginfo
    end
end

# These implement the required interface to consider a Logger as a graph and
# compute its longest path

Base.isless(t1::TaskLog, t2::TaskLog) = isless(t1.tag, t2.tag)

#= A logged task, with its predecessors in the complete dependency graph =#
struct LoggedNode
    log::TaskLog
    intags::Vector{Int64}
end

tag(n::LoggedNode) = tag(n.log)
intags(n::LoggedNode) = n.intags
weight(n::LoggedNode) = weight(n.log)

function topological_sort(l::LogInfo)
    deps = dependencies(l)
    logged = Set(tag(t) for t in l.tasklogs)
    # the edges seen by the scheduler complete the replayed ones (e.g. for tasks
    # whose accesses were not recorded). Tags increase along the edges, and only
    # the predecessors which were logged (and ran) are part of the graph.
    return map(sort(l.tasklogs)) do t
        intags = union(t.inneighbors, get(deps, tag(t), Int64[]))
        return LoggedNode(t, filter!(∈(logged), intags))
    end
end
# The longest path is weighted by the wall time of the task bodies: along a
# chain of dependent tasks the bodies run one after the other, so that the length
# of the longest path is a lower bound of the elapsed time.
weight(t::TaskLog) = task_duration(t) * 1.0e-9

"""
    struct LogSummary

Summary of the events recorded in a [`LogInfo`](@ref), as computed by
[`DataFlowTasks.summarize`](@ref). All times are in seconds.

## Fields:
- `elapsed`       : wall-clock time of the logging window
- `workers`       : number of threads available to run the tasks (the threads
  of the `:default` threadpool)
- `running`       : total time the tasks spent running
- `blocked`       : total time the tasks spent descheduled during their body
  (sleeping, waiting on I/O or on a lock...)
- `insertion`     : total time spent inserting the tasks in the DAG (on the
  threads calling `@dspawn`)
- `longest_path_length` : length (in wall time) of the longest chain of
  dependent tasks
- `gc`, `compile` : time spent in garbage collection and in compilation during
  the logging window
- `categories`, `running_per_category` : the categories of tasks, and the
  running time of the tasks in each of them (the last entry gathers the tasks
  matching no category)
- `longest_path`  : tags of the tasks on the longest path
- `ntasks`, `nfailed`, `nmigrated` : number of tasks, of tasks which threw an
  error, and of tasks which finished on another thread than the one they
  started on

The following quantities are derived from these fields:
- `capacity(s) = s.workers * s.elapsed`: the time the workers were available;
- `idle(s) = capacity(s) - s.running`: the time the workers did not run any task;
- `nowait(s) = s.running / s.workers`: the elapsed time if the running time were
  perfectly shared between the workers, without ever waiting.

Both `longest_path_length` and `nowait` are lower bounds of `elapsed`.
"""
struct LogSummary
    elapsed::Float64
    workers::Int
    running::Float64
    blocked::Float64
    insertion::Float64
    longest_path_length::Float64
    gc::Float64
    compile::Float64
    categories::Vector{Pair{String, Regex}}
    running_per_category::Vector{Float64}
    longest_path::Vector{Int64}
    ntasks::Int
    nfailed::Int
    nmigrated::Int
end

capacity(s::LogSummary) = s.workers * s.elapsed
idle(s::LogSummary) = capacity(s) - s.running
nowait(s::LogSummary) = s.running / s.workers

_category(c::Pair{String, Regex}) = c
_category(c::String) = c => Regex(c)

#= Index of the first category of `categories` matching `label`, or
`length(categories) + 1` if there is none. =#
function jobid(label::String, categories)
    for i in eachindex(categories)
        (_, rx) = categories[i]
        occursin(rx, label) && return i
    end
    return length(categories) + 1
end

"""
    summarize(loginfo::LogInfo; categories = String[]) -> LogSummary

Compute a [`LogSummary`](@ref) of the events recorded in `loginfo`.

Passing a `categories` argument allows grouping tasks by category. The
`categories` can be a vector of `String`s or a vector of `String => Regex`
pairs, which will be matched against the tasks' labels.
"""
function summarize(loginfo::LogInfo; categories = String[])
    loginfo.time_finish > loginfo.time_start || throw(
        ArgumentError(
            "the logging window of `loginfo` is not set: record it with `DataFlowTasks.@log`",
        ),
    )
    ns = 1.0e-9
    cats = Pair{String, Regex}[_category(c) for c in categories]
    running_per_category = zeros(length(cats) + 1)
    blocked = 0.0
    nfailed = nmigrated = 0
    for t in loginfo.tasklogs
        running = t.running_time * ns
        running_per_category[jobid(t.label, cats)] += running
        # the running time is at most the wall time, up to the clock resolution
        blocked += max(0.0, task_duration(t) * ns - running)
        nfailed += t.failed
        nmigrated += t.tid != t.tid_finish
    end
    insertion = sum(l -> (l.time_finish - l.time_start) * ns, loginfo.insertionlogs; init = 0.0)
    path = isempty(loginfo.tasklogs) ? Int64[] : longest_path(loginfo)
    onpath = Set(path)
    longest_path_length = sum(weight, (t for t in loginfo.tasklogs if tag(t) ∈ onpath); init = 0.0)
    return LogSummary(
        (loginfo.time_finish - loginfo.time_start) * ns,
        loginfo.nworkers,
        sum(running_per_category),
        blocked,
        insertion,
        longest_path_length,
        loginfo.gc_time,
        loginfo.compile_time,
        cats,
        running_per_category,
        path,
        length(loginfo.tasklogs),
        nfailed,
        nmigrated,
    )
end

"""
    describe(loginfo::LogInfo; categories = String[])
    describe(io, loginfo::LogInfo; categories = String[])

Analyses the information contained in `loginfo` and displays a summary on `io`
(`stdout` by default). See [`LogSummary`](@ref) for the definitions of the
reported quantities.

Passing a `categories` argument allows grouping tasks by category. The
`categories` can be a vector of `String`s or a vector of `String => Regex`
pairs, which will be matched against the tasks' labels.
"""
function describe(loginfo::LogInfo; categories = String[])
    return describe(stdout, loginfo; categories = categories)
end

function describe(io::IO, loginfo::LogInfo; categories = String[])
    s = summarize(loginfo; categories)
    percent(x, total) = total > 0 ? 100 * x / total : 0.0
    function line(prefix, label, value)
        print(io, prefix, rpad(label, 32 - length(prefix)), ": ")
        return @printf(io, "%.3f", value)
    end

    line("• ", "Elapsed time", s.elapsed)
    println(io)
    line("  ├─ ", "Longest path", s.longest_path_length)
    println(io)
    line("  ╰─ ", "No-wait (running / workers)", nowait(s))
    println(io, "\n")

    line("• ", "Worker time ($(s.workers) × elapsed)", capacity(s))
    println(io)
    line("  ├─ ", "Running tasks", s.running)
    @printf(io, "  (%.1f%%)\n", percent(s.running, capacity(s)))
    for (i, (title, _)) in enumerate(s.categories)
        line("  │  ├─ ", title, s.running_per_category[i])
        println(io)
    end
    line("  │  ╰─ ", "uncategorized", s.running_per_category[end])
    println(io)
    line("  ╰─ ", "Idle", idle(s))
    @printf(io, "  (%.1f%%)\n\n", percent(idle(s), capacity(s)))

    line("• ", "Task insertion", s.insertion)
    @printf(io, "  (%.1f%% of elapsed)\n", percent(s.insertion, s.elapsed))
    line("• ", "Tasks blocked", s.blocked)
    println(io, "  (sleeping, waiting on I/O or locks...)")
    line("• ", "Garbage collection", s.gc)
    println(io)
    line("• ", "Compilation", s.compile)
    println(io)
    s.nfailed > 0 && println(io, "\n⚠ $(s.nfailed) of the $(s.ntasks) tasks failed")
    return nothing
end

"""
    loggertodot(logger)  --> dagstring

Return a string in the
[DOT](https://en.wikipedia.org/wiki/DOT_(graph_description_language)) format
representing the underlying graph in `logger`.

If `GraphViz` is installed, you can use `GraphViz.Graph(logger)` to produce an
image.
"""
function loggertodot(logger)
    path = longest_path(logger)

    # Write DOT graph
    # ---------------
    str = "strict digraph dag {rankdir=LR;layout=dot;rankdir=TB;"
    str *= """concentrate=true;"""

    for node in topological_sort(logger)
        tasklog = node.log
        # Tasklog.tag node attributes
        str *= """ $(tasklog.tag) """
        tasklog.label != "" && (str *= """ [label="$(tasklog.label)"] """)
        tasklog.tag ∈ path && (str *= """ [color=red] """)
        str *= """[penwidth=2];"""

        # Defines edges
        for neighbour in intags(node)
            red = false

            # Is this connection is in the longest path
            (neighbour ∈ path && tasklog.tag ∈ path) && (red = true)

            # Edge
            str *= """ $neighbour -> $(tasklog.tag) """
            red && (str *= """[color=red] """)
            str *= """[penwidth=2];"""
        end
    end

    return str *= "}"
end
