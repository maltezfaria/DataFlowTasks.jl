using Test
using LinearAlgebra
using DataFlowTasks
import DataFlowTasks as DFT

# NOTE: the functions below call sleep to make sure the computation does not finish
# before full dag is created. Otherwise the critical path may be "incomplete"
# and the tests on `longest_path` will fail
computing(A) = (sleep(0.01); A * A)
computing(A, B) = (sleep(0.01); A * B)
function work(A, B)
    @dspawn computing(@RW(A)) label = "A²"
    @dspawn computing(@RW(A)) label = "A²"
    @dspawn computing(@RW(A)) label = "A²"
    @dspawn computing(@RW(B)) label = "B²"
    res = @dspawn computing(@RW(A), @RW(B)) label = "A*B"
    return fetch(res)
end

A = ones(20, 20)
B = ones(20, 20)

# Run the code below using a new taskgraphg
tg = DFT.TaskGraph()
DFT.set_active_taskgraph!(tg)

logger = DFT.@log work(A, B)

nbtasks = DFT.nbtasknodes(logger)
nbinsertion = length(logger.insertionlogs)
@test nbtasks == 5
@test nbinsertion == 5

# Critical Path
path = DFT.longest_path(logger)
@test path == [5, 3, 2, 1]

using GraphViz, CairoMakie

@testset "DataFlowTasks_GraphVizExt" begin
    # Check that the extension has been loaded correctly
    GraphVizExt = Base.get_extension(DFT, :DataFlowTasks_GraphViz_Ext)
    @test GraphVizExt isa Module

    # DOT Format File
    dotstr = DataFlowTasks.loggertodot(logger)
    @test occursin("strict digraph dag", dotstr)
    @test occursin("1 -> 2", dotstr)
    @test occursin("2 -> 3", dotstr)
    @test occursin("3 -> 5", dotstr)
    @test occursin("4 -> 5", dotstr)

    # GraphViz.Graph creation
    graph = GraphViz.Graph(logger)
    @test graph isa GraphViz.Graph
end

@testset "DataFlowTasks_Makie_Ext" begin
    # Check that the extension has been loaded correctly
    MakieExt = Base.get_extension(DFT, :DataFlowTasks_Makie_Ext)
    @test MakieExt isa Module

    # Trace visualization
    plt = plot(logger; categories = ["A²", "B²", "A*B"])
    @test plt isa Makie.Figure
end

# do not reset the counter and make sure things still work
logger = DFT.@log work(A, B)
nbtasks = DFT.nbtasknodes(logger)
nbinsertion = length(logger.insertionlogs)
@test nbtasks == 5
@test nbinsertion == 5

# Critical Path
path = DFT.longest_path(logger)
@test path == [5, 3, 2, 1] .+ nbtasks

@testset "Concurrent logging" begin
    # many independent tasks finishing concurrently on different threads
    n = 500
    xs = [zeros(Int, 1) for _ in 1:n]
    logger = DFT.@log begin
        for x in xs
            @dspawn (@W(x); x[1] = Threads.threadid())
        end
        wait(DFT.get_active_taskgraph())
    end
    @test DFT.nbtasknodes(logger) == n
    @test length(logger.insertionlogs) == n
    @test allunique(DFT.tag.(logger.tasklogs))
    @test Set(t.tid for t in logger.tasklogs) == Set(x[1] for x in xs)
end
