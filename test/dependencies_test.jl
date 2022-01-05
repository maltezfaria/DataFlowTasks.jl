using Test
using SafeTestsets

@safetestset "Dependencies" begin
    using LinearAlgebra
    using DataFlowScheduler
    R,W,RW  = DataFlowScheduler.READ, DataFlowScheduler.WRITE, DataFlowScheduler.READWRITE
    @testset "Arrays and subarrays" begin
        using DataFlowScheduler: memory_overlap
        m,n = 20,20
        A   = rand(m,n)
        C   = A
        B   = copy(A)
        @test memory_overlap(A,C) == true
        @test memory_overlap(A,B) == false
        A11 = view(A,1:10,1:10)
        A12 = view(A,11:20,1:10)
        @test memory_overlap(A,A11) == true
        @test memory_overlap(A11,A11) == true
        @test memory_overlap(A11,A12) == false
    end
end
