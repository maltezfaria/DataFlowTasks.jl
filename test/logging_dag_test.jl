using Test
using DataFlowTasks
using DataFlowTasks: Logger, parse!, PlotFinished, PlotRunnable, TiledFactorization
using LinearAlgebra
using Logging
using Plots

GC.gc()

sch = DataFlowTasks.JuliaScheduler(1000)
# sch = DataFlowTasks.PriorityScheduler(200,true)
DataFlowTasks.setscheduler!(sch)

include(joinpath(DataFlowTasks.PROJECT_ROOT,"test","testutils.jl"))

m = 4000
A = rand(m,m)
A = (A+A') + 2*size(A,1)*I

TiledFactorization.TILESIZE[] = 256
io     = open("forkjoin.log","w+")
logger = Logger(io)
TiledFactorization.cholesky!(copy(A)) # run once to compile
DataFlowTasks.TASKCOUNTER[] = 0
with_logger(logger) do
    DataFlowTasks.reset_timer!(logger)
    F = TiledFactorization.cholesky!(A)
end
parse!(logger)

# plot(PlotRunnable(),logger)
# plot(PlotFinished(),logger)
@info DataFlowTasks.TASKCOUNTER[]
plot(logger)

# tl = logger.tasklogs
# chol  = filter(t-> occursin("chol",t.task_label),tl)
# schur = filter(t-> occursin("schur",t.task_label),tl)
# ldiv = filter(t-> occursin("ldiv",t.task_label),tl)

# t_chol = map(t -> (t.time_finish-t.time_start)/1e9,chol)
# t_ldiv = map(t -> (t.time_finish-t.time_start)/1e9,ldiv)
# t_schur = map(t -> (t.time_finish-t.time_start)/1e9,schur)
# histogram(t_chol,label="cholesky",xlabel="time (s)",alpha=0.8)
# histogram!(t_ldiv,label="ldiv",xlabel="time (s)",alpha=0.5)
# histogram!(t_schur,label="schur",xlabel="time (s)",alpha=0.5)
# plot(p1,p2,p3,layout=(1,3))
