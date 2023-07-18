using Test
using LinearAlgebra
import DataFlowTasks as DFT

@testset "Dependencies" begin
    @testset "Arrays and subarrays" begin
        m, n = 20, 20
        A    = rand(m, n)
        C    = A
        B    = copy(A)
        @test DFT.memory_overlap(A, C) == true
        @test DFT.memory_overlap(A, B) == false
        A11 = view(A, 1:10, 1:10)
        A12 = view(A, 11:20, 1:10)
        @test DFT.memory_overlap(A, A11) == true
        @test DFT.memory_overlap(A11, A11) == true
        @test DFT.memory_overlap(A11, A12) == false
    end
end
