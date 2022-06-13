using DataFlowTasks
using DataFlowTasks: R, W, RW
using Plots

# Set up
a = 1
b = 2
task(a) = a + exp(a)
computing(a) = (sleep(1) ; task(a))

# Log activation
should_log() = true

# Clear logger
for logs in LOGGER
    empty!(logs)
end

A = ones(4,4)

t1 = @dspawn computing(A) (A,) (RW,)
t2 = @dspawn computing(A) (A,) (RW,) 
t3 = @dspawn computing(A) (A,) (RW,)
t4 = @dspawn computing(A) (A,) (RW,)
t5 = @dspawn computing(A) (A,) (RW,)
t6 = @dspawn computing(A) (A,) (RW,)
t7 = @dspawn computing(A) (A,) (RW,)

wait(t1)
wait(t2)
wait(t3)
wait(t4)
wait(t5)
wait(t6)
wait(t7)

plot(LOGGER)