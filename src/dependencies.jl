# memory_overlap(di,dj) = memory_overlap(dj,di)

memory_overlap(di::Array,dj::Array) = di===dj
memory_overlap(di::Number,dj::Any) = false
memory_overlap(di::Any,dj::Number) = false
memory_overlap(di::Number,dj::Number) = false

memory_overlap(di::SubArray,dj::Array) = di.parent === dj
memory_overlap(di::Array,dj::SubArray) = dj.parent === di

function memory_overlap(di::SubArray,dj::SubArray)
    di.parent === dj.parent || (return false)
    for (idx_di, idx_dj) in zip(di.indices,dj.indices)
        intersect(idx_di,idx_dj) |> isempty || (return false)
    end
    return true
end
