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

See also: [`@dtask`](@ref), [`@dspawn`](@ref).
"""
mutable struct DataFlowTask
    data::Tuple
    access_mode::Tuple{Vararg{AccessMode}}
    tag::Int
    priority::UInt16
    label::String
    # the active logger when the task was created (if any)
    logger::Maybe{LogInfo}
    task::Task
    function DataFlowTask(
            code,
            data,
            mode::NTuple{N, AccessMode},
            priority = 0,
            label = "",
            sch = get_active_taskgraph(),
        ) where {N}
        @assert length(data) == N
        0 <= priority <= typemax(UInt16) || throw(
            ArgumentError(
                "task priority must be in 0:$(typemax(UInt16)) (0 being the most urgent), got $priority",
            ),
        )
        taskcounter = 0 # not yet inserted in a dag. This will be modified upon insertion.
        logger = _log_mode() ? _getloginfo() : nothing
        # the insertion is requested before waiting for the lock of the dag
        time_request = isnothing(logger) ? UInt64(0) : time_ns()
        tj = new(data, mode, taskcounter, priority, label, logger)
        # hold the lock so that the dag cleaner cannot modify the dependencies of
        # `tj` before they are copied
        deps = @lock dag(sch).lock begin
            addnode!(sch, tj, true, logger, time_request)
            copy(inneighbors(dag(sch), tj))
        end
        tj.task = @task handle_errors() do
            # read from `tj`: capturing the `logger` of the constructor (of type
            # `Maybe{LogInfo}`) makes the creation of the task measurably slower.
            # `local` is needed, otherwise the assignment would capture it.
            local logger = tj.logger
            # time the execution of the body for logging (the running time
            # excludes the time the task is descheduled)
            t₀ = r₀ = UInt64(0)
            tid₀ = 0
            failed = true
            try
                # wait for all the dependencies, even if one of them failed, so
                # that `tj` does not leave the dag before its predecessors
                err = nothing
                for ti in deps
                    try
                        wait(ti)
                    catch e
                        err = something(err, e)
                    end
                end
                isnothing(err) || throw(err)
                if !isnothing(logger)
                    tid₀ = Threads.threadid()
                    # the wall time interval encloses the running one, so that
                    # the running time does not exceed the wall time
                    t₀ = time_ns()
                    r₀ = something(running_time_ns(), UInt64(0))
                end
                res = code()
                failed = false
                return res
            finally
                if !isnothing(logger)
                    r₁ = running_time_ns()
                    t₁ = time_ns()
                    # the body did not start if waiting for a dependency failed
                    t₀ == 0 && (t₀ = t₁; tid₀ = Threads.threadid())
                    # without task metrics, fall back to the wall time
                    running = isnothing(r₁) || r₀ == 0 ? t₁ - t₀ : r₁ - r₀
                    tid₁ = Threads.threadid()
                    inneighbors = [t.tag for t in deps]
                    log = TaskLog(tj.tag, t₀, t₁, running, tid₀, tid₁, inneighbors, tj.label, failed)
                    record!(logger, log)
                end
                # also on failure, so that the node is removed from the dag (tasks
                # depending on `tj` still fail since waiting on `tj` rethrows)
                put!(sch.finished, tj)
            end
        end
        # when several tasks are waiting for a thread, Julia's scheduler tends to
        # start the ones with the smallest priority value first
        tj.task.priority = tj.priority
        tj.data = (tj.data..., tj.task)
        tj.access_mode = (tj.access_mode..., READWRITE)
        # record the data accesses to compute the complete dependencies
        isnothing(logger) || record!(
            logger,
            LoggedAccess(tj.tag, objectid(dag(sch)), tj.data, tj.access_mode, _linear_dag()),
        )
        return tj
    end
end

"""
    data(t::DataFlowTask[,i])

Data accessed by `t`.
"""
data(t::DataFlowTask) = t.data
data(t::DataFlowTask, i) = t.data[i]

"""
    access_mode(t::DataFlowTask[,i])

How `t` accesses its data.

## See: [`AccessMode`](@ref)
"""
access_mode(t::DataFlowTask) = t.access_mode
access_mode(t::DataFlowTask, i) = t.access_mode[i]

Base.istaskdone(t::DataFlowTask) = istaskdone(t.task)
Base.istaskfailed(t::DataFlowTask) = istaskfailed(t.task)
Base.istaskstarted(t::DataFlowTask) = istaskstarted(t.task)
Base.wait(t::DataFlowTask) = wait(t.task)
Base.fetch(t::DataFlowTask) = fetch(t.task)

# the tag gives a total order of the tasks, with smaller tasks being assumed to
# have come before in a sequential execution of the program
tag(t::DataFlowTask) = t.tag
tag(t) = t

Base.hash(t::DataFlowTask, h::UInt64) = hash(t.tag, h)
Base.:(==)(a::DataFlowTask, b::DataFlowTask) = (a.tag == b.tag)
Base.isless(a::DataFlowTask, b::DataFlowTask) = isless(a.tag, b.tag)

function Base.show(io::IO, t::DataFlowTask)
    return if isdefined(t, :task)
        print(io, "DataFlowTask ($(t.task.state)) $(t.tag)")
    else
        print(io, "DataFlowTask (no Task created) $(t.tag)")
    end
end

"""
    data_dependency(t1::DataFlowTask,t1::DataFlowTask)

