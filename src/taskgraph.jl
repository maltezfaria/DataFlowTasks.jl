"""
    struct TaskGraph

A directed acyclic graph used to reprenset the dependencies between
[`DataFlowTask`](@ref)s.

`TaskGraph(sz)` creates a task graph that can hold at most `sz` elements at any
given time. In particular, trying to add a new `DataFlowTask` will block if the
`TaskGraph` is already full.

See also: [`get_active_taskgraph`](@ref), [`set_active_taskgraph!`](@ref)
"""
mutable struct TaskGraph
    dag::DAG{DataFlowTask}
    finished::FinishedChannel{Stoppable{DataFlowTask}}
    dag_cleaner::Task
    function TaskGraph(sz = typemax(Int))
        if sz <= 0
            throw(ArgumentError("Capacity must be a positive integer"))
        end
        dag = DAG{DataFlowTask}(sz)
        finished = FinishedChannel{Stoppable{DataFlowTask}}()
        sch = new(dag, finished)
        start_dag_cleaner(sch)
        return sch
    end
end

# The default `TaskGraph`, used outside of any `with_taskgraph` block
const DEFAULT_TASKGRAPH = Ref{TaskGraph}()

# The `TaskGraph` of the innermost enclosing `with_taskgraph` block (if any). As a
# `ScopedValue`, it is seen by the code running inside the block and by the tasks
# created inside the block, but not by the other tasks.
const TASKGRAPH = ScopedValue{Union{Nothing, TaskGraph}}(nothing)

"""
    set_active_taskgraph!(tg)

Set the default [`TaskGraph`](@ref) to `tg`. The default `TaskGraph` is used
outside of [`with_taskgraph`](@ref) blocks.
"""
set_active_taskgraph!(tg) = (DEFAULT_TASKGRAPH[] = tg)

"""
    get_active_taskgraph()

Return the active [`TaskGraph`](@ref): the one of the innermost enclosing
[`with_taskgraph`](@ref) block (a task created inside such a block is also
considered inside it), or the default one (see [`set_active_taskgraph!`](@ref)).
"""
get_active_taskgraph() = something(TASKGRAPH[], DEFAULT_TASKGRAPH[])

"""
    with_taskgraph(f,tg::TaskGraph)

Run `f`, but push the `DataFlowTask`s created by `f` to `tg`. This includes the
`DataFlowTask`s created by the tasks that `f` creates, but other tasks running
concurrently are not affected.
"""
with_taskgraph(f, tg) = with(f, TASKGRAPH => tg)

function addnode!(taskgraph::TaskGraph, tj, check = true, logger = nothing, time_request = UInt64(0))
    addnode!(taskgraph.dag, tj, check, logger, time_request)
    return taskgraph
end
remove_node!(taskgraph::TaskGraph, tj, logger = nothing) = remove_node!(taskgraph.dag, tj, logger)

dag(sch::TaskGraph) = sch.dag

"""
    wait(tg::TaskGraph)

Wait for all nodes in `tg` to be finished before continuining.

To wait on the active `TaskGraph`, use `wait(get_active_taskgraph())`.
"""
function Base.wait(taskgraph::TaskGraph)
    dag = taskgraph.dag
    lock(dag)
    try
        while !isempty(dag)
            wait(dag.cond_empty)
        end
    finally
        unlock(dag)
    end
    return taskgraph
end

Base.isempty(taskgraph::TaskGraph) = isempty(taskgraph.dag)

capcity(taskgraph) = taskgraph |> dag |> capacity

"""
    resize!(tg::TaskGraph, sz)

Change the buffer size of `tg` to `sz`.
"""
Base.resize!(tg::TaskGraph, sz) = (resize!(tg.dag, sz); tg)

"""
    empty!(tg::TaskGraph)

Remove all the tasks from `tg`, so that the tasks spawned afterwards do not
depend on them.

This function is useful when tasks in `tg` are blocked (e.g. waiting for a
resource which is never released), to avoid having to restart the REPL. The
removed tasks are not interrupted: those which are running or waiting to run
keep doing so.
"""
function Base.empty!(tg::TaskGraph)
    @warn "emptying the task graph: its tasks are not interrupted, but new tasks no longer depend on them"
    stop_dag_cleaner(tg)
    empty!(tg.finished)
    empty!(tg.dag)
    start_dag_cleaner(tg)
    return tg
end

"""
    start_dag_cleaner(tg)

Start a task associated with `tg` which takes nodes from its `finished` queue
and removes them from the `dag`. The task blocks if `finished` is empty.
"""
function start_dag_cleaner(tg::TaskGraph = get_active_taskgraph())
    # run on the interactive threadpool (if any) so that the bookkeeping is not
    # delayed by the computations running on the default threadpool
    task = Threads.@spawn :interactive while true
        t = take!(tg.finished)
        t isa Stop && break
        # remove task `t` from the dag (the removal is logged if `t` is)
        remove_node!(tg, t, t.logger)
    end
    tg.dag_cleaner = task
    return tg.dag_cleaner
end

function stop_dag_cleaner(tg::TaskGraph = get_active_taskgraph())
    t = tg.dag_cleaner
    # NOTE: `t` may not have started yet, but it will still receive the `Stop`
    if istaskfailed(t)
        @warn "DAG worker failed"
    elseif istaskdone(t)
        @warn "DAG worker already stopped"
    else # expected result, task is running (or about to)
        put!(tg.finished, Stop())
        # wait for t to stop before continuing
        wait(t)
    end
    return tg.dag_cleaner
