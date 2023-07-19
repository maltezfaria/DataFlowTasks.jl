using Test
using DataFlowTasks
using DataFlowTasks: memory_overlap
using LinearAlgebra

@testset "Dependencies" begin
    @testset "Arrays and subarrays" begin
        m, n = 20, 20
        A    = rand(m, n)
        C    = A
        B    = copy(A)
        @test memory_overlap(A, C) == true
        @test memory_overlap(A, B) == false
        A11 = view(A, 1:10, 1:10)
        A12 = view(A, 11:20, 1:10)
        @test memory_overlap(A, A11) == true
        @test memory_overlap(A11, A11) == true
        @test memory_overlap(A11, A12) == false
        @test memory_overlap(A11', A12) == false
        @test memory_overlap(A11', A12') == false
    end
end
