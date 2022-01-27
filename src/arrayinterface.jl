#=
This file defines `memory_overlap` for some commonly used (native) arrays. It
covers some interseting use cases, and show how to implement the interface.
=#

using LinearAlgebra

"""
    memory_overlap(di::Array,dj::Array)
    memory_overlap(di::SubArray,dj::Array)
    memory_overlap(di::Array,dj::SubArray)

When both `di` and `dj` are of type `Array`, compare their addresses. If one is
of type `SubArray`, compare the parent.
"""
memory_overlap(di::Array,dj::Array) = pointer(di)===pointer(dj)
memory_overlap(di::SubArray,dj::Array) = memory_overlap(di.parent,dj)
memory_overlap(di::Array,dj::SubArray) = memory_overlap(dj.parent,di)

memory_overlap(di::SubArray,dj::LinearAlgebra.AbstractTriangular) = memory_overlap(parent(dj),di)
memory_overlap(di::LinearAlgebra.AbstractTriangular,dj::SubArray) = memory_overlap(dj,di)

"""
    memory_overlap(di::SubArray,dj::SubArray)

First compare their parents. If they are the same, compare the indices in the
case where the `SubArray`s have the  same dimension.
"""
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
    length(idx1) == length(idx2) || error()
    N = length(idx1)
    inter = ntuple(i->idxintersect(idx1[i],idx2[i]),N)
    all(inter)
    # for d in 1:length(idx1)
    #     isempty(intersect(idx1[d],idx2[d])) && (return false)
    # end
    # if you are here it is because all axis intersect
    # return true
end

idxintersect(a,b) = !isempty(intersect(a,b))
idxintersect(a::Number,b::Number) = a == b
