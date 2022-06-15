using DataFlowTasks
using DataFlowTasks: R, W, RW
using Plots

# Set up
a = 1
b = 2
task(a) = a + exp(a)
computing(a) = (sleep(1) ; task(a))

# Log activation
DataFlowTasks.should_log() = true

# Reset logger and taskcounter
DataFlowTasks.clear_logger()
DataFlowTasks.TASKCOUNTER[] = 0

A = ones(4,4)
B = ones(4,4)

t1 = @dspawn computing(A) (A,) (RW,)
t2 = @dspawn computing(B) (B,) (RW,) 
t3 = @dspawn computing(A) (A,) (RW,)
t4 = @dspawn computing(B) (B,) (RW,)
t5 = @dspawn computing(A) (A,) (RW,)
t6 = @dspawn computing(B) (B,) (RW,)

plot(TraceLog)
plot(DagLog)

fig_path = joinpath(DataFlowTasks.PROJECT_ROOT, "tmp")
fig_path = joinpath(fig_path, "graph.png")
savefig(fig_path)

