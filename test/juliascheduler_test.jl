using Test
using DataFlowTasks
using DataFlowTasks: R,W,RW
using LinearAlgebra
using DataFlowTasks.TiledFactorization

include(joinpath(DataFlowTasks.PROJECT_ROOT,"test","testutils.jl"))

sch = DataFlowTasks.JuliaScheduler(200)
DataFlowTasks.setscheduler!(sch)

@testset "Julia scheduler" begin
    @testset "Fork-join" begin
        m = 50
        s = 0.1
        nw = Threads.nthreads()
        t = fetch(fork_join(m,s))
        t1 = @elapsed fetch(fork_join(m,s))
        t2 = (2+ceil(m/nw))*s
        # test that ideal vs actual time are close
        @test abs(t1-t2) < 1e-2
    end

    @testset "Stop dag worker" begin
        m = 50
        s = 0.1
        nw = Threads.nthreads()
        # stopping the dag_worker will mean finished nodes are no longer cleaned up
        DataFlowTasks.stop_dag_worker()
        fork_join(m,s)
        @test DataFlowTasks.num_nodes(sch.dag) == 52
        # resuming dag_worker will now cleanup nodes
        DataFlowTasks.start_dag_worker()
        DataFlowTasks.sync() # wait for dag to be empty
        @test DataFlowTasks.num_nodes(sch.dag) == 0
        t1 = @elapsed fetch(fork_join(m,s))
        t2 = (2+ceil(m/nw))*s
        # test that ideal vs actual time are close
        @test abs(t1-t2) < 1e-2
    end

    @testset "Tiled cholesky factorization" begin
        m  = 1000
        bsize = div(m,5)
        # create an SPD matrix
        A = rand(m,m)
        A = (A + adjoint(A))/2
        A = A + m*I
        F = TiledFactorization.cholesky(A)
        @test F.L*F.U ≈ A
    end

    @testset "Tiled lu factorization" begin
        m  = 1000
        bsize = div(m,5)
        A = rand(m,m)
        F = TiledFactorization.lu(A)
        @test F.L*F.U ≈ A
    end
end
