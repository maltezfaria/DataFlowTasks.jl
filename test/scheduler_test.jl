using SafeTestsets

@safetestset "Scheduler" begin
    using LinearAlgebra
    using HScheduler
    using LightGraphs
    R,W,RW  = HScheduler.READ, HScheduler.WRITE, HScheduler.READWRITE

    @testset "Serial execution" begin
        using LightGraphs
        using HScheduler: insert_task!, gettask, gettasks, plan_block_gemm!, getgraph
        m,n,k     = 100, 50, 40
        bsize     = (5,5,5)
        C  = rand(m,n)
        A  = rand(m,k)
        B  = rand(k,n)
        tmp = C + A*B
        task_graph = TaskGraph(Codelet[],SimpleDiGraph())
        t = @elapsed plan_block_gemm!(C,A,B,1,1,bsize,task_graph);
        @info "t = $t", "ne = $(ne(task_graph)), nv = $(nv(task_graph))"
        @test !(C ≈ tmp)
        graph = getgraph(task_graph)
        sch = Scheduler(task_graph)
        HScheduler.run(sch)
        @test C ≈ tmp
        t = @elapsed tmp = transitivereduction(task_graph);
        @info "t = $t", "ne = $(ne(tmp)), nv = $(nv(tmp))"
        # block_gemm!(C,A,B,1,1,bsize)
        # @test C ≈ tmp
    end
end
