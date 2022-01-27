using Test
using LinearAlgebra
using DataFlowTasks
using DataFlowTasks: data_dependency,R,W,RW

@testset "Macros" begin
    m,n  = 100,100
    A    = rand(n,m)
    b    = 2
    # verbose way of defining task
    t    = @dtask rmul!(A,b) (A,) (RW,)
    tmp  = A*b
    @test A !== tmp
    schedule(t)
    wait(t)
    @test A == tmp
end

@testset "Data dependency" begin
    m,n  = 100,100
    A    = rand(n,m)
    a    = -π
    b    = 2
    t1 = @dtask rmul!(A,b) (A,b) (RW,R)
    t2 = @dtask rmul!(A,b) (A,b) (RW,R)
    @test data_dependency(t1,t2) == true
    # rebind A to a different matrix, and make sure independency is inferred
    A = rand(100,100)
    t3 = @dtask rmul!(A,b) (A,b) (RW,R)
    @test data_dependency(t1,t3) == false
end
