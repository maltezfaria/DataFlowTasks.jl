```@meta
CurrentModule = DataFlowTasks
```
# DataFlowTasks

*Tasks which automatically respect data-flow dependencies*

## Basic usage

This package defines a `DataFlowTask` type which behaves very much like a Julia
`Task`, except that it allows the user to specify explicit *data dependencies*.
This information is then be used to automatically infer *task dependencies* by
constructing and analyzing a directed acyclic graph based on how
tasks access the underlying data. The premise is that it is sometimes simpler to
specify how *tasks depend on data* than to specify how *tasks depend on each
other*.


The use of a `DataFlowTask` is intended to be as similar to a native `Task` as
possible. The API revolves around three macros:

- [`@dtask`](@ref)
- [`@dspawn`](@ref)
- [`@dasync`](@ref)

They behave like their `Base` counterparts (`@task`, `Threads.@spawn`
and `@async`), but additional annotations specifying explicit *data
dependencies* are required. The example below shows the most basic usage:

```@example simple-example
using DataFlowTasks # hide

A = ones(5)
B = ones(5)
d = @dspawn begin
    @RW A   # A is accessed in READWRITE mode
    @R  B   # B is accessed in READ mode
    A .= A .+ B
end

fetch(d)
```

This creates (and schedules for execution) a `DataFlowTask` `d`
which accesses `A` in `READWRITE` mode, and `B` in `READ` mode. The benefit of
`DataFlowTask`s comes when you start to compose operations which may mutate the
same data:

```@example simple-example
using DataFlowTasks # hide

n = 100_000
A = ones(n)

d1 = @dspawn begin
    @RW A

    # in-place work on A
    for i in eachindex(A)
        A[i] = log(A[i]) # A[i] = 0
    end
end

# reduce A
d2 = @dspawn sum(@R A)
# The above is a shortcut for:
#   d2 = @dspawn begin
#       @R A
#       sum(A)
#   end


c = fetch(d2) # 0
```

We now have two asynchronous tasks being created, both of which access the array
`A`. Because `d1` writes to `A`, and `d2` reads from it, the outcome `C` is
nondeterministic unless we specify an order of precedence. `DataFlowTasks`
reinforces the **sequential consistency** criterion, which is to say that
executing tasks in parallel must preserve, up to rounding errors, the result
that would have been obtained if they were executed sequentially (i.e. `d1` is
executed before `d2`, `d2` before `d3`, and so on). In this example, this means
`d2` will always wait on `d1` because of an inferred data dependency. The
outcome is thus always zero.

!!! note
    If you replace `@dspawn` by `Threads.@spawn` in the example above (and pick
    an `n` large enough) you will see that you no longer get `0` because `d2`
    may access an element of `A` before it has been replaced by zero!

!!! tip
    In the `d2` example above, a shortcut syntax was introduced, which
    allows putting `READ`/`WRITE` annotations directly around arguments in a
    function call. This is especially useful when the task body is a one-liner.

No parallelism was allowed in the previous example due to a data conflict. To
see that when parallelism is possible, spawning `DataFlowTask`s will exploit it,
consider this one last example:

```@example simple-example
using DataFlowTasks # hide

n = 100
A = ones(n)

d1 = @dspawn begin
    @W A

    # write to A
    sleep(1)
    fill!(A,0)
end

d2 = @dspawn begin
    @R A

    # some long computation 
    sleep(5)
    # reduce A
    sum(A)
end

# another reduction on A
d3 = @dspawn sum(x->sin(x), @R(A))

t = @elapsed c = fetch(d3)

t,c 
```

We see that the elapsed time to `fetch` the result from `d3` is on the order of
one second. This is expected since `d3` needs to wait on `d1` but can be
executed concurrently with `d2`. The result is, as expected, `0`.

All examples this far have been simple enough that the dependencies between the
tasks could have been inserted *by hand*. There are certain problems, however,
where the constant reuse of memory (mostly for performance reasons) makes a
data-flow approach to parallelism a rather natural way to implicitly describe
task dependencies. This is the case, for instance, of tiled (also called
blocked) matrix factorization algorithms, where task dependencies can become
rather difficult to describe in an explicit manner. The [tiled factorization section](@ref
tiledcholesky-section) showcases some non-trivial problems for which
`DataFlowTask`s may be useful.

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
to say, we must know if *mutating* A can affect `B`, or vice-versa.
Obviously, without any further information on the types of `A` and `B`, this is
an impossible question.

