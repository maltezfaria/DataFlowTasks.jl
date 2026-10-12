"""
    struct TaskTimeline

Lifecycle of a logged [`DataFlowTask`](@ref), as computed by
[`DataFlowTasks.timeline`](@ref). Times are in seconds since the start of the
logging window.

## Fields:
- `tag`             : task id in DAG
- `label`           : label of the task
- `requested`       : the insertion of the task in the DAG was requested
- `insertion_start` : the data-flow analysis began, once the DAG was available
- `inserted`        : the task was inserted in the DAG
- `ready`           : the task was inserted and all its predecessors finished
- `started`         : the task body started running
- `finished`        : the task body finished running
- `removed`         : the task was removed from the DAG, or `nothing` if it was
  not removed during the logging window
- `running`         : time the task body spent running on a thread (see
  [`TaskLog`](@ref))
- `predecessors`    : tags of the logged tasks the task depends on
- `ready_by`        : tag of the predecessor which finished last, if it made the
  task ready (i.e. after its insertion), and `0` otherwise
- `lane`            : lane of the task in a trace of the tasks, such that the
  tasks of a lane do not overlap in time. Lanes are not threads: a task may
  migrate between threads, and a thread runs other tasks while a task is
  descheduled.
- `migrated`        : whether the task finished on another thread than the one it
  started on
- `failed`          : whether the task threw an error

!!! note
    The time between `ready` and `started` includes the latency of Julia's
    scheduler, but also, for a task created with [`@dtask`](@ref), the time
    before it was scheduled.
"""
struct TaskTimeline
    tag::Int64
    label::String
    requested::Float64
    insertion_start::Float64
    inserted::Float64
    ready::Float64
    started::Float64
    finished::Float64
    removed::Union{Float64, Nothing}
    running::Float64
    predecessors::Vector{Int64}
    ready_by::Int64
    lane::Int
    migrated::Bool
    failed::Bool
end

tag(t::TaskTimeline) = t.tag

#= Seconds elapsed between the start of the logging window and `t` (in ns) =#
_seconds(l::LogInfo, t) = (Int64(t) - Int64(l.time_start)) * 1.0e-9

"""
    timeline(l::LogInfo) -> Vector{TaskTimeline}

Lifecycle of the tasks logged in `l`, sorted by tag. See [`TaskTimeline`](@ref).

The ready time of a task is derived from the logs: it is the latest of its
insertion and of the end of its predecessors (in the complete dependency graph
of the logged tasks).
"""
function timeline(l::LogInfo)
    nodes = topological_sort(l)
    insertions = Dict(i.taskid => i for i in l.insertionlogs)
    removals = Dict(tag(c) => c for c in l.cleanuplogs)
    finished = Dict(tag(n) => _seconds(l, n.log.time_finish) for n in nodes)
    lanes = _lanes(n.log for n in nodes)
    return map(nodes, lanes) do n, lane
        t = n.log
        started = _seconds(l, t.time_start)
        # without a record of the insertion (e.g. in a hand-built log), the task
        # is considered inserted when it started
        i = get(insertions, tag(t), nothing)
        requested, insertion_start, inserted = if isnothing(i)
            started, started, started
        else
            _seconds(l, i.time_request), _seconds(l, i.time_start), _seconds(l, i.time_finish)
        end
        ready, ready_by = inserted, 0
        for p in intags(n)
            if finished[p] >= ready
                ready, ready_by = finished[p], p
            end
        end
        c = get(removals, tag(t), nothing)
        removed = isnothing(c) ? nothing : _seconds(l, c.time_finish)
        return TaskTimeline(
            tag(t),
            t.label,
            requested,
            insertion_start,
            inserted,
            ready,
            started,
            _seconds(l, t.time_finish),
            removed,
            t.running_time * 1.0e-9,
            intags(n),
            ready_by,
            lane,
            t.tid != t.tid_finish,
            t.failed,
        )
    end
end

