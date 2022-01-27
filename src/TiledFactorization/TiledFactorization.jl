"""
    module TiledFactorization

Tiled algorithms for factoring dense matrices.
"""
module TiledFactorization

using LinearAlgebra
using LinearAlgebra: BlasInt
using LoopVectorization
using TriangularSolve
using RecursiveFactorization
using Octavian

using DataFlowTasks
using DataFlowTasks: R,W,RW

function schur_complement!(C,A,B,tturbo::Val{T}) where {T}
    # RecursiveFactorization.schur_complement!(C,A,B,tturbo) // usually slower than Octavian
    if T
        Octavian.matmul!(C,A,B,-1,1)
    else
        Octavian.matmul_serial!(C,A,B,-1,1)
    end
end

const TILESIZE = Ref(256)

include("tiledmatrix.jl")
include("cholesky.jl")
include("lu.jl")

export
    PseudoTiledMatrix

end
