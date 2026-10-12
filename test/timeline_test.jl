using Test
using DataFlowTasks
import DataFlowTasks as DFT

# Lifecycle of the tasks of a hand-built log, with known timings. Times are in
# seconds since the start of the window [1 s, 3 s]:
#
#   task  requested  analysis  inserted  started  finished  removed
#   1 "a"    0.0       0.0       0.1       0.1      0.5       0.6
#   2 "b"    0.1       0.1       0.2       0.6      1.0       1.1    after 1, migrated
#   3 "a"    0.2       0.3       0.4       0.5      0.7       0.8    failed
#   4 "c"    0.4       0.4       0.5       1.0      1.5        -     after 2 and 3
const ms = 1_000_000 # 1 millisecond in ns
t0 = 1_000ms
at(t) = t0 + t * ms
function hand_built_log()
    log = DFT.LogInfo()
    log.time_start, log.time_finish = t0, at(2000)
    log.nworkers = 2
    for (tag, req, ana, ins, start, finish, removed, deps, label, tids, failed) in [
            (1, 0, 0, 100, 100, 500, 600, Int[], "a", (1, 1), false),
            (2, 100, 100, 200, 600, 1000, 1100, [1], "b", (1, 2), false),
            (3, 200, 300, 400, 500, 700, 800, Int[], "a", (2, 2), true),
            (4, 400, 400, 500, 1000, 1500, nothing, [2, 3], "c", (2, 2), false),
        ]
        running = (finish - start) * ms
        DFT.record!(log, DFT.TaskLog(tag, at(start), at(finish), running, tids..., deps, label, failed))
        DFT.record!(log, DFT.InsertionLog(at(req), at(ana), at(ins), 0, tag, 1))
        log.active = 1 # removals are only recorded while logging
        isnothing(removed) || DFT.record!(log, DFT.CleanupLog(tag, at(removed - 50), at(removed)))
    end
    return log
end

@testset "Timeline of a hand-built log" begin
    tl = DFT.timeline(hand_built_log())
    @test DFT.tag.(tl) == [1, 2, 3, 4]
    t1, t2, t3, t4 = tl
    @test t3.requested ≈ 0.2 && t3.insertion_start ≈ 0.3 && t3.inserted ≈ 0.4
    @test all((t1.started, t1.finished, t1.removed) .≈ (0.1, 0.5, 0.6))
    @test t4.removed === nothing
    @test t2.running ≈ 0.4
    # ready: once inserted and once the predecessors finished
    @test t1.ready ≈ 0.1 && t1.ready_by == 0
    @test t2.ready ≈ 0.5 && t2.ready_by == 1
    @test t3.ready ≈ 0.4 && t3.ready_by == 0
    @test t4.ready ≈ 1.0 && t4.ready_by == 2
    @test t4.predecessors == [2, 3]
    @test [t.migrated for t in tl] == [false, true, false, false]
    @test [t.failed for t in tl] == [false, false, true, false]
    @test [t.label for t in tl] == ["a", "b", "a", "c"]
    # task 3 starts in the lane of task 1, which finishes at the same time
    @test [t.lane for t in tl] == [1, 2, 1, 1]
end

@testset "Concurrency of a hand-built log" begin
    c = DFT.concurrency(hand_built_log())
    @test c.time ≈ [0, 0.1, 0.2, 0.4, 0.5, 0.6, 0.7, 0.8, 1.0, 1.1, 1.5, 2.0]
    # task 4 is not removed during the window: it is in the dag until its end
    @test c.dag == [0, 1, 2, 3, 4, 3, 3, 2, 2, 1, 1, 0]
    @test c.ready == [0, 0, 0, 1, 1, 0, 0, 0, 0, 0, 0, 0]
    @test c.running == [0, 1, 1, 1, 1, 2, 1, 1, 1, 1, 0, 0]
    @test maximum(c.running) == maximum(t.lane for t in DFT.timeline(hand_built_log()))
end

@testset "Realized critical path of a hand-built log" begin
    log = hand_built_log()
    path = DFT.realized_critical_path(log)
    @test path == [1, 2, 4]
    # the path covers the window up to the end of the last task: each task is
    # made ready by the end of the previous one
    tl = Dict(DFT.tag(t) => t for t in DFT.timeline(log))
    for (p, t) in zip(path, path[2:end])
        @test tl[t].ready == tl[p].finished
    end
    @test tl[first(path)].ready_by == 0
    @test tl[last(path)].finished ≈ 1.5
    @test isempty(DFT.realized_critical_path(DFT.LogInfo()))
end

@testset "Timeline without insertion records" begin
    log = DFT.LogInfo()
    log.time_start, log.time_finish = t0, at(1000)
    DFT.record!(log, DFT.TaskLog(1, at(100), at(200), 100ms, 1, 1, Int[], "", false))
    t = only(DFT.timeline(log))
    @test t.requested == t.insertion_start == t.inserted == t.ready == t.started
    @test t.ready_by == 0
    @test t.removed === nothing
end

@testset "Timeline of a real run" begin
    A, B = zeros(1), zeros(1)
    log = DFT.@log begin
        for _ in 1:5
            @dspawn (@RW(A); sleep(0.01))
            @dspawn (@RW(B); sleep(0.01))
            @dspawn (@R(A, B); sleep(0.01))
        end
        wait(DFT.get_active_taskgraph())
    end
    tl = DFT.timeline(log)
    @test length(tl) == 15
    for t in tl
        @test 0 <= t.requested <= t.insertion_start <= t.inserted <= t.ready <= t.started <= t.finished
        @test isnothing(t.removed) || t.finished <= t.removed
    end
    c = DFT.concurrency(log)
    @test maximum(c.running) == maximum(t.lane for t in tl)
    @test c.time[end] ≈ (log.time_finish - log.time_start) * 1.0e-9
    path = DFT.realized_critical_path(log)
    @test issorted(path) && last(path) == DFT.tag(argmax(t -> t.finished, tl))
end

@testset "Elapsed time along the realized critical path" begin
    sm = DFT.summarize(hand_built_log())
    @test sm.realized_path == [1, 2, 4]
    @test sm.realized_before ≈ 0.1 # task 1 is ready once inserted
    @test sm.realized_waiting ≈ 0.1 # task 2 starts 0.1 s after task 1 finishes
    @test sm.realized_bodies ≈ 0.4 + 0.4 + 0.5
    @test DFT.realized_after(sm) ≈ 0.5
end
