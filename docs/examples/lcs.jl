# Longest Common subsequence algorithm

using DataFlowTasks
import DataFlowTasks as DFT
using TiledFactorization: PseudoTiledMatrix
using GLMakie, GraphViz
using Random
using BenchmarkTools

# F[i,j] contains the LCS between the first i elements of X
# and the first j elements of y.
# ti : tile index on the vertical axis
# tj : tile index on the horizontal axis
# ts : tilesize
function tiledLCS!(F, x, y, ti, tj, ts)
    # First and Last indices
    fi = (ti-1)*ts+2  ;  li = fi+(ts-1)
    fj = (tj-1)*ts+2  ;  lj = fj+(ts-1)

    # For every element of that tile
    for i ∈ fi:li, j ∈ fj:lj
        F[i,j] = x[i-1]==y[j-1] ? F[i-1,j-1]+1 : max(F[i,j-1], F[i-1,j])
    end
end

# Returns the view of the tile (ti,tj) of F
function gettile(F, ti, tj, ts)
    # First and Last indices
    fi = (ti-1)*ts+2  ;  li = fi+(ts-1)
    fj = (tj-1)*ts+2  ;  lj = fj+(ts-1)

    view(F, fi:li, fj:lj)
end

# Longest common subsequence of x and y (parallel)
# WITH PseudoTiledMatrix
function parallelLCS_PTM(x, y, tilesize)
    @assert length(x) == length(y)

    # Parameters
    n = length(x)
    ntiles = round(Int, n/tilesize)
    
    # F[i,j] contains the LCS between the first i elements of X
    # and the first j elements of y.
    # Contains an extra line + column of zeros for commodity in boundary conditions
    F = zeros(n+1,n+1)
    # Tiled view of that matrix
    Ft = PseudoTiledMatrix(F[2:end, 2:end], tilesize)


    # First diagonal block
    @dspawn begin
        @RW Ft[1,1]
        tiledLCS!(F, x, y, 1, 1, tilesize)
    end label="1 ; 1"

    # First horizontal line
    # tj : tile index on the horizontal axis
    for tj ∈ 2:ntiles
        @dspawn begin
            @RW Ft[1,tj]
            @R  Ft[1,tj-1]
            tiledLCS!(F, x, y, 1, tj, tilesize)
        end label="1 ; ≥2" 
    end

    # First Vertical Column
    # ti : tile index on the vertical axis
    for ti ∈ 2:ntiles
        @dspawn begin
            @RW Ft[ti,1]
            @R  Ft[ti-1,1]
            tiledLCS!(F, x, y, ti, 1, tilesize)
        end label="≥2 ; 1" 
    end

    # Others
    # ti : tile index on the vertical axis
    # tj : tile index on the horizontal axis
    for ti ∈ 2:ntiles, tj ∈ 2:ntiles
        @dspawn begin
            @RW Ft[ti,tj]
            @R  Ft[ti-1,tj] Ft[ti,tj-1] Ft[ti-1, tj-1]            
            tiledLCS!(F, x, y, ti, tj, tilesize)
        end label="≥2 ; ≥2" 
    end

    DFT.sync()
end


# Longest common subsequence of x and y 
# ts : tilesize
# WITHOUT PseudoTiledMatrix
function parallelLCS(x, y, ts)
    @assert length(x) == length(y)

    n = length(x)
    F = zeros(n+1,n+1)
    last_tile_idx = round(Int, n/ts)

    # First diagonal block
    @dspawn begin
        @RW gettile(F, 1, 1, ts)
        tiledLCS!(F, x, y, 1, 1, ts)
    end label="1 ; 1"

    # First horizontal line
    for blockj ∈ 2:last_tile_idx
        @dspawn begin
            @RW gettile(F, 1, blockj, ts)
            @R gettile(F, 1, blockj-1, ts)
            tiledLCS!(F, x, y, 1, blockj, ts)
        end label="1 ; ≥2" 
    end

    # First Vertical Column
    for blocki ∈ 2:last_tile_idx
        @dspawn begin
            @RW gettile(F, blocki, 1, ts)
            @R gettile(F, blocki-1, 1, ts)
            tiledLCS!(F, x, y, blocki, 1, ts)
        end label="≥2 ; 1" 
    end

    # Others
    for blocki ∈ 2:last_tile_idx, blockj ∈ 2:last_tile_idx
        @dspawn begin
            @RW gettile(F, blocki, blockj, ts)
            @R gettile(F, blocki-1, blockj-1, ts)
            @R gettile(F, blocki-1, blockj, ts)
            @R gettile(F, blocki, blockj-1, ts)
            tiledLCS!(F, x, y, blocki, blockj, ts)
        end label="≥2 ; ≥2" 
    end

    DFT.sync()
end

# Longest common subsequence of x and y (serial)
function serialLCS(x, y)
    @assert length(x) == length(y)

    n = length(x)
    F = zeros(n+1,n+1)

    tiledLCS!(F, x, y, 1, 1, n)
end

# Context
n = 5000
x, y = [randstring(n) for _ in 1:2]
# @show x
# @show y
blocks = 250


# Enabling logging
DFT.enable_log()

# Precompilation
parallelLCS(x, y, blocks)

# Reset
DFT.resetlogger!()
GC.gc()

# Real work
parallelLCS(x, y, blocks)

# Plot
f = DFT.plot(categories=["1 ; 1", "1 ; ≥2", "≥2 ; 1", "≥2 ; ≥2"])

# DFT.resetlogger!()
# bs = @benchmark serialLCS(x, y) samples=1
# bp = @benchmark parallelLCS(x, y, blocks) samples=1

# display(bs)
# display(bp)

# g = DFT.dagplot()
# GraphViz.layout!(g)
# DFT.savedag("dag.svg", g)

