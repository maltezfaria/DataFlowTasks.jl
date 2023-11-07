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

"""
    const TASKGRAPH::Ref{TASKGRAPH}

The active `TaskGraph` being used. Nodes will be added to this `TaskGraph` by
default.

Can be changed using [`set_active_taskgraph!`](@ref).
"""
const TASKGRAPH = Ref{TaskGraph}()

"""
    set_active_taskgraph!(tg)

Set the active [`TaskGraph`](@ref) to `tg`.
"""
set_active_taskgraph!(tg) = (TASKGRAPH[] = tg)

"""
    get_active_taskgraph()

Return the active [`TaskGraph`](@ref).
"""
get_active_taskgraph() = (TASKGRAPH[])

"""
    with_taskgraph(f,tg::TaskGraph)

Run `f`, but push `DataFlowTask`s to `tg`.
"""
function with_taskgraph(f, tg)
    old = get_active_taskgraph()
    set_active_taskgraph!(tg)
    res = f()
    set_active_taskgraph!(old)
    return res
end

addnode!(taskgraph::TaskGraph, tj, check = true) = addnode!(taskgraph.dag, tj, check)
remove_node!(taskgraph::TaskGraph, tj) = remove_node!(taskgraph.dag, tj)

dag(sch::TaskGraph) = sch.dag

"""
    wait(tg::TaskGraph)

Wait for all nodes in `tg` to be finished before continuining.

To wait on the active `TaskGraph`, use `wait(get_active_taskgraph())`.
"""
function Base.wait(taskgraph::TaskGraph)
    dag = taskgraph.dag
    isempty(dag) || wait(dag.cond_empty)
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

Interrupt all tasks in `tg` and remove them from the underlying `DAG`.

This function is useful to avoid having to restart the REPL when a task in `tg`
errors.
"""
function Base.empty!(tg::TaskGraph)
    @warn "emptying the tasgraph: pending tasks will be interrupted and lost."
    stop_dag_cleaner(tg)
    empty!(tg.finished)
    # go over all task in the dag and interrupt them
    for (t, _) in tg.dag.inoutlist
        istaskstarted(t.task) || schedule(t.task, :stop; error = true)
    end
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
    task = @async while true
        t = take!(tg.finished)
        t == Stop() && break
        # remove task `t` from the dag
        remove_node!(tg, t)
    end
    tg.dag_cleaner = task
    return tg.dag_cleaner
end

function stop_dag_cleaner(tg::TaskGraph = get_active_taskgraph())
    t = tg.dag_cleaner
    @assert istaskstarted(t)
    if istaskdone(t)
        @warn "DAG worker already stopped"
    elseif istaskfailed(t)
        @warn "DAG worker failed"
        return tg.dag_cleaner
    else # expected result, task is running
        put!(tg.finished, Stop())
        # wait for t to stop before continuining
        wait(t)
    end
    return tg.dag_cleaner
end

# interface methods for TaskGraph
function spawn(tj::DataFlowTask)
    tj.task.sticky = false
    return schedule(tj.task)
end

function Base.schedule(tj::DataFlowTask)
    return schedule(tj.task)
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
- `priority`: inform the scheduler about the relative priority of the task. This
  information is not (yet) leveraged by the default scheduler.

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
    _dtask(expr, kwargs; source = __source__) do t
        return :($spawn($t))
    end
end

"""
    @dasync expr [kwargs...]

Like [`@dspawn`](@ref), but schedules the task to run on the current thread.

See also:

[`@dspawn`](@ref), [`@dtask`](@ref)
"""
macro dasync(expr, kwargs...)
    _dtask(expr, kwargs; source = __source__) do t
        return :($schedule($t))
    end
end
