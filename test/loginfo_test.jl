using Test
using DataFlowTasks
using LinearAlgebra

DataFlowTasks.@using_opt GraphViz, CairoMakie

# Check that extensions were loaded correctly
MakieExt = Base.get_extension(DataFlowTasks, :DataFlowTasks_Makie_Ext)
@test MakieExt isa Module

GraphVizExt = Base.get_extension(DataFlowTasks, :DataFlowTasks_GraphViz_Ext)
@test GraphVizExt isa Module

# NOTE: the functions below call sleep to make sure the computation does not finish
# before full dag is created. Otherwise the critical path may be "incomplete"
# and the tests on `longest_path` will fail
computing(A) = (sleep(0.01); A*A)
computing(A, B) = (sleep(0.01); A*B)
function work(A, B)
    @dspawn computing(@RW(A)) label="A²"
    @dspawn computing(@RW(A)) label="A²"
    @dspawn computing(@RW(A)) label="A²"
    @dspawn computing(@RW(B)) label="B²"
    @dspawn computing(@RW(A), @RW(B)) label="A*B"
    DataFlowTasks.sync()
end

A = ones(20, 20)
B = ones(20, 20)

# reset counter. Needed because the tests below assume tags started with 1
DataFlowTasks.TASKCOUNTER[] = 0

logger = DataFlowTasks.@log work(A, B)

@test length(logger.tasklogs) == Threads.nthreads()
nbtasks = DataFlowTasks.nbtasknodes(logger)
nbinsertion = sum(length(insertionlog) for insertionlog ∈ logger.insertionlogs)
@test nbtasks == 5
@test nbinsertion == 5

# Critical Path
path = DataFlowTasks.longest_path(logger)
@test path == [5, 3, 2, 1]

# DOT Format File
dotstr = GraphVizExt.loggertodot(logger)
@test occursin("strict digraph dag", dotstr)
@test occursin("1 -> 2", dotstr)
@test occursin("2 -> 3", dotstr)
@test occursin("3 -> 5", dotstr)
@test occursin("4 -> 5", dotstr)

# Visualization call
plt = plot(logger, categories=["A²", "B²", "A*B"])
graph = GraphViz.Graph(logger)

# do not the counter and make sure things still work
logger = DataFlowTasks.@log work(A, B)
@test length(logger.tasklogs) == Threads.nthreads()
nbtasks = DataFlowTasks.nbtasknodes(logger)
nbinsertion = sum(length(insertionlog) for insertionlog ∈ logger.insertionlogs)
@test nbtasks == 5
@test nbinsertion == 5

# Critical Path
path = DataFlowTasks.longest_path(logger)
@test path == [5, 3, 2, 1] .+ nbtasks
