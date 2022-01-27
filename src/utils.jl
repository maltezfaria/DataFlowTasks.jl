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
