using Test
using LinearAlgebra
using DataFlowScheduler

@testset "Codelets" begin
    R,W,RW  = DataFlowScheduler.READ, DataFlowScheduler.WRITE, DataFlowScheduler.READWRITE

    @testset "Codelet" begin
        m,n  = 100,100
        A    = rand(n,m)
        b    = 2
        codelet = Codelet(func=LinearAlgebra.rmul!,data=(A,b),access_mode=(RW,R))
        tmp  = A*b
        @test A !== tmp
        execute(codelet)
        @test A == tmp
    end

    @testset "Data dependency" begin
        using DataFlowScheduler: dependency_type
        m,n  = 100,100
        A    = rand(n,m)
        a    = -π
        b    = 2
        codelet1 = Codelet(func=rmul!,data=(A,b),access_mode=(RW,R))
        codelet2 = Codelet(func=rmul!,data=(A,a),access_mode=(RW,R))
        @test dependency_type(codelet1,codelet2) == DataFlowScheduler.InferredSequential
        codelet3 = Codelet(func=rmul!,data=(rand(m,n),a),access_mode=(RW,R))
        @test dependency_type(codelet1,codelet3) == DataFlowScheduler.InferredIndependent
    end
    @testset "Task" begin
        task1     = Task(()->1+1)
        codelet1 = Codelet(func=+,data=(1,1),access_mode=(R,R))
        task2     = Task(codelet1,[task1])
        schedule(task2)
        sleep(1e-5)# need to wait for the scheduler to run and update the task dependencies
        @test task1.donenotify.waitq == task2.queue
    end
end
