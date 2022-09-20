# FIXME: should we be able to iterate over an ordered dictionary in reverse
# order? For some reason that does not work (it does not work either for a
# regular `Dict`), so the lines below commit type piracy to make `OrderedDict`
# be "reverse iterable".
function Base.iterate(rt::Iterators.Reverse{<:OrderedDict})
    t = rt.itr
    t.ndel > 0 && DataStructures.OrderedCollections.rehash!(t)
    n = length(t.keys)
    n < 1 && return nothing
    return (Pair(t.keys[n], t.vals[n]), n-1)
end
function Base.iterate(rt::Iterators.Reverse{<:OrderedDict}, i)
    t = rt.itr
    i < 1 && return nothing
    return (Pair(t.keys[i], t.vals[i]), i-1)
end

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
    mode
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
    Base.display_error(stderr, exceptions)
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
