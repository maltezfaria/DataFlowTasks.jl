```@meta
CurrentModule = DataFlowTasks
```
# DataFlowTasks

*Tasks which automatically respect data-flow dependencies*

## Basic usage

This package defines a [`@spawn`](@ref) macro type which behaves very much like
`Threads.@spawn`, except that it allows the user to specify explicit *data
dependencies* for the spawned `Task`. This information is then be used to
automatically infer *task dependencies* by constructing and analyzing a directed
acyclic graph based on how tasks access the underlying data. The premise is that
it is sometimes simpler to specify how *tasks depend on data* than to specify
how *tasks depend on each other*.

When creating a `Task` using [`DataFlowTasks.@spawn`](@ref), the following
annotations can be used to declare how the `Task` accesses the data:

- read-only: `@R` or `@READ`
- write-only: `@W` or `@WRITE`
- read-write: `@RW` or `@READWRITE`

An `@R(A)` annotation for example implies that *data* `A` will be accessed in
read-only mode by the *task*. Here is a simple example:

```@example simple-example
using DataFlowTasks: @spawn

n = 100_000
A = ones(n)

d1 = @spawn begin
    @RW A

    # in-place work on A
    for i in eachindex(A)
        A[i] = log(A[i]) # A[i] = 0
    end
end

# reduce A
d2 = @spawn sum(@R A)
# The above is a shortcut for:
#   d2 = @spawn begin
#       @R A
#       sum(A)
#   end

c = fetch(d2) # 0
```

Two (asynchronous) tasks were created, both of which access the array `A`.
Because `d1` writes to `A`, and `d2` reads from it, the outcome `C` is
nondeterministic unless we specify an order of precedence. `DataFlowTasks`
reinforces the **sequential consistency** criterion, which is to say that
executing tasks in parallel must preserve, up to rounding errors, the result
that would have been obtained if they were executed sequentially, following the
order in which they were created. In the example above, this means `d2` will
wait on `d1` because of an inferred data dependency. The outcome is thus always
zero.

!!! note
    If you replace `DataFlowTasks.@spawn` by `Threads.@spawn` in the example above (and pick
    an `n` large enough) you will see that you no longer get `0` because `d2`
    may access an element of `A` before it has been replaced by zero!

!!! tip
    In the `d2` example above, a shortcut syntax was introduced, which
    allows putting access mode annotations directly around arguments in a
    function call. This is especially useful when the task body is a one-liner.
    See [`@spawn`](@ref) for an exhaustive list of supported ways to create
    tasks and specify data dependencies.

No parallelism was allowed in the previous example due to a data conflict. To
see that when parallelism is possible, `DataFlowTasks` will exploit it,
consider this one last example:

```@example simple-example
using DataFlowTasks: @spawn

function run(A)
    d1 = @spawn begin
        @W A # write to A
        sleep(1)
        fill!(A,0)
    end

    # a reduction on A
    d2 = @spawn begin
        @R A # read from A
        sleep(10)
        sum(A)
    end

    # another reduction on A
    d3 = @spawn sum(@R(A))

    t = @elapsed c = fetch(d3)

    @show t,c
end

A = ones(10)
run(A)
```

We see that the elapsed time to `fetch` the result from `d3` is on the order of
one second. This is expected since `d3` needs to wait on `d1` but can be
executed concurrently with `d2`. The result is, as expected, `0`.

All examples this far have been simple enough that the dependencies between the
tasks could (and probably should) have been inserted *by hand*. There are
certain problems, however, where the constant reuse of memory (mostly for
performance reasons) makes a data-flow approach to parallelism a rather natural
way to implicitly describe task dependencies. This is the case, for instance, of
tiled (also called blocked) matrix factorization algorithms, where task
dependencies can become rather difficult to describe in an explicit manner. The
[tiled factorization section](@ref tiledcholesky-section) showcases some
non-trivial problems for which `DataFlowTask`s may be useful.

!!! tip
    The main goal of `DataFlowTask`s is to expose parallelism: two tasks `ti`
    and `tj` can be executed concurrently if one does not write to memory that
    the other reads. This data-dependency check is done *dynamically*, and
    therefore is not limited to tasks in the same lexical scope. Of course,
    there is an overhead associated with these checks, so whether performance
    gains can be obtained depend largely on how parallel the algorithm is, as
    well as how long each individual task takes (compared to the overhead).

