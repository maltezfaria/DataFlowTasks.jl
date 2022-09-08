"""
    struct FinishedChannel{T} <: AbstractChannel{T}

Used to store tasks which have been completed, but not yet removed from the
underlying `DAG`. Taking from an empty `FinishedChannel` will block.
"""
struct FinishedChannel{T} <: AbstractChannel{T}
    data::Vector{T}
    cond_take::Threads.Condition
    function FinishedChannel{T}() where {T}
        lock      = Threads.ReentrantLock()
        cond_take = Threads.Condition(lock)
        data      = Vector{T}()
        new(data,cond_take)
    end
end

Base.lock(c::FinishedChannel)   = lock(c.cond_take)
Base.unlock(c::FinishedChannel) = unlock(c.cond_take)

Base.length(c::FinishedChannel) = length(c.data)

function Base.take!(c::FinishedChannel)
    lock(c)
    try
        while isempty(c.data)
            wait(c.cond_take)
        end
        v = popfirst!(c.data)
        return v
    finally
        unlock(c)
    end
end

function Base.put!(c::FinishedChannel{T},t::T) where {T}
    lock(c)
    try
        push!(c.data, t)
        notify(c.cond_take)
    finally
        unlock(c)
    end
    return t
end

function Base.empty!(c::FinishedChannel)
    lock(c)
    try
        empty!(c.data)
    finally
        unlock(c)
    end
    return c
end

# https://discourse.julialang.org/t/how-to-kill-thread/34236/8
"""
    struct Stop

Singleton type used to safely interrupt a task reading from an `AbstractChannel.
"""
struct Stop end

const Stoppable{T} = Union{T,Stop}

"""
    abstract type TaskGraphScheduler

Structures implementing a strategy to evaluate a [`DAG`](@ref).

Concrete subtypes are expected to contain a `dag::DAG` field for storing the
task graph, and a `finished::AbstractChannel` field to keep track of completed
tasks. The interface requires the following methods:

-`spawn(t,sch)`
-`schedule(t,sch)`

## See also: [`JuliaScheduler`](@ref), [`PriorityScheduler`](@ref), [`StaticScheduler`](@ref)
"""
abstract type TaskGraphScheduler end

"""
    const SCHEDULER::Ref{TaskGraphScheduler}

The active scheduler being used.
"""
const SCHEDULER = Ref{TaskGraphScheduler}()

"""
    setscheduler!(sch)

Set the active scheduler to `sch`.
"""
setscheduler!(sch) = (SCHEDULER[] = sch)

"""
    getscheduler()

Return the active scheduler.
"""
getscheduler() = (SCHEDULER[])

"""
    with_scheduler(f,sch)

Run `f`, but push `DataFlowTask`s to the scheduler `dag` in `sch` instead of the
default `dag`.
"""
function with_scheduler(f,sch)
    old = getscheduler()
    setscheduler!(sch)
    res = f()
    setscheduler!(old)
    return res
end

spawn(tj::DataFlowTask) = spawn(tj,getscheduler())
Base.schedule(tj::DataFlowTask) = schedule(tj,getscheduler())

addnode!(sch::TaskGraphScheduler,tj,check=true)     = addnode!(sch.dag,tj,check)
remove_node!(sch::TaskGraphScheduler,tj) = remove_node!(sch.dag,tj)

dag(sch::TaskGraphScheduler) = sch.dag

"""
    sync([sch::TaskGraphScheduler])

Wait for all nodes in `sch` to be finished before continuining. If called with
no arguments, use  the current scheduler.
"""
function sync(sch::TaskGraphScheduler=getscheduler())
    dag = sch.dag
    isempty(dag) || wait(dag.cond_empty)
    return sch
end

"""
    struct JuliaScheduler{T} <: TaskGraphScheduler{T}

Implement a simple scheduling strategy which consists of delegating the
[`DataFlowTask`](@ref)s to the native Julia scheduler for execution immediately
after the data dependencies have been analyzed using its `dag::DAG`. This is
the default scheduler used by [`DataFlowTasks`](@ref).

The main advantage of this strategy is its simplicity and composability. The
main disadvantage is that there is little control over how the underlying `Task`s
are executed by the Julia scheduler (e.g., no priorities can be passed).

Calling `JuliaScheduler(sz)` creates a new scheduler with an empty `DAG` of
maximum capacity `sz`.
"""
mutable struct JuliaScheduler{T} <: TaskGraphScheduler
    dag::DAG{T}
    finished::FinishedChannel{Stoppable{T}}
    dag_worker::Task
    function JuliaScheduler{T}(sz = typemax(Int)) where {T}
        if sz <= 0
            throw(ArgumentError("Scheduler buffer size must be a positive integer"))
        end
        dag            = DAG{T}(sz)
        finished       = FinishedChannel{Stoppable{T}}()
        sch            = new(dag,finished)
        start_dag_worker(sch)
        return sch
    end
