using Test
using DataFlowTasks
using DataFlowTasks: R,W,RW
using LinearAlgebra

include(joinpath(DataFlowTasks.PROJECT_ROOT,"test","testutils.jl"))

sch = DataFlowTasks.JuliaScheduler(200)
DataFlowTasks.setscheduler!(sch)

@testset "Julia scheduler" begin
    @testset "Fork-join" begin
        m = 10
        s = 0.1
        nw = Threads.nthreads()
        t = fetch(fork_join(m,s))
        t1 = @elapsed fetch(fork_join(m,s))
        t2 = (2+ceil(m/nw))*s
        # test that ideal vs actual time are close
        @test abs(t1-t2) < 1e-2
    end

    @testset "Stop dag worker" begin
        m = 10
        s = 0.1
        nw = Threads.nthreads()
        # stopping the dag_worker will mean finished nodes are no longer cleaned up
        DataFlowTasks.stop_dag_worker()
        fork_join(m,s)
        @test DataFlowTasks.num_nodes(sch.dag) == m+3
        # resuming dag_worker will now cleanup nodes
        DataFlowTasks.start_dag_worker()
        DataFlowTasks.sync() # wait for dag to be empty
        @test DataFlowTasks.num_nodes(sch.dag) == 0
        t1 = @elapsed fetch(fork_join(m,s))
        t2 = (2+ceil(m/nw))*s
        # test that ideal vs actual time are close
        @test abs(t1-t2) < 1e-2
    end

    @testset "Restart dag worker" begin
        n = 10
        A = ones(n)
        # a first task that errors
        t1 = @dspawn error() (@RW A)
        # a second task that hangs
        t2 = @dspawn identity(@RW A)
        # check that scheduler is in limbo
        sch = DataFlowTasks.getscheduler()
        @test DataFlowTasks.num_nodes(sch.dag) == 2
        # restart scheduler and make sure it runs again
        DataFlowTasks.restart_scheduler!()
        @test DataFlowTasks.num_nodes(sch.dag) == 0
        t = @dspawn sum(@R A)
        @test fetch(t) == n
    end
end
