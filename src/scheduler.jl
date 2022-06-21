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
        @trace "length_finished $(length(c.data)) $(time_ns())"
        v = popfirst!(c.data)
        @trace "length_finished $(length(c.data)) $(time_ns())"
        return v
    finally
        unlock(c)
    end
end

function Base.put!(c::FinishedChannel{T},t::T) where {T}
    lock(c)
    try
        @trace "length_finished $(length(c.data)) $(time_ns())"
        push!(c.data, t)
        @trace "length_finished $(length(c.data)) $(time_ns())"
        notify(c.cond_take)
    finally
        unlock(c)
    end
    return t
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
    setscheduler!(r)

Set the active scheduler to `r`.
"""
setscheduler!(ex) = (SCHEDULER[] = ex)

"""
    getscheduler(sch)

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

graphplot(sch::TaskGraphScheduler=getscheduler()) = graphplot(sch.dag)

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
    sch.dag_worker = errormonitor(task)
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
        isempty(sch.dag) || @warn "Stopping DAG worker of a non-empty graph"
        put!(sch.finished, Stop())
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
    macro dspawn expr data mode

Create a [`DataFlowTask`](@ref) and schedule it to run on any available thread.
The `data` and `mode` arguments are passed to the `DataFlowTask` constructor,
and can be used to indicate how the code in `expr` accesses `data`. These fields
are used to automatically infer task dependencies.

## Examples:

```jldoctest
using DataFlowTasks
using DataFlowTasks: R,W,RW

A = rand(5)

# create a task which writes to A
t1 = @dspawn begin
    sleep(1)
    fill!(A,0)
    println("finished writing")
end (A,) (W,)

# create a task which reads from A
t2 = @dspawn begin
    println("I automatically wait for `t1` to finish")
    sum(A)
end (A,) (R,)

fetch(t2) # 0

# output

finished writing
I automatically wait for `t1` to finish
0.0
```

Note that in the example above `t2` waited for `t1` because it read a data field
that `t1` accessed in a writtable manner.
"""
macro dspawn(expr,data,mode,p=0)
    quote
        t = @dtask $(esc(expr)) $(esc(data)) $(esc(mode)) $(esc(p))
        spawn(t)
    end
end

"""
    macro dasync(expr,data,mode)

Like [`@dspawn`](@ref), but schedules the task to run on the current thread.
"""
macro dasync(expr,data,mode,p=0)
    quote
        t = @dtask $(esc(expr)) $(esc(data)) $(esc(mode)) $(esc(p))
        schedule(t)
    end
end