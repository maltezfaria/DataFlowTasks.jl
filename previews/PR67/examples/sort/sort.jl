# # Merge sort

# This implements a parallel [merge sort](https://en.wikipedia.org/wiki/Merge_sort) using `DataFlowTasks`

# ## Sequential version

# We'll use a "bottom-up" implementation of the merge sort algorithm. To explain
# how it works, let's consider a small vector of 32 elements:

using Random, CairoMakie, CairoMakie.Colors
v = randperm(32)
barplot(v)

# We decompose it into 4 blocks of 8 elements, which we sort individually:

sort!(view(v, 1:8))
sort!(view(v, 9:16))
sort!(view(v, 17:24))
sort!(view(v, 25:32))
barplot(v; color=ceil.(Int, eachindex(v)./8), colormap=:Set1_4)

# Now we can merge the first two 8-element blocks into a sorted 16-element
# block. And do the same for the 3rd and 4th 8-element blocks. We'll need an
# auxilliary array `w` to store the results:

function merge!(dest, src₁, src₂)
    ## pre-condition:
    ##   src₁ is sorted
    ##   src₂ is sorted
    ##   length(src₁) + length(src₂) == length(dest)
    ## post-condition:
    ##   dest is sorted

    (i₁, i₂) = (1, 1)
    (n₁, n₂) = (length(src₁), length(src₂))
    @inbounds for j in eachindex(dest)
        if i₁ <= n₁ && (i₂ > n₂ || src₁[i₁] < src₂[i₂])
            dest[j] = src₁[i₁]; i₁ += 1
        else
            dest[j] = src₂[i₂]; i₂+=1
        end
    end

end

w = similar(v)
@views merge!(w[1:16],  v[1:8],   v[9:16])
@views merge!(w[17:32], v[17:24], v[25:32])
barplot(w; color=ceil.(Int, eachindex(v)./16), colormap=:Set1_3)

# Now `w` is sorted in two blocks, which we can merge to get the entire sorted
# array. Instead of using a new buffer to store the results, let's re-use the
# original array `v`:
@views merge!(v, w[1:16], w[17:32])
barplot(v)


# The following sequential implementation automates these steps.
#
# First, the vector is decomposed in blocks of size 64 (by default). Each block is
# sorted using an insertion sort (which works in-place without allocating
# anything, and is relatively fast for small vectors).
#
# Then, sorted blocks are grouped in pairs which are merged into the buffer. If
# the number of blocks is odd, the last block is copied directly to the
# destination buffer.
#
# The auxiliary buffer is now composed of sorted blocks twice as large as the
# original blocks, so we can iterate the algorithm with a doubled block size,
# this time putting the results back to the original vector.
#
# Depending on the parity of the number of iterations, the final result ends up
# being stored either in the original vector (which is what we want) or in the
# auxiliary buffer (in which case we copy it back to the original vector). The
# semantics of `mergesort!` is thus that of an in-place sort: after the call,
# `v` should be sorted.

function mergesort!(v, buf=similar(v), bs=64)
    N = length(v)

    for i in 1:bs:N
        j = min(i+bs-1, N)
        sort!(view(v, i:j), alg=InsertionSort)
    end

    (a, b) = (v, buf)

    while bs < length(v)
        i = 1
        while i < N
            i1 = i+bs;    i1>N && break
            i2 = i+2bs-1; i2 = min(i2, N)
            @views merge!(b[i:i2], a[i:i1-1], a[i1:i2])

            i = i2+1
        end
        if i <= N
            @inbounds b[i:N] .= a[i:N]
        end

        bs *= 2
        (a, b) = (b, a)
    end

    v === a || copy!(v, a)
    v
end

N = 100_000
v = rand(N)
buf = similar(v)

@assert mergesort!(copy(v), buf) == sort(v)

# ## Parallel version

# Parallelizing with DataFlowTasks involves splitting the work into several
# parallel tasks, which have to be annotated to list their data dependencies. In our case:
#
# - Sorting each initial block involves calling the sequential implementation on
#   it. The block size is larger here, to avoid spawning tasks for too small
#   chunks. Each such task modifies its own block in-place.
#
# - Merging two blocks (or copying a lone block) reads part of the source array, and writes to (the same)
#   part of the destination array.
#
# - A final task reads the whole array to act as a barrier: we can fetch it to
#   synchronize all other tasks and get the result.

using DataFlowTasks

function mergesort_dft!(v, buf=similar(v), bs=16384)
    N = length(v)

    for i in 1:bs:N
        j = min(i+bs-1, N)
        DataFlowTasks.@spawn mergesort!(@RW(view(v, i:j))) label="sort\n$i:$j"
    end

    ## WARNING: (from, to) are not local to each task
    (from, to) = (v, buf)

    while bs < N
        i = 1  # WARNING: i is not local to each task
        while i < N
            i1 = i+bs;    i1>N && break
            i2 = i+2bs-1; i2 = min(i2, N)
            let
                src₁ = @view from[i:i1-1]
                src₂ = @view from[i1:i2]
                dest = @view to[i:i2]
                DataFlowTasks.@spawn merge!(@W(dest), @R(src₁), @R(src₂)) label="merge\n$i:$i2"
            end
            i = i2+1
        end
        if i <= N
            let
                src  = @view from[i:N]
                dest = @view to[i:N]
                DataFlowTasks.@spawn @W(dest) .= @R(src) label="copy\n$i:$N"
            end
        end

        bs *= 2
        (from, to) = (to, from)
    end

    final_task = DataFlowTasks.@spawn @R(from) label="result"
    fetch(final_task)
    v === from || copy!(v, from)
    v
end

@assert mergesort_dft!(copy(v), buf) == sort(v)

# Task graph

resize!(DataFlowTasks.get_active_taskgraph(), 2000)
log_info = DataFlowTasks.@log mergesort_dft!(copy(v))

using GraphViz
dag = GraphViz.Graph(log_info)
DataFlowTasks.savedag("sort_dag.svg", dag) #src

# ## Performance

N = 1_000_000
v = rand(N);
buf = similar(v);

using BenchmarkTools
bench_seq = @benchmark mergesort!(x, $buf) setup=(x=copy(v)) evals=1

#-

bench_dft = @benchmark mergesort_dft!(x, $buf) setup=(x=copy(v)) evals=1

#-

(;
 nthreads = Threads.nthreads(),
 speedup = time(minimum(bench_seq)) / time(minimum(bench_dft)))

#-

log_info = DataFlowTasks.@log mergesort_dft!(copy(v))
DataFlowTasks.describe(log_info, categories=["sort", "merge", "copy", "result"])

#-

using CairoMakie
plot(log_info, categories=["sort", "merge", "copy", "result"])
