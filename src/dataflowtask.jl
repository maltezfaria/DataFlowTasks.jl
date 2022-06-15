"""
    DataFlowTask(func,data,mode)

Create a task-like object similar to `Task(func)` which accesses `data` with
[`AccessMode`](@ref) `mode`.

When a `DataFlowTask` is created, the elements in its `data` field will be
checked against all other active `DataFlowTask` to determined if a dependency is
present based on a data-flow analysis. The resulting `Task` will then wait on
those dependencies.

A `DataFlowTask` behaves much like a Julia `Task`: you can call `wait(t)`,
`schedule(t)` and `fetch(t)` on it.

## See also: [`@dtask`](@ref), [`@dspawn`](@ref), [`@dasync`](@ref).
"""
mutable struct DataFlowTask
    data::Tuple
    access_mode::NTuple{<:Any,AccessMode}
    tag::Int
    priority::Float64
    label::String
    task::Task
    function DataFlowTask(code,data,mode::NTuple{N,AccessMode},priority=0,label="",sch=getscheduler()) where {N}
        @assert length(data) == N
        TASKCOUNTER[] += 1
        tj    = new(data,mode,TASKCOUNTER[],priority,label)
        addnode!(sch,tj,true)

        # Logging
        if should_log()
            push!(dag_logger, [task.tag for task ∈ inneighbors(sch.dag, tj)])
        end

        deps  = inneighbors(sch.dag,tj) |> copy
        tj.task = @task begin
            for ti in deps
                wait(ti)
            end
            # run the underlying code block and time its execution for logging
            t₀  = time()
            res = code()
            t₁  = time()
            tid = Threads.threadid()

            # Logging
            if should_log()
                task_log = TaskLog(tid, t₀, t₁, tj.tag, tj.label)
                push!(task_logger[tid], task_log)
            end

            put!(sch.finished,tj)
            res
        end
        return tj
    end
end

"""
    const TASKCOUNTER::Ref{Int}

Global counter of created `DataFlowTask`s.
"""
const TASKCOUNTER = Ref(0)

"""
    data(t::DataFlowTask[,i])

Data accessed by `t`.
"""
data(t::DataFlowTask)        = t.data
data(t::DataFlowTask,i)      = t.data[i]

"""
    access_mode(t::DataFlowTask[,i])

How `t` accesses its data.

## See: [`AccessMode`](@ref)
"""
access_mode(t::DataFlowTask)   = t.access_mode
access_mode(t::DataFlowTask,i) = t.access_mode[i]

tag(t::DataFlowTask) = t.tag
tag(t) = t

Base.wait(t::DataFlowTask)  = wait(t.task)
Base.fetch(t::DataFlowTask) = fetch(t.task)

# the tag gives a total order of the tasks, with smaller tasks being assumed to
# have come before in a sequential execution of the program
Base.hash(t::DataFlowTask,h::UInt64)        = hash(t.tag,h)
Base.:(==)(a::DataFlowTask,b::DataFlowTask) = (a.tag == b.tag)
Base.:(<)(a::DataFlowTask,b::DataFlowTask)  = (a.tag < b.tag)

function Base.show(io::IO,t::DataFlowTask)
    if isdefined(t,:task)
        print(io, "DataFlowTask ($(t.task.state)) $(t.tag)")
    else
        print(io, "DataFlowTask (no Task created) $(t.tag)")
    end
end

Base.errormonitor(t::DataFlowTask) = errormonitor(t.task)

"""
    data_dependency(t1::DataFlowTask,t1::DataFlowTask)

Determines if there is a data dependency between `t1` and `t2` based on the data
they read from and write to.
"""
function data_dependency(ti::DataFlowTask, tj::DataFlowTask)
    # unpack and dispatch
    di,dj = data(ti), data(tj)
    mi,mj = access_mode(ti), access_mode(tj)
    _data_dependency(di,mi,dj,mj)
end

@noinline function _data_dependency(datai,modei,dataj,modej)
    for (di,mi) in zip(datai,modei)
        for (dj,mj) in zip(dataj,modej)
            mi == READ && mj == READ && continue
            if memory_overlap(di,dj)
                return true
            end
        end
    end
    return false
end

"""
    memory_overlap(di,dj)

Determine if data `di` and `dj` have overlapping memory in the sense that
mutating `di` can change `dj` (or vice versa). This function is used to build
the dependency graph between [`DataFlowTask`](@ref)s.

A generic version is implemented returning `true` (but printing a warning).
Users should overload this function for the specific data types used in the
arguments to allow for appropriate inference of data dependencies.
"""
function memory_overlap(di,dj)
    (isbits(di) || isbits(dj)) && return false
    @warn "memory_overlap(::$(typeof(di)),::$(typeof(dj))) not implemented. Defaulting to `true`"
    return true
end

"""
    macro dtask(expr,data,mode)

Create a `DataFlowTask` to execute `expr`, where `mode::NTuple{N,AccessMode}`
species how `data::Tuple{N,<:Any}` is accessed in `expr`. Note that the task is
not automatically scheduled for execution.

## See also: [`@dspawn`](@ref), [`@dasync`](@ref)
"""
macro dtask(expr,data,mode,p=0)
    :(DataFlowTask(
        ()->$(esc(expr)),
        $(esc(data)),
        $(esc(mode)),
        $(esc(p))
        )
    )
end
