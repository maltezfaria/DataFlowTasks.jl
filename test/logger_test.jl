using Test
using DataFlowTasks
using LinearAlgebra

# NOTE: the functions below call sleep to make sure the computation does not finish
# before full dag is created. Otherwise the critical path may be "incomplete"
# and the tests on `criticalpath` will fail
computing(A) = (sleep(0.01); A*A)
computing(A, B) = (sleep(0.01); A*B)
function work(A, B)
    @dspawn computing(@RW(A)) label="A²"
    @dspawn computing(@RW(A)) label="A²"
    @dspawn computing(@RW(A)) label="A²"
    @dspawn computing(@RW(B)) label="B²"
    @dspawn computing(@RW(A), @RW(B)) label="A*B"
    DataFlowTasks.sync()
end

DataFlowTasks.enable_log()

A = ones(20, 20)
B = ones(20, 20)

DataFlowTasks.resetlogger!()

work(A, B)

logger = DataFlowTasks.getlogger()

@test length(logger.tasklogs) == Threads.nthreads()
nbtasks = DataFlowTasks.nbtasknodes(logger)
nbinsertion = sum(length(insertionlog) for insertionlog ∈ logger.insertionlogs)
@test nbtasks == 5
@test nbinsertion == 5

# Critical Path
path = DataFlowTasks.criticalpath(logger)
@test path == [5, 3, 2, 1]

# DOT Format File
dotstr = DataFlowTasks.loggertodot(logger)
@test occursin("strict digraph dag", dotstr)
@test occursin("1 -> 2", dotstr)
@test occursin("2 -> 3", dotstr)
@test occursin("3 -> 5", dotstr)
@test occursin("4 -> 5", dotstr)

# Visualization call
DataFlowTasks.plot(logger, categories=["A²", "B²", "A*B"])