end
JuliaScheduler(args...) = JuliaScheduler{DataFlowTask}(args...)

capcity(sch) = sch |> dag |> capacity

"""
    restart_scheduler!([sch])

Interrupt all tasks in `sch` and remove them from the underlying `DAG`.

This function is useful to avoid having to restart the REPL when a task in `sch`
errors.
"""
restart_scheduler!() = restart_scheduler!(getscheduler())

function restart_scheduler!(sch::JuliaScheduler)
    @warn "restarting the scheduler: pending tasks will be interrupted and lost."
    stop_dag_worker(sch)
    empty!(sch.finished)
    # go over all task in the dag and interrupt them
    for (t,_) in sch.dag.inoutlist
        istaskstarted(t.task) || schedule(t.task, :stop, error=true)
    end
    empty!(sch.dag)
    start_dag_worker(sch)
    return sch
end

"""
    start_dag_worker(sch)

Start a forever-running task associated with `sch` which takes nodes from
`finished` and removes them from the `dag`. The task blocks if `finished` is
empty.
"""
function start_dag_worker(sch::JuliaScheduler=getscheduler())
    task = @async while true
        @assert Threads.threadid() == 1 # sanity check?
        t = take!(sch.finished)
        t == Stop() && break
        # remove task `t` from the dag
        remove_node!(sch,t)
    end
    sch.dag_worker = task
    return sch.dag_worker
end

function stop_dag_worker(sch::JuliaScheduler=getscheduler())
    t = sch.dag_worker
    @assert istaskstarted(t)
    if istaskdone(t)
        @warn "DAG worker already stopped"
    elseif istaskfailed(t)
        @warn "DAG worker failed"
        return sch.dag_worker
    else # expected result, task is running
        isempty(sch.dag)
        put!(sch.finished, Stop())
        # wait for t to stop before continuining
        wait(t)
    end
    return sch.dag_worker
end

# interface methods for JuliaScheduler
function spawn(tj,::JuliaScheduler)
    tj.task.sticky = false
    schedule(tj.task)
    return tj
end

function Base.schedule(tj,::JuliaScheduler)
    schedule(tj.task)
    return tj
end

function Base.show(io::IO, sch::JuliaScheduler)
    dag = sch.dag
    n = num_nodes(dag)
    e = num_edges(dag)
    f = length(sch.finished)
    s1 = n==1 ? "" : "s"
    s2 = f==1 ? "" : "s"
    s3 = e==1 ? "" : "s"
    print(io, typeof(sch)," with $n active node$s1, $f finished node$s2, and $e edge$s3 (capacity of $(dag.sz_max[]) nodes)")
end

"""
    @dspawn expr [kwargs...]

Create a [`DataFlowTask`](@ref) to execute the code given by `expr`, and
schedule it to run on any available thread. The code in `expr` should be
annotated with `@R`, `@W` and/or `@RW` tags in order to indicate how it accesses
data (see examples below). This information is is then used to automatically
infer task dependencies.

## Supported keyword arguments:

- `label`: provide a label to identify the task. This is useful when logging scheduling information;
- `priority`: inform the scheduler about the relative priority of the task. This
  information is not (yet) leveraged by the default scheduler.

## See also:

[`@dtask`](@ref), [`@dasync`](@ref)

## Examples:

Below are 3 equivalent ways to create the same `DataFlowTask`, which expresses a
Read-Write dependency on `C` and Read dependencies on `A` and `B`

```julia
using LinearAlgebra
A = rand(10, 10)
B = rand(10, 10)
C = rand(10, 10)
α, β = (100.0, 10.0)

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
@dspawn mul!(C, A, B, α, β) @RW(C) @R(A,B)
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
    _dtask(expr, kwargs; source=__source__) do t
        :($spawn($t))
    end
end



"""
    @dasync expr [kwargs...]

Like [`@dspawn`](@ref), but schedules the task to run on the current thread.

## See also:

[`@dspawn`](@ref), [`@dtask`](@ref)
"""
macro dasync(expr, kwargs...)
    _dtask(expr, kwargs; source=__source__) do t
        :($schedule($t))
    end
end
