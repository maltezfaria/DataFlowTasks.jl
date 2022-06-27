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

        # Store inneighbors if logging activated
        _log_mode() && (inneighbors_ = [task.tag for task ∈ inneighbors(sch.dag, tj)])

        deps  = inneighbors(sch.dag,tj) |> copy
        tj.task = @task handle_errors() do
            if sch isa JuliaScheduler
                # in this case julia handles the scheduling, so we must pass the
                # dependencies to the julia scheduler
                for ti in deps
                    wait(ti)
                end
            end
            # run the underlying code block and time its execution for logging
            t₀  = time_ns()
            res = code()
            t₁  = time_ns()
            # Push new TaskLog if logging activated
            if _log_mode()
                tid = Threads.threadid()
                task_log = TaskLog(tj.tag, t₀, t₁, tid, inneighbors_, tj.label)
                push!(getlogger().tasklogs[tid], task_log)
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
    resetcounter!()

Reset the [`TASKCOUNTER`](@ref) to `0`.
"""
function resetcounter!()
    TASKCOUNTER[] = 0
end

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
    enable_sequential(mode = true)

If `mode` is `true`, enable sequential mode: no tasks are created and scheduled,
code is simply run as it appears in the sources. In effect, this makes `@dspawn`
a no-op.

By default, sequential mode is disabled when the program starts.
"""
function enable_sequential(seq::Bool = true; static::Bool = false)
    dyn = static ? :sta : :dyn
    par = seq    ? :seq : :par
    if static
        @warn "Statically setting sequential/parallel mode is not recommended"
    end
    @eval _sequential_mode() = $(tuple(dyn, par))
    nothing
end
enable_sequential(false)


function _dtask(continuation, expr::Expr, kwargs; source=LineNumberNode(@__LINE__, @__FILE__))
    data = []
    mode = []

    # Register access mode `m` for all data listed in `expr`
    # If multiple data are listed, only return the first one
    function register_modes(expr, m)
        for i in 3:length(expr.args)
            push!(data, expr.args[i])
            push!(mode, m)
        end
        return expr.args[3]
    end

    # Detect @R/@W/@RW tags in the task body:
    # - register the associated data and mode
    # - remove tags from the final expression
    transform(x) = x
    function transform(x::Expr)
        if x.head == :macrocall
            tags = (READ      => ("@R",  "@←"),
                    WRITE     => ("@W",  "@→"),
                    READWRITE => ("@RW", "@↔"))
            for (m, t) in tags
                x.args[1] ∈ Symbol.(t) && return register_modes(x, m)
            end
        end

        return Expr(x.head, transform.(x.args)...)
    end

    new_expr = transform(expr)
    data = Expr(:tuple, data...)
    mode = Tuple(mode)


    # Handle optional keyword arguments
    defaults = (
        label    = "",  # task label
        priority = 0,   # task priority
    )

    params = foldl(kwargs, init=defaults) do params, opt
        if !(opt isa Expr && opt.head == :(=))
            @warn("Malformed DataFlowTask parameter: `$opt`",
                  _file = string(source.file),
                  _line = source.line)
            return params
        end

        opt_name = opt.args[1]
        opt_val  = opt.args[2]
        if opt_name ∉ keys(params)
            @warn("Unknown DataFlowTask parameter: `$opt`",
                  _file = string(source.file),
                  _line = source.line)
            return params
        end

        return Base.setindex(params, opt_val, opt_name)
    end

    t = gensym(:task)
    (dyn, par) = _sequential_mode()
    if dyn == :dyn      # Dynamic mode -> choose at compile time
        quote
            (dyn, par) = $_sequential_mode()
            if par == :par
                $t = $DataFlowTask(
                    ()->$(esc(new_expr)),
                    $(esc(data)),
                    $(mode),
                    $(esc(params.priority)),
                    $(esc(params.label)),
                )
                $(continuation(t))
            else
                $(esc(new_expr))
            end
        end
    elseif par == :par  # Static mode -> generate specific, parallel code
        quote
            $t = $DataFlowTask(
                ()->$(esc(new_expr)),
                $(esc(data)),
                $(mode),
                $(esc(params.priority)),
                $(esc(params.label)),
            )
            $(continuation(t))
        end
    else                # Static mode -> generate specific, sequential code
        esc(new_expr)
    end
end

_dtask(expr::Expr, params; kwargs...) = _dtask(identity, expr, params; kwargs...)

"""
    @dtask expr [kwargs...]

Create a `DataFlowTask` to execute `expr`, where data have been tagged to
specify how they are accessed. Note that the task is not automatically scheduled
for execution.

See [`@dspawn`](@ref) for information on how to annotate `expr` to specify data
dependencies, and a list of supported keyword arguments.

## See also:

[`@dspawn`](@ref), [`@dasync`](@ref)
"""
macro dtask(expr, kwargs...)
    _dtask(expr, kwargs; source=__source__)
end
