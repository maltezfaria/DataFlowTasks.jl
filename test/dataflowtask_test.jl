using Test
using LinearAlgebra
using DataFlowTasks
using DataFlowTasks: data_dependency

@testset "Macros" begin
    m,n  = 100,100
    A    = rand(n,m)
    b    = 2
    # verbose way of defining task
    t    = @dtask rmul!(@RW(A), b)
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
    t1 = @dtask rmul!(@RW(A), @R(b))
    t2 = @dtask rmul!(@RW(A), @R(b))
    @test data_dependency(t1,t2) == true
    # rebind A to a different matrix, and make sure independency is inferred
    A = rand(100,100)
    t3 = @dtask rmul!(@RW(A), @R(b))
    @test data_dependency(t1,t3) == false
end


# Mock-up error handler:
# pushes errors to an array instead of displaying them
const ERRORS = []
function DataFlowTasks._handle_error(exceptions)
    push!(ERRORS, exceptions)
end

@testset "Error handling" begin
    # Errors are not handled when debug mode is off
    DataFlowTasks.enable_debug(false)
    empty!(ERRORS)
    t = @dspawn error("Unseen error")
    @test_throws TaskFailedException wait(t)
    @test isempty(ERRORS)

    # Errors are handled when debug mode is on
    DataFlowTasks.enable_debug(true)
    empty!(ERRORS)
    t = @dspawn error("Expected error")
    @test_throws TaskFailedException wait(t)
    @test length(ERRORS) == 1
    @test ERRORS[1][1].exception.msg == "Expected error"

    # Tasks can be stopped when debug mode is on
    empty!(ERRORS)
    t = @dspawn sleep(3600)
    sleep(0.1); @test !istaskdone(t.task)
    schedule(t.task, :stop, error=true)
    sleep(0.1); @test istaskdone(t.task)
    @test isempty(ERRORS)
end
