using Test
using DataFlowTasks
using DataFlowTasks: R,W,RW, execute_dag
using LinearAlgebra

sch = DataFlowTasks.StaticScheduler()
DataFlowTasks.setscheduler!(sch)

include(joinpath(DataFlowTasks.PROJECT_ROOT,"test","testutils.jl"))

@testset "Static scheduler" begin
    @testset "Fork-join" begin
        m = 50
        s = 0.1
        nw = Threads.nthreads()
        # create the dag
        t = fork_join(m,s)
        execute_dag(sch)
        fork_join(m,s)
        t1 = @elapsed execute_dag(sch)
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
        t = tiled_cholesky(A,bsize)
        execute_dag(sch)
        F = fetch(t)
        @test F.L*F.U ≈ A
    end

    @testset "Tiled lu factorization" begin
        m  = 1000
        bsize = div(m,5)
        A = rand(m,m)
        t = tiled_lu(A,bsize)
        execute_dag(sch)
        F = fetch(t)
        @test F.L*F.U ≈ A
    end
end
