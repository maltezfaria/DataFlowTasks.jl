using Test
using DataFlowTasks
import DataFlowTasks as DFT

# Summaries of hand-built logs, with known timings: no threads or timing involved.
#
#   window: [1 s, 3 s], with 2 workers
#   task 1 ("a")          : body [0.0, 0.5] s, running 0.50 s, thread 2 → 2
#   task 2 ("b", after 1) : body [0.5, 1.5] s, running 0.25 s, thread 2 → 3 (migrated)
#   task 3 ("a", failed)  : body [0.2, 0.4] s, running 0.20 s, thread 3 → 3
#   two insertions of 0.01 s each, the second one with 0.005 s of gc
const s = 1_000_000_000 # 1 second in ns
t0 = 1s
function hand_built_log()
    log = DFT.LogInfo()
    log.time_start, log.time_finish = t0, t0 + 2s
    log.nworkers = 2
    log.gc_time, log.compile_time = 0.25, 0.125
    DFT.record!(log, DFT.TaskLog(1, t0, t0 + s ÷ 2, s ÷ 2, 2, 2, Int[], "a", false))
    DFT.record!(log, DFT.TaskLog(2, t0 + s ÷ 2, t0 + 3s ÷ 2, s ÷ 4, 2, 3, [1], "b", false))
    DFT.record!(log, DFT.TaskLog(3, t0 + s ÷ 5, t0 + 2s ÷ 5, s ÷ 5, 3, 3, Int[], "a", true))
    DFT.record!(log, DFT.InsertionLog(t0, t0, t0 + s ÷ 100, 0, 1, 1))
    DFT.record!(log, DFT.InsertionLog(t0, t0, t0 + s ÷ 100, s ÷ 200, 2, 1))
    return log
end

@testset "Summary of a hand-built log" begin
    sm = DFT.summarize(hand_built_log(); categories = ["a", "b"])
    @test sm.elapsed ≈ 2.0
    @test sm.workers == 2
    @test DFT.capacity(sm) ≈ 4.0
    @test sm.running ≈ 0.5 + 0.25 + 0.2
    @test DFT.idle(sm) ≈ 4.0 - 0.95
    @test DFT.nowait(sm) ≈ 0.95 / 2
    @test sm.blocked ≈ 0.75 # task 2 ran 0.25 s of its 1 s body
    @test sm.running_per_category ≈ [0.7, 0.25, 0.0]
    @test first.(sm.categories) == ["a", "b"]
    # the longest chain is 1 → 2, weighted by the wall time of the bodies
    @test sm.path == [2, 1]
    @test sm.critical_path ≈ 1.5
    @test sm.insertion ≈ 0.02
    @test sm.gc == 0.25
    @test sm.compile == 0.125
    @test (sm.ntasks, sm.nfailed, sm.nmigrated) == (3, 1, 1)
end

@testset "Categories" begin
    log = hand_built_log()
    # no categories: everything is unlabeled
    @test DFT.summarize(log).running_per_category ≈ [0.95]
    # regex categories, matched in order
    sm = DFT.summarize(log; categories = ["vowel" => r"[aeiou]", "any" => r"."])
    @test sm.running_per_category ≈ [0.7, 0.25, 0.0]
end

@testset "Gantt data" begin
    log = hand_built_log()
    g = DFT.Gantt(log, DFT.summarize(log; categories = ["a", "b"]))
    # 3 tasks, 2 insertions, 1 gc
    @test length(g.threads) == 6
    # task bars, relative to the start of the window, shaded by running fraction
    @test g.starts[1:3] ≈ [0.0, 0.5, 0.2]
    @test g.stops[1:3] ≈ [0.5, 1.5, 0.4]
    @test g.running_fraction[1:3] ≈ [1.0, 0.25, 1.0]
    @test g.jobids[1:3] == [1, 2, 1]
    # insertions (category 4) and gc (category 5) on the calling thread
    @test sort(g.jobids[4:end]) == [4, 4, 5]
    @test all(==(1), g.threads[4:end])
end

@testset "describe" begin
    out = sprint(io -> DFT.describe(io, hand_built_log(); categories = ["a", "b"]))
    @test occursin(r"Elapsed time\s+: 2.000", out)
    @test occursin(r"Running tasks\s+: 0.950", out)
    @test occursin(r"Idle\s+: 3.050", out)
    @test occursin(r"Tasks blocked\s+: 0.750", out)
    @test occursin("1 of the 3 tasks failed", out)
end

@testset "Logs without a window" begin
    @test_throws ArgumentError DFT.summarize(DFT.LogInfo())
end
