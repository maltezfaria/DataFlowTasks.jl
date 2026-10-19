using Test
using LinearAlgebra
using DataFlowTasks
using Suppressor
import DataFlowTasks as DFT

include(joinpath(DFT.PROJECT_ROOT, "test", "testutils.jl"))

tg = DFT.TaskGraph(200)
DFT.set_active_taskgraph!(tg)

# a type for which the data-flow analysis throws
struct Faulty
    data::Vector{Float64}
end
DFT.memory_overlap(::Faulty, ::Vector{Float64}) = error("faulty memory_overlap")
DFT.memory_overlap(v::Vector{Float64}, f::Faulty) = DFT.memory_overlap(f, v)

@testset "Fork-join" begin
    m = 10
    s = 0.1
    nw = Threads.nthreads()
    t = fetch(fork_join(m, s))
    t1 = @elapsed fetch(fork_join(m, s))
    t2 = (2 + ceil(m / nw)) * s
    # test that ideal vs actual time are close: losing parallelism costs at
    # least one extra block of `s` seconds, so allow for half a block of noise
    @test t2 - 1.0e-2 < t1 < t2 + s / 2
end

@testset "Stop dag worker" begin
    m = 10
    s = 0.1
    nw = Threads.nthreads()
    # stopping the dag_worker will mean finished nodes are no longer cleaned up
    DFT.stop_dag_cleaner()
    fork_join(m, s)
    @test DFT.num_nodes(tg.dag) == m + 3
    # resuming dag_worker will now cleanup nodes
    DFT.start_dag_cleaner()
    wait(tg) # wait for graph to be empty
    @test DFT.num_nodes(tg.dag) == 0
    t1 = @elapsed fetch(fork_join(m, s))
    t2 = (2 + ceil(m / nw)) * s
    # test that ideal vs actual time are close: losing parallelism costs at
    # least one extra block of `s` seconds, so allow for half a block of noise
    @test t2 - 1.0e-2 < t1 < t2 + s / 2
end

@testset "Restart dag worker" begin
    n = 10
    A = ones(n)
    blocker = Channel{Nothing}()
    # a first task that never finishes
    t1 = @dspawn take!(blocker) (@RW A)
    # a second task that waits on it
    t2 = @dspawn identity(@RW A)
    # check that scheduler is in limbo
    tg = DFT.get_active_taskgraph()
    @test DFT.num_nodes(tg.dag) == 2
    # restart scheduler and make sure it runs again
    empty!(tg)
    @test DFT.num_nodes(tg.dag) == 0
    # the tasks removed by `empty!` may still finish (here they fail), which
    # must not break the dag cleaner
    @suppress_err begin
        close(blocker)
        @test timedwait(() -> istaskdone(t2), 5) == :ok
    end
    t = @dspawn sum(@R A)
    @test fetch(t) == n
    @test timedwait(() -> isempty(tg), 5) == :ok
    @test !istaskdone(tg.dag_cleaner)
end

@testset "Dag cleaner threadpool" begin
    tg = DFT.TaskGraph()
    expected = Threads.nthreads(:interactive) > 0 ? :interactive : :default
    @test Threads.threadpool(tg.dag_cleaner) == expected
    DFT.stop_dag_cleaner(tg)
end

@testset "Capacity back-pressure" begin
    # a small capacity forces constant hand-offs between the inserting task and
    # the dag cleaner
    tg = DFT.TaskGraph(2)
    n = 2_000
    A = zeros(Int, 4)
    DFT.with_taskgraph(tg) do
        for i in 1:n
            Av = view(A, mod1(i, 4):mod1(i, 4))
            @dspawn (@RW(Av); Av[1] += 1)
        end
    end
    wait(tg)
    @test DFT.num_nodes(tg.dag) == 0
    @test sum(A) == n
    DFT.stop_dag_cleaner(tg)
end

@testset "resize! wakes up waiting inserters" begin
    tg = DFT.TaskGraph(1)
    DFT.stop_dag_cleaner(tg) # finished nodes are not removed
    A, B = ones(2), ones(2)
    DFT.with_taskgraph(() -> @dspawn(sum(@R A)), tg)
    # the dag is full, so this insertion blocks until there is room
    inserter = Threads.@spawn DFT.with_taskgraph(() -> @dspawn(sum(@R B)), tg)
    sleep(0.1)
    @test !istaskdone(inserter)
    @test_throws ArgumentError resize!(tg, 0)
    resize!(tg, 2)
    @test fetch(fetch(inserter)) == 2
    @test DFT.num_nodes(tg.dag) == 2
    DFT.start_dag_cleaner(tg)
    wait(tg)
    @test DFT.num_nodes(tg.dag) == 0
