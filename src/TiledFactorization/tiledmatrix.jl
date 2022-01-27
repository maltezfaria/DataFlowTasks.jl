"""
    PseudoTiledMatrix(data::Matrix,sz::Int)

Wrap a `Matrix` in a tiled structure of size `sz`, where `getindex(A,i,j)`
returns a view of the `(i,j)` block (of size `(sz × sz)`). No copy of `data` is
made, but the elements in a block are not continguos in memory. If `sz` is not a
divisor of the matrix size, one last row/column block will be included of size
given by the remainder fo the division.
"""
struct PseudoTiledMatrix{T}
    data::Matrix{T}
    # rows/columns of block i are given by partition[i]:partition[i+1]-1
    partition::Vector{Int}
    function PseudoTiledMatrix(data::Matrix,s::Int)
        T = eltype(data)
        m,n = size(data)
        p = 1:s:m |> collect
        push!(p,m+1)
        new{T}(data,p)
    end
end

function Base.size(A::PseudoTiledMatrix)
    length(A.partition)-1,length(A.partition)-1
end

function Base.getindex(A::PseudoTiledMatrix,i::Int,j::Int)
    @assert 1 ≤ i ≤ size(A)[1]
    @assert 1 ≤ j ≤ size(A)[2]
    p = A.partition
    I = p[i]:(p[i+1]-1)
    J = p[j]:(p[j+1]-1)
    view(A.data,I,J)
end