## Custom types

In order to infer dependencies between `DataFlowTask`s, we must be able to
determine whether two objects `A` and `B` share a common memory space. That is
to say, we must know if *mutating* `A` can affect `B`, or vice-versa. This check
is performed by the [`memory_overlap`](@ref) function:

```@example
using DataFlowTasks: memory_overlap

A = rand(10,10)
B = view(A,1:10)
C = view(A,11:20)

memory_overlap(A,B), memory_overlap(A,C), memory_overlap(B,C)
```

The example above works because `memory_overlap` has been defined for some basic
`AbstractArray`s types inside `DataFlowTasks`. If a specialized method for
`memory_overlap` is not found, `DataFlowTasks` errs on the safe side and falls
back to a generic implementation that always returns `true`:

```@repl memory-overlap
using DataFlowTasks: memory_overlap

struct CirculantMatrix # a custom type
    data::Vector{Float64}
end

v = rand(10);
M = CirculantMatrix(v);

memory_overlap(M,copy(v))
```

The warning message printed above hints at what should be done:

```@repl memory-overlap
import DataFlowTasks: memory_overlap
memory_overlap(M::CirculantMatrix,v) = memory_overlap(M.data,v) # overload
memory_overlap(v,M::CirculantMatrix) = memory_overlap(M,v)
memory_overlap(M,v), memory_overlap(M,copy(v))
```

You can now `spawn` tasks with your custom type `CirculantMatrix` as a data
dependency, and things should work as expected:

```@example memory-overlap
using DataFlowTasks: @spawn

v  = ones(5);
M1 = CirculantMatrix(v);
M2 = CirculantMatrix(copy(v));

Base.sum(M::CirculantMatrix) = length(M.data)*sum(M.data)

d1 = @spawn begin
    @W v
    sleep(0.5)
    fill!(v,0) 
end;
d2 = @spawn sum(@R M1)
d3 = @spawn sum(@R M2)

fetch(d3) # 25
fetch(d2) # 0

nothing # hide
```

## Task graph

Each time a `Task` is spawned using `DataFlowTasks.@spawn`, it is added to an
internal `TaskGraph` (see [`get_active_taskgraph`](@ref)) so that its
data-dependencies can be tracked and analyzed. There are two important things to
know about `TaskGraph` objects. First, they are buffered to handle at most
`sz_max` tasks at a time: trying to add a task to the `TaskGraph` when it is
full will block. This is done to keep the cost of analyzing the data
dependencies under control. You can modify the buffer size as follows:

```@example scheduler
using DataFlowTasks # hide
taskgraph = DataFlowTasks.get_active_taskgraph()
resize!(taskgraph,200)
```

Second, when the computation of a task in the `TaskGraph` is completed, it gets
pushed into a `finished` channel, to be eventually processed and `pop`ed from
the graph by the `dag_cleaner`. This is done to avoid concurrent access to the
DAG: only the `dag_cleaner` should modify it. If you want to stop nodes from
being removed from the DAG, you may stop the `dag_cleaner` using:

```@example scheduler
DataFlowTasks.stop_dag_cleaner(taskgraph)
```

Finished nodes will now remain in the DAG:

```@example scheduler
A = ones(5)
DataFlowTasks.@spawn begin 
    @RW A
    A .= 2 .* A
end
DataFlowTasks.@spawn sum(@R A)
taskgraph
```

Note that stopping the `dag_cleaner` means `finished` nodes are no longer
removed; since the task graph is a buffered structure, this may cause the
execution to halt if it is at full capacity. You can then either `resize!` it,
or simply start the worker (which will result in the processing of the
`finished` channel):

```@example scheduler
DataFlowTasks.start_dag_cleaner(taskgraph)
taskgraph
```

!!! tip
    There are situations where you may want to use a different `TaskGraph`
    temporarily to execute a block of code, and restore the default after. This
    can be done using the [`with_taskgraph`](@ref) method.

## Limitations

Some current limitations are listed below:

- There is no way to specify priorities for a task.
- The main thread executes tasks, and is responsible for adding/removing nodes
  from the DAG. This may hinder parallelism if the main thread is given a long
  task since the processing of the dag will halt until the main thread becomes
  free again.
- ...
