using Test
using LinearAlgebra
using DataFlowTasks
using Suppressor
import DataFlowTasks as DFT

# NOTE: the dag cleaner is stopped while the tasks are spawned, so that finished
# tasks stay in the dag until the full dag is created. Otherwise a task could be
# removed before the tasks depending on it are inserted, and the critical path
# would be "incomplete". The sleep makes the weights of the critical path
# predictable.
computing(A) = (sleep(0.01); A * A)
computing(A, B) = (sleep(0.01); A * B)
function work(A, B)
    DFT.stop_dag_cleaner()
    res = try
        @dspawn computing(@RW(A)) label = "A²"
        @dspawn computing(@RW(A)) label = "A²"
        @dspawn computing(@RW(A)) label = "A²"
        @dspawn computing(@RW(B)) label = "B²"
        @dspawn computing(@RW(A), @RW(B)) label = "A*B"
    finally
        DFT.start_dag_cleaner()
    end
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

using GraphViz, Makie

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

@testset "Accounting of real runs" begin
    busy(t) = (t₀ = time(); while time() - t₀ < t end)
    xs = [zeros(1) for _ in 1:4]
    function check_invariants(sm)
        ε = 1.0e-3 # clock resolution
        @test sm.running <= DFT.capacity(sm) + ε
        @test DFT.idle(sm) >= -ε
        @test sm.critical_path <= sm.elapsed + ε
        @test DFT.nowait(sm) <= sm.elapsed + ε
    end
    check_invariants(DFT.summarize(DFT.@log work(A, B)))

    # tasks which only sleep do not run (and `@log` waits for them, although
    # they are not fetched)
    log = DFT.@log for x in xs
        @dspawn (@W(x); sleep(0.1))
    end
    sm = DFT.summarize(log)
    @test sm.ntasks == length(xs)
    @test sm.running < 0.05
    @test sm.blocked > 0.3 # 4 × 0.1 s
    check_invariants(sm)

    # tasks which compute run all the time
    log = DFT.@log for x in xs
        @dspawn (@W(x); busy(0.05))
    end
    sm = DFT.summarize(log)
    @test sm.running > 0.9 * 4 * 0.05
    @test sm.blocked < 0.02
    check_invariants(sm)

    # the logging window includes the work of the program itself
    log = DFT.@log begin
        busy(0.2)
        fetch(@dspawn identity(@R(xs[1])))
    end
    @test DFT.summarize(log).elapsed >= 0.2

    # failed tasks are logged, and waited for without rethrowing their error
    log = @suppress_err DFT.@log @dspawn error("task failure")
    @test DFT.summarize(log).nfailed == 1

    # the logger and the task metrics are restored when the logged code throws
    @test_throws ErrorException DFT.@log error("logged code failure")
    @test isnothing(DFT._getloginfo())
    t = Threads.@spawn nothing
    wait(t)
    @test isnothing(Base.Experimental.task_running_time_ns(t))
end
