using Test
using DataFlowTasks
using DataFlowTasks: R, W, RW
using LinearAlgebra

computing(mat) = mat*mat
function work(A, B)
    @dspawn computing(@RW(A)) label="A"
    @dspawn computing(@RW(B)) label="B"
    @dspawn computing(@RW(A)) label="A"
    @dspawn computing(@RW(B)) label="B"
    @dspawn computing(@RW(A)) label="A"
    @dspawn computing(@RW(B)) label="B"
    DataFlowTasks.sync()
end

DataFlowTasks.enable_log()

A = ones(20, 20)
B = ones(20, 20)

work(copy(A), copy(B))

DataFlowTasks.resetlogger!()
DataFlowTasks.TASKCOUNTER[] = 0

GC.gc()

work(A, B)

logger = DataFlowTasks.getlogger()

@test length(logger.tasklogs) == Threads.nthreads()
nbtasks = DataFlowTasks.nbtasknodes(logger)
nbinsertion = sum(length(insertionlog) for insertionlog ∈ logger.insertionlogs)
@test nbtasks == 6
@test nbinsertion == 6

path = DataFlowTasks.criticalpath(logger)
dotstr = DataFlowTasks.loggertodot(logger)
