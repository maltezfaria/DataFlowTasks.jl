using Test
using LinearAlgebra
using DataFlowTasks
import DataFlowTasks as DFT

include(joinpath(DFT.PROJECT_ROOT, "test", "testutils.jl"))

tg = DFT.TaskGraph(200)
DFT.set_active_taskgraph!(tg)

@testset "Fork-join" begin
    m = 10
    s = 0.1
    nw = Threads.nthreads()
    t = fetch(fork_join(m, s))
    t1 = @elapsed fetch(fork_join(m, s))
    t2 = (2 + ceil(m / nw)) * s
    # test that ideal vs actual time are close
    @test abs(t1 - t2) < 1e-2
end

@testset "Stop dag worker" begin
    m = 10
    s = 0.1
    nw = Threads.nthreads()
    # stopping the dag_worker will mean finished nodes are no longer cleaned up
    DFT.stop_dag_cleaner()
    fork_join(m, s)
    @test DFT.num_nodes(tg.dag) == m + 3
    # resuming dag_worker will now cleanup nodes
    DFT.start_dag_cleaner()
    wait(tg) # wait for graph to be empty
    @test DFT.num_nodes(tg.dag) == 0
    t1 = @elapsed fetch(fork_join(m, s))
    t2 = (2 + ceil(m / nw)) * s
    # test that ideal vs actual time are close
    @test abs(t1 - t2) < 1e-2
end

@testset "Restart dag worker" begin
    n = 10
    A = ones(n)
    # a first task that errors
    t1 = @dspawn error() (@RW A)
    # a second task that hangs
    t2 = @dspawn identity(@RW A)
    # check that scheduler is in limbo
    tg = DFT.get_active_taskgraph()
    @test DFT.num_nodes(tg.dag) == 2
    # restart scheduler and make sure it runs again
    empty!(tg)
    @test DFT.num_nodes(tg.dag) == 0
    t = @dspawn sum(@R A)
    @test fetch(t) == n
end
