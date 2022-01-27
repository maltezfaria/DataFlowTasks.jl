#=
    Utility functions for testing the DataFlowTasks package.
=#
using DataFlowTasks: R,W,RW

# define a simple function to mimic a problem with fork-join parallelization.
# The execution starts with one node, spawns `n` independent nodes, and then
# joint them later at a last node. The  computation waits for the last node, and
# each block works for `s` seconds
function fork_join(n,s)
    A = rand(2n)
    @dspawn do_work(s) (A,) (RW,)
    for i in 1:n
        @dspawn do_work(s) (view(A,[i,i+n]),) (RW,)
    end
    res = @dspawn do_work(s) (A,) (R,)
    return res
end

function do_work(t)
    ti = time()
    while (time()-ti) < t end
    return
end