end

@testset "wait returns after empty!" begin
    tg = DFT.TaskGraph()
    A = ones(2)
    blocker = Channel{Nothing}()
    DFT.with_taskgraph(tg) do
        @dspawn take!(blocker) (@RW A) # never finishes
        return @dspawn identity(@RW A) # waits on the blocked task
    end
    waiter = Threads.@spawn wait(tg)
    sleep(0.1)
    @test !istaskdone(waiter)
    @suppress_err empty!(tg)
    @test timedwait(() -> istaskdone(waiter), 5) == :ok
    DFT.stop_dag_cleaner(tg)
    close(blocker) # release the blocked tasks
end

@testset "Failed tasks are removed from the dag" begin
    tg = DFT.TaskGraph()
    A = ones(2)
    t1, t2 = DFT.with_taskgraph(tg) do
        t1 = @dspawn error() (@RW A)
        t2 = @dspawn sum(@R A) # depends on `t1`, so it fails too
        return t1, t2
    end
    waiter = Threads.@spawn wait(tg)
    @test @suppress_err(timedwait(() -> istaskdone(waiter), 5)) == :ok
    @test istaskfailed(t1) && istaskfailed(t2)
    @test isempty(tg)
    DFT.stop_dag_cleaner(tg)
end

@testset "A failed insertion leaves the dag unchanged" begin
    tg = DFT.TaskGraph(2)
    A = ones(2)
    blocker = Channel{Nothing}()
    t1 = DFT.with_taskgraph(() -> @dspawn((@R(A); take!(blocker))), tg)
    @test_throws ErrorException DFT.with_taskgraph(() -> @dspawn(fill!(@W(Faulty(A)).data, 0)), tg)
    @test DFT.num_nodes(tg.dag) == 1
    # the dag is still usable, and empties once the first task finishes
    t2 = DFT.with_taskgraph(() -> @dspawn(sum(@R(A))), tg)
    @test fetch(t2) == 2
    put!(blocker, nothing)
    wait(t1)
    waiter = Threads.@spawn wait(tg)
    @test timedwait(() -> istaskdone(waiter), 5) == :ok
    @test isempty(tg)
    DFT.stop_dag_cleaner(tg)
end

@testset "empty! with tasks waiting for a thread" begin
    # the main task needs a thread of its own while the workers are busy
    if Threads.nthreads(:interactive) == 0
        @test_skip false
    else
        tg = DFT.TaskGraph()
        release = Threads.Atomic{Bool}(false)
        spinning = Threads.Atomic{Int}(0)
        function spin(release)
            Threads.atomic_add!(spinning, 1)
            while !release[]
                GC.safepoint()
            end
            return
        end
        # occupy all the workers, so that the tasks below wait for a thread
        nworkers = Threads.nthreads(:default)
        blockers = [Threads.@spawn spin(release) for _ in 1:nworkers]
        @test timedwait(() -> spinning[] == nworkers, 5) == :ok
        xs = [zeros(1) for _ in 1:5]
        ts = DFT.with_taskgraph(tg) do
            [@dspawn fill!(@W(x), 1) for x in xs]
        end
        @test !any(istaskstarted, ts)
        @suppress_err empty!(tg)
        @test isempty(tg)
        release[] = true
        foreach(wait, blockers)
        # the removed tasks still run, and the task graph can be used again
        @test timedwait(() -> all(istaskdone, ts), 5) == :ok
        @test all(x -> x[1] == 1, xs)
        @test fetch(DFT.with_taskgraph(() -> @dspawn(sum(@R(xs[1]))), tg)) == 1
        DFT.stop_dag_cleaner(tg)
    end
end

