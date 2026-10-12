using Test
using LinearAlgebra
using DataFlowTasks
using Suppressor
import DataFlowTasks as DFT

# NOTE: the sleep makes the weights of the critical path predictable. The tasks
# may finish before the tasks depending on them are inserted: the logged
# dependencies are complete nonetheless.
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

# tags are unique across all the task graphs: number them from the first one
first_tag(logger) = minimum(DFT.tag, logger.tasklogs) - 1

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
t₀ = first_tag(logger)
path = DFT.longest_path(logger)
@test path == [5, 3, 2, 1] .+ t₀

using GraphViz, Makie

@testset "DataFlowTasks_GraphVizExt" begin
    # Check that the extension has been loaded correctly
    GraphVizExt = Base.get_extension(DFT, :DataFlowTasks_GraphViz_Ext)
    @test GraphVizExt isa Module

    # DOT Format File
    dotstr = DataFlowTasks.loggertodot(logger)
    @test occursin("strict digraph dag", dotstr)
    @test occursin("$(t₀ + 1) -> $(t₀ + 2)", dotstr)
    @test occursin("$(t₀ + 2) -> $(t₀ + 3)", dotstr)
    @test occursin("$(t₀ + 3) -> $(t₀ + 5)", dotstr)
    @test occursin("$(t₀ + 4) -> $(t₀ + 5)", dotstr)

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

# log again, and make sure things still work
logger = DFT.@log work(A, B)
nbtasks = DFT.nbtasknodes(logger)
nbinsertion = length(logger.insertionlogs)
@test nbtasks == 5
@test nbinsertion == 5

# Critical Path
path = DFT.longest_path(logger)
@test path == [5, 3, 2, 1] .+ first_tag(logger)

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


@testset "Complete dependencies" begin
    deps(logger, t) = sort(DFT.dependencies(logger)[t])
    x, y = zeros(1), zeros(1)

    # a task finished and removed from the dag before a task depending on it is
    # inserted: the scheduler sees no dependency, but the logged graph has it
    logger = DFT.@log begin
        a = @dspawn (@W(x); sleep(0.05))
        wait(a)
        wait(DFT.get_active_taskgraph()) # `a` is removed from the dag
        @dspawn (@R(x); sleep(0.05))
    end
    ta, tb = sort(logger.tasklogs)
    @test isempty(tb.inneighbors)
    @test deps(logger, DFT.tag(tb)) == [DFT.tag(ta)]
    @test DFT.longest_path(logger) == [DFT.tag(tb), DFT.tag(ta)]
    # the data accesses are released once analysed
    @test isempty(logger.accesses)

    # when no task is removed, the logged graph is the one of the scheduler
    DFT.stop_dag_cleaner()
    logger = try
        DFT.@log for i in 1:20
            z = isodd(i) ? x : y
            @dspawn (@RW(z); @R(x); nothing)
        end
    finally
        DFT.start_dag_cleaner()
    end
    @test all(logger.tasklogs) do t
        return deps(logger, DFT.tag(t)) == sort(t.inneighbors)
    end

    # linear dag: each task depends on the previous one
    DFT.force_linear_dag(true)
    logger = try
        DFT.@log for z in (x, y, x)
            @dspawn @R(z)
        end
    finally
        DFT.force_linear_dag(false)
    end
    t1, t2, t3 = DFT.tag.(sort(logger.tasklogs))
    @test (deps(logger, t2), deps(logger, t3)) == ([t1], [t2])

    # tasks of different task graphs do not depend on each other
    tg = DFT.TaskGraph()
    logger = DFT.@log begin
        @dspawn @W(x)
        DFT.with_taskgraph(() -> @dspawn(@W(x)), tg)
    end
    @test allunique(DFT.tag.(logger.tasklogs))
    @test all(isempty, values(DFT.dependencies(logger)))
    DFT.stop_dag_cleaner(tg)
end
