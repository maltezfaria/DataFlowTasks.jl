"""
    module TiledFactorization

Tiled algorithms for factoring dense matrices.
"""
module TiledFactorization

using LinearAlgebra
using LoopVectorization
using TriangularSolve
using RecursiveFactorization

using DataFlowTasks
using DataFlowTasks: R,W,RW

const TILESIZE = Ref(256)

include("utils.jl")
include("tiledmatrix.jl")
include("cholesky.jl")
include("lu.jl")

export
    PseudoTiledMatrix

end
