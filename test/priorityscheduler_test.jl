using Test
using DataFlowTasks
using DataFlowTasks: R, W, RW
using LinearAlgebra

background = false
sch = DataFlowTasks.PriorityScheduler(100, background)
DataFlowTasks.setscheduler!(sch)

include(joinpath(DataFlowTasks.PROJECT_ROOT, "test", "testutils.jl"))

@testset "Priority scheduler" begin
    @testset "Fork-join" begin
        m = 50
        s = 0.1
        nw = Threads.nthreads() - background # one worker handles the dag
        fetch(fork_join(m, s))
        t1 = @elapsed fetch(fork_join(m, s))
        t2 = (2 + ceil(m / nw)) * s
        # test that ideal vs actual time are close
        @test abs(t1 - t2) < 1e-2
    end
end
