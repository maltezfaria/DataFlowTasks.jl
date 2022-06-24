#=
    Utility functions for testing the DataFlowTasks package.
=#
using DataFlowTasks: R,W,RW

# define a simple function to mimic a problem with fork-join parallelization.
# The execution starts with one node, spawns `n` independent nodes, and then
# joint them later at a last node. This is repeated m times. The  computation waits for the last node, and
# each block works for `s` seconds
function fork_join(n,s,m=1)
    A = rand(2n)
    @dspawn do_work(s,@RW A) label="first"
    for i in 1:n
        Av = view(A,[i,i+n])
        @dspawn do_work(s,Av) label="indep($i)"
    end
    res = @dspawn do_work(s,@R A) label="last"
    return res
end

function do_work(t,args...)
    ti = time()
    while (time()-ti) < t end
    return
end
