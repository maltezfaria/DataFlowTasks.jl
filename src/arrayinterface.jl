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

#case where both subarrays have the same dimension
function _memory_overlap(di::SubArray{_,N},dj::SubArray{__,N}) where {_,__,N}
    for dim in 1:N
        idx1 = di.indices[dim]
        idx2 = dj.indices[dim]
        isempty(intersect(idx1,idx2)) && (return false)
    end
    return true
end
