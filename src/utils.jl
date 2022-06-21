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
    enable_debug(mode = true)

If `mode` is true (the default), enable debug mode: errors inside tasks will be
shown.
"""
function enable_debug(mode = true)
    @eval _debug_mode() = $mode
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