end

# interface methods for TaskGraph
spawn(tj::DataFlowTask) = schedule(tj)

"""
    schedule(t::DataFlowTask)

Schedule `t` to run on the `:default` threadpool (as [`@dspawn`](@ref) does),
and return its Julia `Task`.
"""
function Base.schedule(tj::DataFlowTask)
    tj.task.sticky = false
    # A `Task` inherits the threadpool of its parent. Since Julia 1.12 the main
    # task lives in the `:interactive` pool, so explicitly move `tj` to the
    # `:default` pool like `Threads.@spawn` does.
    Threads._spawn_set_thrpool(tj.task, :default)
    log_task!(tj)
    return schedule(tj.task)
end

#= Record `tj` in the logger which was active when it was created (if any), which
waits for it before closing its logging window =#
function log_task!(tj::DataFlowTask)
    logger = tj.logger
    isnothing(logger) || record!(logger, tj.task)
    return
end

function Base.show(io::IO, sch::TaskGraph)
    dag = sch.dag
    n = num_nodes(dag)
    e = num_edges(dag)
    f = length(sch.finished)
    s1 = n == 1 ? "" : "s"
    s2 = f == 1 ? "" : "s"
    s3 = e == 1 ? "" : "s"
    return print(
        io,
        typeof(sch),
        " with $n active node$s1, $f finished node$s2, and $e edge$s3 (capacity of $(dag.sz_max[]) nodes)",
    )
end

"""
    @dspawn expr [kwargs...]

Spawn a Julia `Task` to execute the code given by `expr`, and schedule it to
run on any available thread.

Annotate the code in `expr` with `@R`, `@W` and/or `@RW` to indicate how it
accesses data (see examples below). This information is used to automatically
infer task dependencies.

Additionally, the following keyword arguments can be provided:

- `label`: provide a label to identify the task. This is useful when logging
  scheduling information;
- `priority`: an integer in `0:65535` (`0` by default) setting the priority of
  the underlying Julia `Task`. As in Julia, `0` is the most urgent: when several
  tasks are waiting for a thread, the ones with a smaller priority value tend to
  be started first. Priorities do not interrupt running tasks, are only
  approximately respected, and have no effect when the `:default` threadpool has
  a single thread.

## Semantics

- The task is inserted in the active `TaskGraph` (see
  [`get_active_taskgraph`](@ref)) before `@dspawn` returns. Its dependencies
  are inferred from the tasks already in the `TaskGraph`, so that they follow the
  order of the `@dspawn` calls (see [nested tasks](@ref nested-tasks) for the
  case of tasks spawned concurrently).
- If the `TaskGraph` is full, `@dspawn` blocks until a task finishes (see
  [`resize!`](@ref)).
- The task runs on the `:default` threadpool, once all the tasks it depends on
  have finished. If one of them failed, the task fails as well.
- `@dspawn` returns the Julia `Task` running the [`DataFlowTask`](@ref), which
  can be `wait`ed on or `fetch`ed. To access the `DataFlowTask` itself, create
  it with [`@dtask`](@ref) and run it with `schedule`.

## Examples:

Below are 3 equivalent ways to create the same `Task`, which expresses a
Read-Write dependency on `C` and Read dependencies on `A` and `B`

```jldoctest; output = false
using LinearAlgebra
using DataFlowTasks
A = ones(5, 5)
B = ones(5, 5)
C = zeros(5, 5)
α, β = (1, 0)

# Option 1: annotate arguments in a function call
@dspawn mul!(@RW(C), @R(A), @R(B), α, β)

# Option 2: specify data access modes in the code block
@dspawn begin
   @RW C
   @R  A B
   mul!(C, A, B, α, β)
end

# Option 3: specify data access modes after the code block
# (i.e. alongside keyword arguments)
res = @dspawn mul!(C, A, B, α, β) @RW(C) @R(A,B)

fetch(res) # a 5×5 matrix of 5.0

# output

5×5 Matrix{Float64}:
 5.0  5.0  5.0  5.0  5.0
 5.0  5.0  5.0  5.0  5.0
 5.0  5.0  5.0  5.0  5.0
 5.0  5.0  5.0  5.0  5.0
 5.0  5.0  5.0  5.0  5.0
```

Here is a more complete example, demonstrating a full computation involving 2 different tasks.

```jldoctest
using DataFlowTasks

A = rand(5)

# create a task with WRITE access mode to A
# and label "writer"
t1 = @dspawn begin
    @W A
    sleep(1)
    fill!(A,0)
    println("finished writing")
end  label="writer"

# create a task with READ access mode to A
t2 = @dspawn begin
    @R A
    println("I automatically wait for `t1` to finish")
    sum(A)
end  priority=1

fetch(t2) # 0

# output

finished writing
I automatically wait for `t1` to finish
0.0
```

Note that in the example above `t2` waited for `t1` because it read a data field
that `t1` accessed in a writable manner.
"""
macro dspawn(expr, kwargs...)
    return _dtask(expr, kwargs; source = __source__) do t
        return :($spawn($t))
    end
end
