# [Debugging & Profiling](@id visualization-section)

`DataFlowTasks` defines two visualization tools that help when debugging and
profiling parallel programs:

- a visualization of the Directed Acyclic Graph (DAG) internally representing
  task dependencies;
- a visualization of how tasks were scheduled during a run, alongside with other
  information helping understand what limits the performances of the computation.

!!! note

    Visualization tools require additional dependencies (such as `Makie` or
    `GraphViz`) which are only needed during the development stage. We are
    therefore only declaring those as *optional dependencies* (using
    `Requires.jl`). The user can either set up a stacked
    environment in which these dependencies are available, or use the 
    [`DataFlowTasks.@using_opt`](@ref) macro which to handle the environment automatically.

Let's first introduce a small example that will help illustrate the features
introduced here:

```@example profiling
using DataFlowTasks

# Utility functions
init!(x)    = (x .= rand())     # Write
mutate!(x)  = (x .= exp.(x))    # Read+Write
result(x,y) = sum(x) + sum(y)   # Read

# Main work function
function work(A, B)
    # Initialization
    @dspawn init!(@W(A))               label="init A"
    @dspawn init!(@W(B))               label="init B"

    # Mutation
    @dspawn mutate!(@RW(A))            label="mutate A"
    @dspawn mutate!(@RW(B))            label="mutate B"

    # Final read
    res = @dspawn result(@R(A), @R(B)) label="read A,B"
    fetch(res)
end
```

## Creating a [`LogInfo`](@ref DataFlowTasks.LogInfo)

In order to inspect code which makes use of `DataFlowTask`s, you
can use the [`DataFlowTasks.@log`](@ref) macro to keep a trace of
the various parallel events and the underlying `DAG`. Note that to avoid
profiling the compilation time, it is often advisable to perform a "dry run" of
the code first, as done in the example below:

```@example profiling

# Context
A = ones(2000, 2000)
B = ones(3000, 3000)

# precompilation run
work(copy(A),copy(B)) 

# activate logging of events
logger = DataFlowTasks.@log work(A, B)
```

The `logger` object above, of [`LogInfo`](@ref DataFlowTasks.LogInfo) type, stores
various information that can be used to reconstruct both the inferred
dependencies and the parallel execution traces of the `DataFlowTask`s, as
illustrated next.

!!! warning
    When using `@log`, you typically want the block of code being benchmarked
    to wait for the completion of its `DataFlowTask`s before returning
    (otherwise the `LoggerInfo` object that is returned may lack information
    regarding the `DataFlowTask`s that have not been completed). In the example
    above, that was achieved through the use of `fetch` in the last line of the
    `work` function.

## DAG visualization

In order to better understand what this example does, and check that *data
dependencies* were suitably annotated, it can be useful to look at the Directed
Acyclic Graph (DAG) representing *task dependencies* as they were inferred by
`DataFlowTasks`. The DAG can be visualized with the [`plot_dag`](@ref
DataFlowTasks.plot_dag) function:

```@example profiling
DataFlowTasks.@using_opt GraphViz # or `using GraphViz` if your environment has it
DataFlowTasks.plot_dag(logger)
```

When the working environment supports rich media, the DAG will be displayed
automatically. In other cases, it is possible to export it to an image using
[`savedag`](@ref DataFlowTasks.savedag):

```@example profiling
g = DataFlowTasks.plot_dag(logger)
DataFlowTasks.savedag("profiling-example.svg", g)
nothing # hide
```

Note how the task labels (which were provided as extra arguments to `@dspawn`)
are used in the DAG rendering and make it more readable. In the DAG
visualization, the *critical path* is highlighted in red: it is the sequential
path that took the longest run time during the computation.

!!! note 

    The run time of this critical path imposes a hard bound on parallel
    performances: no matter how many threads are available, it is not possible for
    the computation to take less time than the duration of the critical path.


## Scheduling and profiling information

The collected scheduling & profiling information can be visualized in a graph
produced by the [`DataFlowTasks.plot_traces`](@ref) function (note that it requires a
`Makie` backend; using `GLMakie` brings a bit more interactivity than
`CairoMakie`) on the `logger` object:

```@example profiling
DataFlowTasks.@using_opt CairoMakie # or GLMakie to benefit from more interactivity
DataFlowTasks.plot_traces(logger; categories=["init", "mutate", "read"])
nothing # hide
```

![ProfilingExampleTrace](profiling_example.png)

The `categories` keyword argument allows grouping tasks in categories according
to their labels. In the example above, all tasks containing `"mutate"` in their
label will be grouped in the same category.

Note : be careful with giving similar labels. If tasks have "R" and "RW" labels,
and the substrings given to the plot's argument are also "R", and "RW", then all
tasks will be in the category "R" (because "R" can be found in "RW"). Regular
expressions can be given instead of substrings in order to avoid such issues.

Let us explore the various parts of this graph.

### Parallel Trace

The main plot (at the top) is the parallel trace visualization. In this example
there were two threads; we can see on which thread the task was run, and the
time it took.

Even though tasks are grouped in categories by considering substrings in their
labels, the full label is shown when hovering over a task in the interactive
visualization (i.e. when using `GLMakie` instead of `CairoMakie`).

The plot also shows the time spent inserting nodes in the graph (which is part
of the overhead incurred by the use of `DataFlowTasks`): these insertion times
are visualized as red tasks. They are not visible for such a small example, but
the interactive visualization allows zooming on the plot to search for those
small tasks.

Also note that inserting tasks into the graph involves memory allocations, and
may thus trigger garbage collector sweeps. When this happens, the time spent in
the garbage collector is also shown in the plot.

### Activity plot

The "activity" barplot (in the bottom left corner of the window) gives us
information on the break-down of parallel computing times (summed over all threads):

* `Computing` represents the total time spent in the tasks bodies (i.e. "useful"
  work);
* `Inserting` represents the total time spent inserting nodes in the DAG
  (i.e. overhead induced by `DataFlowTasks`), possibly including any time spent
  in the GC if it is triggered by a memory allocation in the task insertion process;
* `Other` represents the total idle time on all threads (which may be due to bad
  scheduling, or simply arise by lack of enough exposed parallelism in the
  algorithm).

### Time Bounds plot

The "Time Bounds" barplot (in the bottom center of the window) tries to present
insightful information about the performance limiting factors in the computation:

- `critical path` represents the time spent in the longest sequential path in
  the DAG (shown in red in the DAG visualization). As said above, it bounds the
  performance in that even infinitely many threads would still have to compute
  this path sequentially;
  
- `without waiting` represents the duration of a hypothetical computation in
  which all computing time would be evenly distributed among threads (i.e. no
  thread would ever have to wait). This also bounds the total time because it
  does not account for dependencies between tasks.
  
- `Real` represents the measured "wall clock time" of the computation; it should
  be larger than both of the aforementioned bounds.
  
When looking for faster response times, this graph may suggest sensible ways to
explore. If the measured time is close to the critical path duration, then
adding more threads will be of no help, but decomposing the work in smaller
tasks may be useful. On the other hand, if the measured time is close to the
"without waiting" bound, then adding more workers may reduce the wall clock time
and scale relatively well.

### Times per Category plot

The "Times per Category" barplot (in the bottom right of the window) displays
the total time spent on all threads while performing user-defined tasks (grouped
by category as explained above).

When trying to optimize the sequential performance of the algorithm, this is
where one can get data about what actually takes time (and therefore could
produce large gains in performance if it could be optimized).
