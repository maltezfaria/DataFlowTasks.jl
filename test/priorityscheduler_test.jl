using Test
using DataFlowTasks
using DataFlowTasks: R,W,RW
using LinearAlgebra
using DataFlowTasks.TiledFactorization

background = false
sch = DataFlowTasks.PriorityScheduler(100,background)
DataFlowTasks.setscheduler!(sch)

include(joinpath(DataFlowTasks.PROJECT_ROOT,"test","testutils.jl"))

@testset "Priority scheduler" begin

    @testset "Fork-join" begin
        m = 50
        s = 0.1
        nw = Threads.nthreads() - background # one worker handles the dag
        fetch(fork_join(m,s))
        t1 = @elapsed fetch(fork_join(m,s))
        t2 = (2+ceil(m/nw))*s
        # test that ideal vs actual time are close
        @test abs(t1-t2) < 1e-2
    end

    @testset "Tiled cholesky factorization" begin
        m  = 100
        bsize = div(m,5)
        # create an SPD matrix
        A = rand(m,m)
        A = (A + adjoint(A))/2
        A = A + m*I
        F = TiledFactorization.cholesky(A)
        @test F.L*F.U ≈ A
    end

    @testset "Tiled lu factorization" begin
        m  = 100
        bsize = div(m,5)
        A = rand(m,m)
        F = TiledFactorization.lu(A)
        @test F.L*F.U ≈ A
    end

end
