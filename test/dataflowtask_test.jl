using Test
using Suppressor
using LinearAlgebra
using DataFlowTasks
import DataFlowTasks as DFT

@testset "Macros" begin
    m, n = 100, 100
    A    = rand(n, m)
    b    = 2
    # verbose way of defining task
    t   = DFT.@dtask rmul!(@RW(A), b)
    tmp = A * b
    @test A !== tmp
    schedule(t)
    wait(t)
    @test A == tmp

    fun(args...) = 1
    (x, y, z) = rand(1), rand(1), rand(1)

    @testset "access tags in arguments list" begin
        t = DFT.@dtask f(@R(x), @W(y), @RW(z))
        @test t.data === (x, y, z, t.task)
        @test t.access_mode == (DFT.READ, DFT.WRITE, DFT.READWRITE, DFT.READWRITE)
        @test t.priority == 0
        @test t.label == ""
    end

    @testset "arrow access tags" begin
        t = DFT.@dtask f(@←(x), @→(y), @↔(z))
        @test t.data === (x, y, z, t.task)
        @test t.access_mode == (DFT.READ, DFT.WRITE, DFT.READWRITE, DFT.READWRITE)
    end

    @testset "access tags in task body" begin
        t = DFT.@dtask begin
            @W x
            @R y z
            f(x', y', z')
        end
        @test t.data === (x, y, z, t.task)
        @test t.access_mode == (DFT.WRITE, DFT.READ, DFT.READ, DFT.READWRITE)
    end

    @testset "access tags in parameters" begin
        t = DFT.@dtask f(x', y', z') @R(x) @W(y) @RW(z)
        @test t.data === (x, y, z, t.task)
        @test t.access_mode == (DFT.READ, DFT.WRITE, DFT.READWRITE, DFT.READWRITE)
    end

    @testset "optional parameters" begin
        j = 2
        t = DFT.@dtask f(@W(x), y') @R(y) priority = j label = "task($j)"
        @test t.data === (x, y, t.task)
        @test t.access_mode == (DFT.WRITE, DFT.READ, DFT.READWRITE)
        @test t.priority == 2
        @test t.label == "task(2)"
    end

    @testset "invalid parameters" begin
        # Check that a warning is issued *at macro expansion time*
        out = @capture_err begin
            @macroexpand DFT.@dtask f(@W(x), y') @R(y) not_an_assignment unknown_param = 1
        end
        msgs = split(out, "\n")
        @test occursin("Malformed", msgs[1]) && occursin("not_an_assignment", msgs[1])
        @test occursin("Unknown", msgs[3]) && occursin("unknown_param", msgs[3])
    end
end

@testset "Data dependency" begin
    m, n = 100, 100
    A    = rand(n, m)
    a    = -π
    b    = 2
    t1   = DFT.@dtask rmul!(@RW(A), @R(b))
    t2   = DFT.@dtask rmul!(@RW(A), @R(b))
    @test DFT.data_dependency(t1, t2) == true
    # rebind A to a different matrix, and make sure independency is inferred
    A = rand(100, 100)
    t3 = DFT.@dtask rmul!(@RW(A), @R(b))
    @test DFT.data_dependency(t1, t3) == false
end

# Mock-up error handler:
# pushes errors to an array instead of displaying them
const ERRORS = []
function DFT._handle_error(exceptions)
    return push!(ERRORS, exceptions)
end

@testset "Error handling" begin
    # Errors are not handled when debug mode is off
    DFT.enable_debug(false)
    empty!(ERRORS)
    t = @dspawn error("Unseen error")
    @test_throws TaskFailedException wait(t)
    @test isempty(ERRORS)

    # Errors are handled when debug mode is on.
    DFT.enable_debug(true)
    empty!(ERRORS)
    t = @dspawn error("Expected error")
    @test_throws TaskFailedException wait(t)
    @test length(ERRORS) == 1
    @test ERRORS[1][1].exception.msg == "Expected error"

    # Tasks can be stopped when debug mode is on
    empty!(ERRORS)
    t = @dspawn sleep(3600)
    sleep(0.1)
    @test !istaskdone(t)
    schedule(t, :stop; error = true)
    sleep(0.1)
    @test istaskdone(t)
    @test isempty(ERRORS)
end

@testset "Sequential mode" begin
    x = rand(10)
    test_seq_mode(x) = @dspawn sum(@R x) label = "test_seq_mode" priority = 1

    # Sequential mode
    DFT.force_sequential()

    s = test_seq_mode(x)
    @test typeof(s) == Float64
    @inferred test_seq_mode(x)

    # Parallell mode
    DFT.force_sequential(false)

    s = test_seq_mode(x)
    @test typeof(s) == Task
    @inferred test_seq_mode(x)
end

@testset "Fetching task" begin
    DataFlowTasks.set_active_taskgraph!(DataFlowTasks.TaskGraph())
    d1 = @dspawn (sleep(0.01); rand(10)) label = "sleep"
    d2 = @dspawn fill!(fetch(@R(d1)), 0) label = "fill"
    @test fetch(d2) |> sum == 0
    # make sure that d2 depends on d1 by checking the length of the critical
    # path
    log_info = DataFlowTasks.@log begin
        d1 = @dspawn (sleep(0.01); rand(10)) label = "sleep"
        d2 = @dspawn fill!(fetch(@R(d1)), 0) label = "fill"
        fetch(d2)
    end
    @test length(DataFlowTasks.longest_path(log_info)) == 2
end
