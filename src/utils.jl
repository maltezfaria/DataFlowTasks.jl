"""
    enable_log(mode = true)

If `mode` is `true` (the default), logging is enabled throug the [`@log`](@ref)
macro. Calling `enable_log(false)` will de-activate logging at compile time to
avoid any possible overhead.

Note that changing the log mode at runtime will may invalidate code, possibly
triggering recompilation.

See also: [`@log`](@ref), [`with_logging`](@ref)
"""
function enable_log(mode = true)
    _log_mode() == mode && return mode
    @eval _log_mode() = $mode
    return mode
end

_log_mode() = true

"""
    enable_debug(mode = true)

If `mode` is `true` (the default), enable debug mode: errors inside tasks will be
shown.
"""
function enable_debug(mode = true)
    _debug_mode() == mode && return mode
    @eval _debug_mode() = $mode
    return mode
end

_debug_mode() = true

function _handle_error(exceptions)
    Base.emphasize(stderr, "Failed Task\n")
    return Base.display_error(stderr, exceptions)
end

function handle_errors(body)
    if _debug_mode()
        try
            body()
        catch e
            e == :stop && return
            _handle_error(current_exceptions())
            rethrow()
        end
    else
        body()
    end
end

"""
    struct FinishedChannel{T} <: AbstractChannel{T}

Used to store tasks which have been completed, but not yet removed from the
underlying `DAG`. Taking from an empty `FinishedChannel` will block.
"""
struct FinishedChannel{T} <: AbstractChannel{T}
    data::Vector{T}
    cond_take::Threads.Condition
    function FinishedChannel{T}() where {T}
        lock = Threads.ReentrantLock()
        cond_take = Threads.Condition(lock)
        data = Vector{T}()
        return new(data, cond_take)
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

function Base.put!(c::FinishedChannel{T}, t::T) where {T}
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

Singleton type used to safely interrupt a task reading from an `AbstractChannel`.
"""
struct Stop end

const Stoppable{T} = Union{T,Stop}