To get around this challenge, you must `import` and extend the
[`memory_overlap`](@ref) method to work on any pair of elements `A` and `B` that
you wish to use. The examples in the previous section worked because
these methods have been defined for some basic `AbstractArray`s:

```@example
using DataFlowTasks: memory_overlap

A = rand(10,10)
B = view(A,1:10)
C = view(A,11:20)

memory_overlap(A,B),memory_overlap(A,C),memory_overlap(B,C)
```

By default, `memory_overlap` will return `true` and print a warning if it does
not find a specialized method:

```@repl memory-overlap
using DataFlowTasks: memory_overlap

struct CirculantMatrix
    data::Vector{Float64}
end

v = rand(10);
M = CirculantMatrix(v);

memory_overlap(M,copy(v))
```

Extending the `memory_overlap` will remove the warning, and produce a more
meaningful result:

```@repl memory-overlap
import DataFlowTasks: memory_overlap

# overload the method
memory_overlap(M::CirculantMatrix,v) = memory_overlap(M.data,v)
memory_overlap(v,M::CirculantMatrix) = memory_overlap(M,v)

memory_overlap(M,v), memory_overlap(M,copy(v))
```

You can now `spawn` tasks with your custom type `CirculantMatrix` as a data dependency, and things
should work as expected:

```@repl memory-overlap
using DataFlowTasks

v  = ones(5);
M1 = CirculantMatrix(v);
M2 = CirculantMatrix(copy(v));

Base.sum(M::CirculantMatrix) = length(M.data)*sum(M.data)

d1 = @dspawn begin
    @W v
    sleep(0.5)
    fill!(v,0) 
end;
d2 = @dspawn sum(@R M1)
d3 = @dspawn sum(@R M2)

fetch(d3) # 25

fetch(d2) # 0
```

## Scheduler

When loaded, the `DataFlowTasks` package will initialize an internal scheduler
(of type [`JuliaScheduler`](@ref)), running on the background, to handle
implicit dependencies of the spawned `DataFlowTask`s. In order to retrieve the
current scheduler, you may use the [`getscheduler`](@ref) method:

```@example scheduler
using DataFlowTasks # hide
DataFlowTasks.sync() # hide
sch = DataFlowTasks.getscheduler()
```

The default scheduler can be changed through [`setscheduler!`](@ref).

There are two important things to know about the default `JuliaScheduler` type. First,
it contains a buffered `dag` that can handle up to `sz_max` nodes: trying to
`spawn` a task when the `dag` is full will block. This is done to keep the cost
of analyzing the data dependencies under control, and it means that a
full/static `dag` may in practice never be constructed. You can modify the
buffer size as follows:

```@example scheduler
resize!(sch.dag,50)
```

Second, when the computation of a `DataFlowTask` `ti` is completed, it gets
pushed into a `finished` channel, to be eventually processed and `pop`ed from the `dag` by
the `dag_worker`. This is done to avoid concurrent access to the `dag`: only the
`dag_worker` should modify it. If you want to stop nodes from being removed from the `dag`,
you may stop the `dag_worker` using:

```@example scheduler
DataFlowTasks.stop_dag_worker(sch)
```

Finished nodes will now remain in the `dag`:

```@example scheduler
using DataFlowTasks: R,W,RW, num_nodes
A = ones(5)
@dspawn begin 
    @RW A
    A .= 2 .* A
end
@dspawn sum(@R A)
sch
```

Note that stopping the `dag_worker` means `finished` nodes are no longer removed
from the `dag`; since the `dag` is a buffered structure, this may cause the
execution to halt if the `dag` is at full capacity. You can then either
`resize!` it, or simply start the worker (which will result in the processing of
the `finished` channel):

```@example scheduler
DataFlowTasks.start_dag_worker(sch)
sch
```

!!! tip
    There are situations where you may want to change the default scheduler
    temporarily to execute a block of code, and revert to the default scheduler
    after. This can be done using the [`with_scheduler`](@ref) method. 


## Logging

TODO

