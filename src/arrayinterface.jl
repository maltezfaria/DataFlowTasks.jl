#=
This file defines `memory_overlap` for some commonly used (native) arrays. It
covers some interseting use cases, and shows how to implement the interface.
=#

using LinearAlgebra

"""
    memory_overlap(di::AbstractArray,dj::AbstractArray)

Try to determine if the arrays `di` and `dj` have overlapping memory.

When both `di` and `dj` are `Array`s of bitstype, simply compare their
addresses. Otherwise, compare their `parent`s by default.

When both `di` and `dj` are `SubArray`s we compare the actual indices of the
`SubArray`s when their parents are the same (to avoid too many false positives).
"""
function memory_overlap(di::Array,dj::Array)
    if isbitstype(eltype(di)) && isbitstype(eltype(dj))
        return pointer(di)===pointer(dj)
    else
        warn("memory of Arrays of non-bitstype elements are assumed to overlap by default")
        return true
    end
end
memory_overlap(A::AbstractArray,B::AbstractArray) = memory_overlap(parent(A),parent(B))

function memory_overlap(di::SubArray,dj::SubArray)
    if pointer(di.parent) !== pointer(dj.parent)
        return false
    else
        _memory_overlap(di,dj)
    end
end

# for subarrays, check their indices. For now assume that the indices have the
# same length since this simplifies the logic
function _memory_overlap(di::SubArray,dj::SubArray)
    idx1 = di.indices
    idx2 = dj.indices
    msg = """
        subarrays of different dimensions being compared, assuming by
        default their memory overlaps.
    """
    length(idx1) == length(idx2) || (warn(msg); return true)
    N = length(idx1)
    inter = ntuple(i->idxintersect(idx1[i],idx2[i]),N)
    all(inter)
end

idxintersect(a,b) = !isempty(intersect(a,b))
idxintersect(a::Number,b::Number) = a == b