#=
Assign the tasks to lanes such that the tasks of a lane do not overlap in time,
using as few lanes as possible: the number of lanes is the largest number of
tasks running at the same time (see `concurrency`). A task occupies the interval
`[time_start, time_finish)`, so that a task may start in the lane of a task
finishing at the same time.
=#
function _lanes(tasklogs)
    logs = collect(tasklogs)
    lanes = zeros(Int, length(logs))
    # time at which the last task of each lane finishes
    free = UInt64[]
    for k in sortperm(logs; by = t -> (t.time_start, tag(t)))
        t = logs[k]
        lane = findfirst(<=(t.time_start), free)
        if isnothing(lane)
            push!(free, t.time_finish)
            lanes[k] = length(free)
        else
            free[lane] = t.time_finish
            lanes[k] = lane
        end
    end
    return lanes
end

"""
    concurrency(l::LogInfo) -> (; time, dag, ready, running)

Number of logged tasks over time, as step functions: on `[time[k], time[k+1])`,
- `dag[k]` tasks are in the DAG (inserted and not yet removed),
- `ready[k]` tasks are ready but not started (see [`TaskTimeline`](@ref)),
- `running[k]` tasks are running, i.e. started and not finished (a running task
  may be descheduled, and leave its thread to another task).

Times are in seconds since the start of the logging window, from `0` to the
duration of the window. Tasks which were not removed from the DAG during the
logging window are counted in the DAG until its end.

!!! note
    Only the logged tasks are counted: a task created before the logging window
    is not counted, even while it is in the DAG.
"""
function concurrency(l::LogInfo)
    elapsed = _seconds(l, l.time_finish)
    # events (time, change of dag, of ready and of running)
    events = Tuple{Float64, Int, Int, Int}[]
    for t in timeline(l)
        push!(events, (t.inserted, 1, 0, 0), (something(t.removed, elapsed), -1, 0, 0))
        push!(events, (t.ready, 0, 1, 0), (t.started, 0, -1, 0))
        push!(events, (t.started, 0, 0, 1), (t.finished, 0, 0, -1))
    end
    # the events happening at the same time are merged in a single step
    sort!(events; by = first)
    time, dag, ready, running = [0.0], [0], [0], [0]
    for (t, Δdag, Δready, Δrunning) in events
        if t != time[end]
            push!(time, t)
            push!(dag, dag[end]), push!(ready, ready[end]), push!(running, running[end])
        end
        dag[end] += Δdag
        ready[end] += Δready
        running[end] += Δrunning
    end
    if time[end] < elapsed
        push!(time, elapsed)
        push!(dag, dag[end]), push!(ready, ready[end]), push!(running, running[end])
    end
    return (; time, dag, ready, running)
end

"""
    realized_critical_path(l::LogInfo) -> Vector{Int64}

Tags of the chain of logged tasks which determined when the last task finished,
in execution order.

Starting from the last task to finish, the chain goes back to the predecessor
which made the task ready (see `ready_by` in [`TaskTimeline`](@ref)), until a
task made ready by its insertion. Along the chain, the time is spent either
waiting for the first task to be inserted, or between the moment a task is ready
and the moment it starts (scheduling latency), or running the tasks: these
segments cover the time from the start of the logging window to the end of the
last task.

This is the path that was actually followed during the execution, which differs
from the critical path of [`DataFlowTasks.summarize`](@ref): the longest chain
of dependent tasks, a lower bound of the elapsed time.
"""
function realized_critical_path(l::LogInfo)
    tasks = timeline(l)
    isempty(tasks) && return Int64[]
    bytag = Dict(tag(t) => t for t in tasks)
    t = argmax(t -> (t.finished, tag(t)), tasks)
    path = [tag(t)]
    while t.ready_by != 0
        t = bytag[t.ready_by]
        push!(path, tag(t))
    end
    return reverse!(path)
end

"""
    traceplot(loginfo::LogInfo; categories, highlight, critical_path)
    traceplot!(ax, loginfo::LogInfo; ...)

Plot the trace of the tasks logged in `loginfo`, packed in lanes. This is the
top panel of `Makie.plot(loginfo)`.

This function requires `Makie`; see its documentation in the `Makie` extension
for more details.
"""
function traceplot end

@doc (@doc traceplot) function traceplot! end