Determines if there is a data dependency between `t1` and `t2` based on the data
they read from and write to.
"""
function data_dependency(ti::DataFlowTask, tj::DataFlowTask)
    # unpack and dispatch
    di, dj = data(ti), data(tj)
    mi, mj = access_mode(ti), access_mode(tj)
    return _data_dependency(di, mi, dj, mj)
end

@noinline function _data_dependency(datai, modei, dataj, modej)
    for (di, mi) in zip(datai, modei)
        for (dj, mj) in zip(dataj, modej)
            mi == READ && mj == READ && continue
            if memory_overlap(di, dj)
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
function memory_overlap(di, dj)
    (isbits(di) || isbits(dj)) && return false
    (di isa Task || dj isa Task) && return di === dj
    @warn """using fallback `memory_overlap(::Any,::Any) = true`. Consider implementing
    `DataFlowTasks.memory_overlap(::$(typeof(di)),::$(typeof(dj)))`.
    """
    return true
end

"""
    force_linear_dag(mode=false)

If `mode` is `true`, nodes are added to the DAG in a linear fashion, i.e. the DAG
connects node `i` to node `i+1`. This is useful for debugging purposes.
"""
function force_linear_dag(mode = false)
    return @eval _linear_dag() = $mode
end

_linear_dag() = false

"""
    force_sequential(mode = true)

If `mode` is `true`, enable sequential mode: no tasks are created and scheduled,
code is simply run as it appears in the sources. In effect, `@dspawn expr`
evaluates `expr` and returns its value instead of a `Task` (`fetch` still works
on it, but `wait` does not).

By default, sequential mode is disabled when the program starts.

See also: [`force_linear_dag`](@ref).
"""
function force_sequential(seq::Bool = true; static::Bool = false)
    dyn = static ? :sta : :dyn
    par = seq ? :seq : :par
    _sequential_mode() == (dyn, par) && return (dyn, par)

    if static
        @warn "Statically setting sequential/parallel mode is not recommended"
    end
    @eval _sequential_mode() = $(tuple(dyn, par))
    return (dyn, par)
end

_sequential_mode() = (:dyn, :par)

# Try to parse `expr` as an access tag applied to some data
# - if not successful: return `nothing`
# - otherwise: register the data and their access mode in `data` and `mode`
_try_register_access!(_, _, _) = nothing
function _try_register_access!(data, mode, expr::Expr)
    if expr.head == :macrocall
        tags = (READ => ("@R", "@←"), WRITE => ("@W", "@→"), READWRITE => ("@RW", "@↔"))
        for (m, t) in tags
            if expr.args[1] ∈ Symbol.(t)
                # Register access mode `m` for all data listed in `expr`
                # If multiple data are listed, only return the first one
                for i in 3:length(expr.args)
                    push!(data, expr.args[i])
                    push!(mode, m)
                end
                return expr.args[3]
            end
        end
    end

    return nothing
end

# Detect @R/@W/@RW tags in the task body:
# 1. register the associated data and mode
# 2. remove tags from the final expression
_transform!(_, _, x) = x
function _transform!(data, mode, x::Expr)
    ret = _try_register_access!(data, mode, x)

    # `x` was successfully parsed as a mode specification
    isnothing(ret) || return ret

    # Fallback
    return Expr(x.head, (_transform!(data, mode, arg) for arg in x.args)...)
end

function _dtask(
        continuation,
        expr,
        kwargs;
        source = LineNumberNode(@__LINE__, @__FILE__),
    )
    data = []
    mode = []
    new_expr = _transform!(data, mode, expr)

    # Handle optional keyword arguments
    defaults = (
        label = "",  # task label
        priority = 0,   # task priority
    )

    params = foldl(kwargs; init = defaults) do params, opt
        isnothing(_try_register_access!(data, mode, opt)) || return params

        if !(opt isa Expr && opt.head == :(=))
            @warn(
                "Malformed DataFlowTask parameter: `$opt`",
                _file = string(source.file),
                _line = source.line
            )
            return params
        end

        opt_name = opt.args[1]
        opt_val = opt.args[2]
        if opt_name ∉ keys(params)
            @warn(
                "Unknown DataFlowTask parameter: `$opt`",
                _file = string(source.file),
                _line = source.line
            )
            return params
        end

        return Base.setindex(params, opt_val, opt_name)
    end

    data_expr = Expr(:tuple, data...)
    mode_tuple = Tuple(mode)

    t = gensym(:task)
    (dyn, par) = _sequential_mode()
    return if dyn == :dyn      # Dynamic mode -> choose at compile time
        quote
            (dyn, par) = $_sequential_mode()
            if par == :par
                $t = $DataFlowTask(
                    () -> $(esc(new_expr)),
                    $(esc(data_expr)),
                    $(mode_tuple),
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
                () -> $(esc(new_expr)),
                $(esc(data_expr)),
                $(mode_tuple),
                $(esc(params.priority)),
                $(esc(params.label)),
            )
            $(continuation(t))
        end
    else                # Static mode -> generate specific, sequential code
        esc(new_expr)
    end
end

_dtask(expr, params; kwargs...) = _dtask(identity, expr, params; kwargs...)

"""
    @dtask expr [kwargs...]

Create a `DataFlowTask` to execute `expr`, where data have been tagged to
specify how they are accessed. The task is inserted in the active `TaskGraph`,
but not scheduled: `schedule(t)` runs it on the `:default` threadpool, as
[`@dspawn`](@ref) does. Unlike `@dspawn`, which returns the Julia `Task`, this
gives access to the `DataFlowTask` itself (e.g. its label or priority).

See [`@dspawn`](@ref) for information on how to annotate `expr` to specify data
dependencies, and a list of supported keyword arguments.

See also: [`@dspawn`](@ref)
"""
macro dtask(expr, kwargs...)
    return _dtask(expr, kwargs; source = __source__)
end