## Similarities and differences with `Dagger.jl`
Dagger is a package for parallel computing that is meant to be `flexible` and easy to use. It's supposed to help the parallelization of a complex serial code without the need to refactor everything. It uses a `functionnal` paradigm to imply dependencies between tasks, so they are not to be thought by the user. An exemple from Dagger.jl's documentation :
```@example
p = Dagger.@spawn add1(4)
q = Dagger.@spawn add2(p)
r = Dagger.@spawn add1(3)
s = Dagger.@spawn combine(p, q, r)
```
The result of the first task will be stored in `p`, and Dagger detects that `q` needs `p` to run, etc.. So the dependencies are automatically computed, and gives the next DAG :  
![Dagger's DAG](DaggersDag.png)  
Under the hood, what's happening is we don't manipulate numbers, and matrices, but `EagerThunks`. After the fisrt line, `p` has become an EagerThunk, a sort of task carrying all the informations needed by Dagger.  
Because we now know the dependencies between all tasks, we can give that to a scheduler (Dagger.jl implements his own), and give those tasks to different cores.  
Dagger.jl's abstraction handles multi-threading and `distributed` parallel computing.  
Like Dask, Dagger.jl comes with it's own data structures, mainly `DArrays`, for distributed memory computing.  
So the main points that separate DataFlowTasks and Dagger are :
* Dependencies are not implied by variable names, but by variable's associated memory. With DataFlowTasks we still handles our numbers, matrices etc, rather than a new data structure (EagerThunks).
* DataFlowTasks doesn't support distributed parallel computing (for now)
* DataFlowTasks doesn't use a functionnal paradigm
* DataFlowTasks uses the Julia default scheduler (for now).

DataFlowTasks is oriented towards linear algebra matrix computations, let's see how it can be prefered as Dagger.jl in that case by looking at a cholesky tiled factorization algorithm. Will consider our matrix `A` already divided in blocks, where `Aij` represents the block at index `(i,j)`.  
The pseudo-code for this algorithm would be :
```@example
`Requires` : A of size m*n 
for i in 1:m
    Aii <- cholesky(Aii)
    for j in i+1:m
        Aij <- Aii \ Aij
    end
    for j in i+1:m
        for k in j:n
            Ajk <- schurcomplement(Ajk, Aji, Aik)
        end
    end
end
```

This pseudo-code mimics the functionnal behaviour of Dagger.jl with `Aii <- cholesky(Aii)`. Yet, in this code, we'll only use a couple of variables names : `Aii`, `Aij`, `Ajk` etc... that will represent, depending on the iteration, a different matrix block.  
To illustrate the problem :
```@example
p = Dagger.@spawn add1(4)
p = Dagger.@spawn add2(2)
q = Dagger.@spawn add1(p)
```
Here the first task is shadowed by second, q will only wait for the second task.  
Therefore in the cholesky tiled factorization, we have to have a single variable name for every block of memory. Before computing anything we have to change our paradigm : we can't manipulate blocks of memory, we have to manipulate `Eagerthunks` previously mapped to blocks of memory.
```@example
# Map thunks to blocks of memory
thunks = Matrix{Dagger.EagerThunk}(undef, m, n)

# Work on thunks
for i in 1:m
    thunks[i, i] = Dagger.@spawn cholesky(thunks[i, i])
    ...
end

# Reverse mapping from thunks to blocks of memory
for i in 1:m, j in i:n
    Aij .= fetch(thunks[i, j])
end
```

We see how here it is more natural to reason on memory dependency, rather than on variables names. The DataFlowTasks cholesky tiled factorization would look more similar to the pseudo-code above :
```@example
for i in 1:m
    @dpsawn cholesky!(@RW(Aii))
    for j in i+1:m
        @dspawn ldiv!(@R(L), @RW(Aij))
    end
    for j in i+1:m
        for k in j:n
            @dspawn matmul!(@RW(Ajk), @R(Aji), @R(Aik))
        end
    end
end
```

!!! TO DO : PERFORMANCE DIFFERENCES !!!


## Limitations

Some current limitations are listed below:

- At present, errors are rather poorly handled. The only way to know if a task
  has failed is to manually inspect the `dag`
- There is no way to specify priorities for a task.
- The main thread executes tasks, and is responsible for adding/removing nodes
  from the `dag`. This may hinder parallelism if the main thread is given a long
  task since the processing of the dag will halt until the main thread becomes
  free again.
- ...
