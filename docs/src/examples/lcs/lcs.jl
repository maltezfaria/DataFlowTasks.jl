cd(@__DIR__)             #src
import Pkg               #src
Pkg.activate("../../..") #src

# # Longest Common Subsequence
#
#md # [![ipynb](https://img.shields.io/badge/download-ipynb-blue)](lcs.ipynb)
#md # [![nbviewer](https://img.shields.io/badge/show-nbviewer-blue.svg)](@__NBVIEWER_ROOT_URL__/examples/lcs/lcs.ipynb)
#
# [Longest Common Subsequence](https://en.wikipedia.org/wiki/Longest_common_subsequence)

# ## Small example

function init_lengths!(lengths, x, y)
    lengths[1,1] = 0
    for i in eachindex(x)
        lengths[i+1, 1] = 0
    end
    for j in eachindex(y)
        lengths[1, j+1] = 0
    end
    lengths
end

x = collect("GAC")
y = collect("AGCAT")
lengths = -ones(Int, 1+length(x), 1+length(y))
init_lengths!(lengths, x, y)

#-

using PrettyTables
function display(lengths, x, y)
    table = hcat(['∅', x...], lengths)
    pretty_table(table;
                 header = ["", '∅', y...],
                 formatters = (v, i, j) -> v==-1 ? "" : v)
end
display(lengths, x, y)

#-

function fill_lengths!(lengths, x, y, ir=eachindex(x), jr=eachindex(y))
    for j in jr
        for i in ir
            lengths[i+1, j+1] = if x[i] == y[j]
                lengths[i, j] + 1
            else
                max(lengths[i+1, j], lengths[i, j+1])
            end
        end
    end
end

fill_lengths!(lengths, x, y, 1:1)
display(lengths, x, y)

#-

fill_lengths!(lengths, x, y, 2:2)
display(lengths, x, y)

#-

fill_lengths!(lengths, x, y, 3:3)
display(lengths, x, y)

#-

function backtrack(lengths, x, y)
    i = lastindex(x)
    j = lastindex(y)
    subseq = []
    while lengths[i+1, j+1] != 0
        if x[i] == y[j]
            pushfirst!(subseq, x[i])
            (i, j) = (i-1, j-1)
        elseif lengths[i+1, j] > lengths[i, j+1]
            (i, j) = (i, j-1)
        else
            (i, j) = (i-1, j)
        end
    end
    subseq
end

backtrack(lengths, x, y)

#-

function LCS(x, y)
    lengths = Matrix{Int}(undef, 1+length(x), 1+length(y))
    init_lengths!(lengths, x, y)
    fill_lengths!(lengths, x, y)
    backtrack(lengths, x, y)
end

LCS(x, y)

# ## Large example

# ### Plain sequential version

x = rand("ATCG", 4096);
y = rand("ATCG", 8192);
seq = LCS(x, y)

# ### Tiled sequential version

function splitrange(range, nchunks)
    q, r = divrem(length(range), nchunks)
    chunks = UnitRange{Int}[]

    i₁ = first(range)
    for k in 1:nchunks
        n = k <= r ? q+1 : q
        i₂ = i₁ + n
        push!(chunks, i₁:i₂-1)
        i₁ = i₂
    end
    chunks
end

function LCS_tiled(x, y, nx, ny)
    lengths = Matrix{Int}(undef, 1+length(x), 1+length(y))
    init_lengths!(lengths, x, y)

    for irange in splitrange(eachindex(x), nx)
        for jrange in splitrange(eachindex(y), ny)
            fill_lengths!(lengths, x, y, irange, jrange)
        end
    end

    backtrack(lengths, x, y)
end

nx = 8
ny = 12
tiled = LCS_tiled(x, y, nx, ny)
@assert seq == tiled

# ### Tiled parallel version

using DataFlowTasks

function LCS_par(x, y, nx, ny)
    lengths = Matrix{Int}(undef, 1+length(x), 1+length(y))
    init_lengths!(lengths, x, y)

    for irange in splitrange(eachindex(x), nx)
        for jrange in splitrange(eachindex(y), ny)
            DataFlowTasks.@spawn begin
                @R view(lengths, irange, jrange)
                @W view(lengths, irange .+ 1, jrange .+ 1)
                fill_lengths!(lengths, x, y, irange, jrange)
            end
        end
    end

    barrier = DataFlowTasks.@spawn @R(lengths)
    wait(barrier)

    backtrack(lengths, x, y)
end

par = LCS_par(x, y, nx, ny)
@assert seq == par

# ### Performance comparison

GC.gc(); t_seq   = @elapsed LCS(x, y)
GC.gc(); t_tiled = @elapsed LCS_tiled(x, y, nx, ny)
GC.gc(); t_par   = @elapsed LCS_par(x, y, nx, ny)

using CairoMakie
barplot(1:3, [t_seq, t_tiled, t_par],
        axis = (; title = "Run times [s]",
                xticks = (1:3, ["sequential", "tiled", "parallel"])))

# ### Profiling of the parallel version

resize!(DataFlowTasks.get_active_taskgraph(), 200)
log_info = DataFlowTasks.@log LCS_par(x, y, nx, ny)

#-

DataFlowTasks.stack_weakdeps_env!()
using GraphViz
GraphViz.Graph(log_info)

#-

plot(log_info)
