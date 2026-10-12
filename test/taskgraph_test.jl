using Test
using LinearAlgebra
using DataFlowTasks
using Suppressor
import DataFlowTasks as DFT

include(joinpath(DFT.PROJECT_ROOT, "test", "testutils.jl"))

tg = DFT.TaskGraph(200)
DFT.set_active_taskgraph!(tg)

@testset "Fork-join" begin
    m = 10
    s = 0.1
    nw = Threads.nthreads()
    t = fetch(fork_join(m, s))
    t1 = @elapsed fetch(fork_join(m, s))
    t2 = (2 + ceil(m / nw)) * s
    # test that ideal vs actual time are close
    @test abs(t1 - t2) < 1.0e-2
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
    # test that ideal vs actual time are close
    @test abs(t1 - t2) < 1.0e-2
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
