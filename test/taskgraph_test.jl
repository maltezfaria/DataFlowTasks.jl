using SafeTestsets

@safetestset "TaskGraph" begin
    using LinearAlgebra
    using HScheduler
    R,W,RW  = HScheduler.READ, HScheduler.WRITE, HScheduler.READWRITE
    @testset "Creation" begin
        using LightGraphs
        using HScheduler: TaskGraph, insert_task!, gettask, gettasks
        m,n = 10,10
        A  = rand(m,n)
        B  = rand(m,n)
        C  = rand(m,n)
        graph = TaskGraph()
        codelet1 = Codelet(cpu_func=rmul!,data=[C,2],access_modes=[RW,R])
        codelet2 = Codelet(cpu_func=axpy!,data=[2,C,A],access_modes=[R,R,RW])
        codelet3 = Codelet(cpu_func=axpy!,data=[2,C,B],access_modes=[R,R,RW])
        codelet4 = Codelet(cpu_func=axpy!,data=(2,A,B),access_modes=[R,R,RW])
        insert_task!(graph,codelet1)
        insert_task!(graph,codelet2)
        insert_task!(graph,codelet3)
        insert_task!(graph,codelet4)
        @test nv(graph) == 4
        @test gettask(graph,2) == codelet2
        @test gettasks(graph) == [codelet1,codelet2,codelet3,codelet4]
        @test gettask(graph,:) == [codelet1,codelet2,codelet3,codelet4]
        @test has_edge(graph,1,2) == true
        @test has_edge(graph,1,3) == true
        @test has_edge(graph,2,3) == false
        @test has_edge(graph,1,4) == false
        @test has_edge(graph,3,4) == true
        @test has_edge(graph,2,4) == true
    end
end