@testset "A failed dependency does not stop the dag cleaner" begin
    # `j` depends on `k`, which fails at once, and on `i`, which is still
    # running: `j` must not leave the dag before `i`. Shifting the tags varies
    # the order in which `j` waits for its dependencies.
    for shift in 1:4
        tg = DFT.TaskGraph()
        A, B = ones(2), ones(2)
        i, j = DFT.with_taskgraph(tg) do
            for _ in 1:shift
                @dspawn identity(nothing)
            end
            i = @dspawn (@W(B); sleep(0.2))
            @dspawn (@W(A); error("k fails"))
            j = @dspawn sum(@R(A)) + sum(@R(B))
            return i, j
        end
        waiter = Threads.@spawn wait(tg)
        @test @suppress_err(timedwait(() -> istaskdone(waiter), 5)) == :ok
        @test istaskdone(i) && !istaskfailed(i)
        # `j` leaves the dag just before its task is marked as failed
        @test timedwait(() -> istaskdone(j), 5) == :ok && istaskfailed(j)
        @test !istaskfailed(tg.dag_cleaner)
        @test isempty(tg)
        istaskfailed(tg.dag_cleaner) || DFT.stop_dag_cleaner(tg)
    end
end

@testset "Interrupting a waiting task does not stop the dag cleaner" begin
    tg = DFT.TaskGraph(3)
    A = ones(2)
    i, j = DFT.with_taskgraph(tg) do
        i = @dspawn (@W(A); sleep(0.3))
        j = @dspawn sum(@R(A))
        return i, j
    end
    sleep(0.1)
    # `j` stops waiting for `i`, and leaves the dag before it
    @suppress_err schedule(j, ErrorException("interrupted"); error = true)
    @test timedwait(() -> istaskdone(j), 5) == :ok && istaskfailed(j)
    wait(i)
    # the dag is emptied, so that more tasks than its capacity can be spawned
    t = Threads.@spawn DFT.with_taskgraph(tg) do
        foreach(k -> @dspawn(identity(k)), 1:10)
    end
    @test timedwait(() -> istaskdone(t), 5) == :ok
    @test timedwait(() -> isempty(tg), 5) == :ok
    @test !istaskfailed(tg.dag_cleaner)
    DFT.stop_dag_cleaner(tg)
end

@testset "with_taskgraph restores the active taskgraph" begin
    old = DFT.get_active_taskgraph()
    tg = DFT.TaskGraph()
    @test DFT.with_taskgraph(DFT.get_active_taskgraph, tg) === tg
    @test DFT.get_active_taskgraph() === old
    # also when `f` throws
    @test_throws ErrorException DFT.with_taskgraph(() -> error("boom"), tg)
    @test DFT.get_active_taskgraph() === old
    DFT.stop_dag_cleaner(tg)
end

@testset "with_taskgraph only affects its block and the tasks created in it" begin
    tg = DFT.TaskGraph()
    started, resume = Base.Event(), Base.Event()
    inside = Threads.@spawn DFT.with_taskgraph(tg) do
        notify(started)
        wait(resume)
        # a task created inside the block inherits its task graph
        return fetch(Threads.@spawn DFT.get_active_taskgraph())
    end
    wait(started)
    # meanwhile, the other tasks are not affected
    @test DFT.get_active_taskgraph() !== tg
    notify(resume)
    @test fetch(inside) === tg
    DFT.stop_dag_cleaner(tg)
end


@testset "Priorities" begin
    # with a single worker, tasks are started in the order they are queued
    if Threads.nthreads(:default) > 1
        n = 1000
        release = Threads.Atomic{Bool}(false)
        spinning = Threads.Atomic{Int}(0)
        function spin(release)
            Threads.atomic_add!(spinning, 1)
            while !release[]
                GC.safepoint() # let the garbage collector run
            end
            return
        end
        # occupy all the workers, so that the tasks below wait for a thread
        nworkers = Threads.nthreads(:default)
        blockers = [Threads.@spawn spin(release) for _ in 1:nworkers]
        @test timedwait(() -> spinning[] == nworkers, 5) == :ok
        order = Threads.Atomic{Int}(0)
        starts = zeros(Int, 2n)
        xs = [zeros(1) for _ in 1:2n]
        priorities = [isodd(i) ? 0 : 1000 for i in 1:2n]
        # no task can finish while the workers are occupied, so the task graph
        # must hold all of them (with fewer tasks, priorities show less clearly)
        tasks = DFT.with_taskgraph(DFT.TaskGraph(2n)) do
            return map(1:2n) do i
                x = xs[i]
                @dspawn (@W(x); starts[i] = Threads.atomic_add!(order, 1) + 1) priority =
                    priorities[i]
            end
        end
        release[] = true
        foreach(wait, blockers)
        foreach(wait, tasks)
        # priorities are only approximately respected: most of the first tasks to
        # start are the urgent ones
        first_started = sortperm(starts)[1:n]
        @test count(i -> priorities[i] == 0, first_started) >= 0.7n
    end
end
