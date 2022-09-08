# FIXME: make PR to OrderedCollections to allow for reverse iterators
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

If `mode=true`, information regarding the [`DataFlowTask`](@ref)s will be logged
in the current logger.

## See also: [`getlogger`](@ref), [`setlogger!`](@ref), [`TaskLog`](@ref).
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


"""
    enable_graphics([backend])

Load scripts required to visualize the results of the [`Logger`](@ref).

Calling this function will possibly download and pre-compile a `Makie`
backend and/or `GraphViz`, so if these are not yet available on your system calling
`enable_graphics` for the first time may take a while.

Available backends are: `CairoMakie` and `GLMakie`.
"""
function enable_graphics(;backend=:GLMakie)
    supported = (:GLMakie, :CairoMakie)
    backend in supported || error("supported backends: $supported")
    @eval Main (DataFlowTasks.@using_opt GraphViz, $backend)
end

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
