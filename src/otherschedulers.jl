#=
WARNING: the other schedulers are mostly experimental and likely to disappear in
the future.
=#

"""
    struct RunnableChannel <: AbstractChannel{DataFlowTask}

Used to store tasks which have been tagged as dependency-free, and thus can be
executed. The underlying data is stored using a priority queue, with elements
with a high priority being popped first.

Calling `take` on an empty `RunnableChannel` will block.
"""
struct RunnableChannel{T}
    data::PriorityQueue{T,Float64}
    cond_take::Threads.Condition
    function RunnableChannel{T}() where {T}
        lock = Threads.ReentrantLock()
        cond_take = Threads.Condition(lock)
        # larger is more urgent in priority
        data = PriorityQueue{T,Float64}(Base.Order.ReverseOrdering())
        new(data,cond_take)
    end
end
Base.lock(c::RunnableChannel)   = lock(c.cond_take)
Base.unlock(c::RunnableChannel) = unlock(c.cond_take)

function Base.take!(c::RunnableChannel)
    lock(c)
    try
        while isempty(c.data)
            wait(c.cond_take)
        end
        v = dequeue!(c.data)
        return v
    finally
        unlock(c)
    end
end

function Base.put!(c::RunnableChannel{T},t::T,p=1) where {T}
    lock(c)
    try
        push!(c.data, t=>p)
        notify(c.cond_take)
    finally
        unlock(c)
    end
    return t
end

"""
    StaticScheduler{T} <: TaskGraphScheduler{T}

Like the [`JuliaScheduler`](@ref), but requires an explicit call to [`execute_dag(ex)`](@ref) to
start running the nodes in its `dag` (and removing them as they are completed).

Using a `StaticScheduler` is useful if you wish examine the
underling `TaskGraph` before it is executed.
"""
struct StaticScheduler{T} <: TaskGraphScheduler
    dag::DAG{T}
    finished::FinishedChannel{T}
    dag_worker::Task
    function StaticScheduler{T}() where {T}
        dag            = DAG{T}() # unbuffered dag
        finished       = FinishedChannel{T}()
        worker         = consume_finished(dag,finished)
        sch            = new(dag,finished,worker)
        return sch
    end
end
StaticScheduler() = StaticScheduler{DataFlowTask}()

# interface methods for StaticScheduler
function spawn(tj,::StaticScheduler)
    tj.task.sticky = false
    return tj
end

function Base.schedule(tj,::StaticScheduler)
    # delay the scheduling of tj.task until execute_dag is called
    return tj
end

"""
    execute_dag(sch::StaticScheduler)

Execute all the nodes in the task graph, removing them from the `dag` as they
are completed. This function waits for the dag to be emptied before returning.
"""
function execute_dag(sch::StaticScheduler)
    if isempty(sch.dag)
        @warn "DAG is empty"
        return sch
    else
        for (t,_) in sch.dag
            schedule(t.task)
        end
        # wait on dag to be emptied. This means all nodes have been ran and finished.
        wait(sch)
        return sch
    end
end

"""
    struct PriorityScheduler{T} <: TaskGraphScheduler{T}

Execute a `DAG` by spawning workers that take elements from the `runnable`
channel, execute them, and put them into a `finished` channel to be processed by
a `dag_worker`.
"""
struct PriorityScheduler{T} <: TaskGraphScheduler
    dag::DAG{T}
    runnable::RunnableChannel{T}
    finished::FinishedChannel{T}
    dag_worker::Task
    task_workers::Vector{Task}
    function PriorityScheduler{T}(sz = typemax(Int),background=true) where {T}
        if sz <= 0
            throw(ArgumentError("Scheduler buffer size must be a positive integer"))
        end
        dag            = DAG{T}(sz)
        nt             = Threads.nthreads()
        runnable       = RunnableChannel{T}()
        finished       = FinishedChannel{T}()
        dag_worker     = finished_to_runnable(dag,finished,runnable)
        task_workers   = consume_runnable(runnable,nt,background)
        sch            = new(dag,runnable,finished,dag_worker,task_workers)
        return sch
    end
end
PriorityScheduler(args...) = PriorityScheduler{DataFlowTask}(args...)

"""
    finished_to_runnable(dag,runnable,finished)

Worker which takes nodes from `finished`, remove them from the `dag`, and `put!`
new nodes in `runnable` if they become dependency-free.
"""
function finished_to_runnable(dag,finished,runnable)
    task = @async while true
        t    = take!(finished)
        # check if anyone in outlist is dependency-free after removal of t
        outlist = outneighbors(dag,t)
        remove_node!(dag,t)
        for j in outlist
            if isempty(inneighbors(dag,j))
                p = priority(j)
                put!(runnable,j,p)
            end
        end
    end
    maybe_errormonitor(task)
end

"""
    priority(t::DataFlowTask)

Function called to determine the scheduled priority of `t`. The default
imlementation simply retuns `t.priority`.
"""
function priority(j::DataFlowTask)
    j.priority
end

"""
    consume_runnable(runnable,nt,background=false)

Spawn `nt = Threads.nthreads()` workers that will consume tasks
from `runnable` and execute them. If `background=true` the main thread
(`Threads.threadid()==1`) is not used, and only `nt-1` `tasks` are spawned.
"""
function consume_runnable(runnable,nt,background=false)
    tasks = Task[]
    i1 = nt == 1 ? 1 : background ? 2 : 1
    for i in i1:nt
        t = @tspawnat i begin
            while true
                t    = take!(runnable)
                execute(t,i)
            end
        end
        t.sticky = VERSION >= v"1.7"
        push!(tasks,maybe_errormonitor(t))
    end
    return tasks
end

function execute(t::DataFlowTask,i)
    # FIXME: how to properly `execute` a Task without passing it to the
    # scheduler? Naive approach is to schedule and wait, but that seems silly in
    # the cases where where we know the task can just run immediately, so it is
    # safe to bypass the julia scheduler.
    # idea taken from ThreadPools (https://github.com/tro3/ThreadPools.jl)
    task = t.task
    task.sticky = VERSION >= v"1.7"
    ccall(:jl_set_task_tid, Cvoid, (Any, Cint), task, i-1)
    # ccall(:jl_set_next_task, Cvoid, (Any,), task)
    # yield(task)
    schedule(task)
    wait(task)
    # task = t.task
    # task.result = Base.invokelatest(task.code)
    # task._state = 1
    # donenotify  = task.donenotify
    # lock(donenotify)
    # notify(donenotify)
    # unlock(donenotify)
end

# interface for PriorityScheduler
function spawn(tj,sch::PriorityScheduler)
    # each worker of the priority scheduler takes from runnable, so no need
    # to change sticky tj.task.sticky = false
    deps  = inneighbors(sch.dag,tj)
    if isempty(deps)
        p = priority(tj)
        put!(sch.runnable,tj,p)
    end
    # Since only tid 1 works on the dag, it is better to yield so that the
    # dag_worker can process finished nodes on the dag and make new nodes
    # runnable before continuing adding even more nodes to the dag
    yield()
    return tj
end

function Base.schedule(tj,sch::PriorityScheduler)
    deps  = inneighbors(sch.dag,tj)
    if isempty(deps)
        put!(sch.runnable,tj)
    end
    return tj
end
