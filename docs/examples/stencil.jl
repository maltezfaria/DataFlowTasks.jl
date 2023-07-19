# Difference-Finie-like code

using DataFlowTasks
using TiledFactorization
using LinearAlgebra
using GLMakie, GraphViz

import TiledFactorization as TF
import DataFlowTasks as DFT

# Initial Conditions
function initialization!(Un, n)
    chocsize = round(Int, n/2 - n/4)
    idxcenter = round(Int, n/2)
    for i ∈ 1:n, j ∈ 1:n
        i_inchoc = idxcenter-chocsize ≤ i ≤ idxcenter+chocsize
        j_inchoc = idxcenter-chocsize ≤ j ≤ idxcenter+chocsize

        i_inchoc && j_inchoc && (Un[i,j] = 1)
    end
end

# Update the element i,j of the matrix Un1 depending on the matrix U
function stepelement!(Un1, Un, n, i, j)
    # Boundary Conditions
    if i==1 || j==1 || i==n || j==n
        Un1[i,j] = 0
        return
    end

    # Inside points
    Un1[i,j] = 1/4 * (Un[i-1,j] + Un[i+1,j] + Un[i,j-1] + Un[i,j+1])
end

# Update the tile at idx (ti,tj) of Un1, from Un data
function steptile!(Un1, Un, fi, fj, ts, n)
    for i ∈ fi:fi+ts-1, j ∈ fj:fj+ts-1
        stepelement!(Un1, Un, n, i, j)
    end
end

function step!(Un1, Un, n, tn, ts)
    for ti ∈ 1:tn, tj ∈ 1:tn
        (i,j) = (ti-1)*ts+1, (tj-1)*ts+1
        @spawn steptile!(Un1, @R(Un), i, j, ts, n) label="tile ($ti,$tj)"
    end
    DFT.sync()
end

macro swap!(A::Symbol, B::Symbol)
    blk = quote
        C = $(esc(A))
        $(esc(A)) = $(esc(B))
        $(esc(B)) = C
    end
    return blk
end
# Function wrapper
swap!(A,B) = (@swap! A B)

function main()
    # Declaration
    n = 2048
    niter = 20
    ts = 1024
    tn = round(Int, n/ts)
    Un = zeros(n,n)
    Un1 = zeros(n,n)

    # DFT environnement
    DFT.enable_log()
    DFT.resetlogger!()

    # Initialization
    initialization!(Un, n)

    # Parameters test
    n % ts != 0 && error("Tile size $ts not fitting matrix of size $n")

    # Core
    for _ ∈ 1:niter
        step!(Un1, Un, n, tn, ts)
        @spawn swap!(Un1,Un) label="swap"
    end
end
main()

f = DFT.plot_traces(categories=["tile", "swap"])
