# [Debugging & Profiling](@id visualization-section)

`DataFlowTasks` defines two visualization tools that help when debugging and
profiling parallel programs:

- a visualization of the Directed Acyclic Graph (DAG) internally representing
  task dependencies;
- a visualization of how tasks were scheduled during a run, alongside with other
  information helping understand what limits the performances of the computation.

!!! note "Weak dependencies"

    Visualization tools require additional dependencies (such as `Makie` or
    `GraphViz`) which are only needed during the development stage. We are
    therefore only declaring those as *weak dependencies*: the corresponding
    features are loaded together with these packages (e.g. with `using
    GraphViz`), which must be available in the environment you are working in.

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
log_info = DataFlowTasks.@log work(A, B)
```

The `log_info` object above, of [`LogInfo`](@ref DataFlowTasks.LogInfo) type,
contains information that can be used to reconstruct both the inferred task
dependencies, and the parallel execution traces of the `DataFlowTask`s. A
summary of this information can be displayed using [`DataFlowTasks.describe`](@ref), as
illustrated next:

```@example profiling
DataFlowTasks.describe(log_info; categories=["init", "mutate", "read"])
```

More powerful visualization capabilities, such as displaying the underlying
`DAG` or showing the parallel trace of the tasks executed, are available upon
loading additional packages such as `GraphViz` or `Makie`. These are discussed
in the following sections, where we also explain in more detail the meaning of
the numbers output by [`DataFlowTasks.describe`](@ref).

!!! note "The logging window"

    `@log` records the *logging window*: it starts before running the code block,
    and ends once the code block has returned and all the `DataFlowTask`s spawned
    while logging are completed (even if they are not fetched). For each task, the
    time it actually spent *running* is measured separately from the time it spent
    descheduled (sleeping, waiting on I/O or on a lock...). See [Understanding the
    numbers](@ref understanding-the-numbers) for the meaning of the reported
    quantities.

## DAG visualization

In order to better understand what this example does, and check that *data
dependencies* were suitably annotated, it can be useful to look at the Directed
Acyclic Graph (DAG) representing *task dependencies* as they were inferred by
`DataFlowTasks`. The DAG can be visualized by creating a
[`GraphViz.Graph`](@ref) out of it:

```@example profiling
using GraphViz
GraphViz.Graph(log_info)
```

When the working environment supports rich media, the DAG will be displayed
automatically. In other cases, it is possible to export it to an image using
[`DataFlowTasks.savedag`](@ref):

```@example profiling
dag = GraphViz.Graph(log_info)
DataFlowTasks.savedag("profiling-example.svg", dag)
nothing # hide
```

Note how the task labels (which were provided as extra arguments to `@dspawn`)
are used in the DAG rendering and make it more readable. In the DAG
visualization, the *critical path* is highlighted in red: it is the sequential
path that took the longest run time during the computation.

The DAG shows the complete dependencies between the logged tasks, including the
dependencies on tasks which had already finished when a task was inserted (the
scheduler does not keep track of those, since there is nothing left to wait
for). To compute them, a `LogInfo` keeps references to the data accessed by the
logged tasks until it is first analysed (e.g. by `describe` or `GraphViz.Graph`).

!!! note
    The run time of this critical path imposes a hard bound on parallel
    performances: no matter how many threads are available, it is not possible for
    the computation to take less time than the duration of the critical path.

## Scheduling and profiling information

The collected scheduling & profiling information can be visualized using
[`Makie.plot`](@ref) on the `log_info` object (note that using the `GLMakie`
backend brings a bit more interactivity than `CairoMakie`):

```@example profiling
using CairoMakie # or GLMakie to benefit from more interactivity
plot(log_info; categories=["init", "mutate", "read"])
```

The `categories` keyword argument allows grouping tasks in categories according
to their labels. In the example above, all tasks containing `"mutate"` in their
label will be grouped in the same category.

Note : be careful with giving similar labels. If tasks have "R" and "RW" labels,
and the substrings given to the plot's argument are also "R", and "RW", then all
tasks will be in the category "R" (because "R" can be found in "RW"). Regular
expressions can be given instead of substrings in order to avoid such issues.

Let us explore the various parts of this graph.

### Parallel Trace

The main plot (at the top) is the parallel trace visualization: each task is
shown as a bar on the thread where it started, from the moment its body started
to the moment it finished. The bar is shaded according to the fraction of that
time the task was actually running (see [the limitations of the parallel
trace](@ref trace-limitations)).

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

### Time: breakdown by activity

A barplot in the bottom left corner of the window gives us information on how
the time was spent (summed over all threads):

* `Running` represents the total time the tasks spent running (i.e. "useful"
  work);
* `Idle` represents the time the workers (the threads running the tasks) did not
  run any task, which may be due to bad scheduling, to a lack of exposed
  parallelism in the algorithm, or to the program not spawning tasks fast enough;
* `Blocked in tasks` represents the time the tasks spent descheduled during their
  body (sleeping, waiting on I/O or on a lock...);
* `Task insertion` represents the total time spent inserting nodes in the DAG
  (i.e. overhead induced by `DataFlowTasks`), on the threads calling `@dspawn`,
  possibly including any time spent in the GC if it is triggered by a memory
  allocation in the task insertion process.

### Elapsed time & bounds

A barplot in the bottom center of the window tries to present insightful
information about the elapsed (wall-clock) time of the computation, and its
limiting factors:

- `Elapsed` represents the measured "wall clock time" of the logging window; it
  is larger than both of the bounds described below;

- `Critical Path` represents the duration of the longest chain of dependent
  tasks in the DAG (shown in red in the DAG visualization). As said above, it
  bounds the performance in that even infinitely many threads would still have
  to run this chain sequentially;

- `No-Wait` represents the duration of a hypothetical computation in which all
  the running time would be evenly distributed among the workers (i.e. no
  worker would ever have to wait). This also bounds the elapsed time because it
  does not account for dependencies between tasks.

When looking for faster response times, this graph may suggest sensible ways to
explore. If the measured time is close to the critical path duration, then
adding more threads will be of no help, but decomposing the work in smaller
tasks may be useful. On the other hand, if the measured time is close to the
"without waiting" bound, then adding more workers may reduce the wall clock time
and scale relatively well.

### Running time: breakdown by category

A barplot in the bottom right of the window displays a break-down of the total
running time (*i.e.* the total time spent on all threads while running
user-defined tasks), grouped by user-provided category as explained above.

When trying to optimize the sequential performance of the algorithm, this is
where one can get data about what actually takes time (and therefore could
produce large gains in performance if it could be optimized).

## [Understanding the numbers](@id understanding-the-numbers)

[`DataFlowTasks.describe`](@ref) and `Makie.plot` both report the quantities of
the [`LogSummary`](@ref DataFlowTasks.LogSummary) computed by
[`DataFlowTasks.summarize`](@ref). Each of them has a single definition:

| Quantity              | Definition                                                                 |
|:--------------------- |:-------------------------------------------------------------------------- |
| Elapsed time ``E``    | wall-clock time of the logging window                                      |
| Workers ``P``         | number of threads running the tasks (the `:default` threadpool)            |
| Worker time           | ``P \cdot E``, the time the workers were available                        |
| Running ``W``         | total time the tasks spent running (from Julia's task metrics)             |
| Idle                  | ``P \cdot E - W``, the time the workers did not run any task              |
| Tasks blocked         | total time the tasks spent descheduled during their body                   |
| Task insertion        | total time spent inserting tasks, on the threads calling `@dspawn`         |
| Critical path         | wall time of the longest chain of dependent tasks                          |
| No-wait               | ``W / P``                                                                  |

Both the critical path and the no-wait time are lower bounds of the elapsed
time. The tasks run on the `:default` threadpool, while `@dspawn` (and therefore
the insertion of the tasks) runs on the thread of its caller, which is often
the interactive thread.

Let us look at a few simple cases to see these numbers at work. The tasks below
either compute (`busy`), or sleep:

```@example numbers
using DataFlowTasks, CairoMakie
busy(t) = (t₀ = time(); while time() - t₀ < t end)
xs = [zeros(1) for _ in 1:2Threads.nthreads()]
DataFlowTasks.@log fetch(@dspawn busy(0.01)) # compile
nothing # hide
```

Tasks which only sleep do not run: the workers are idle, and the time the tasks
spend sleeping is reported as blocked.

```@example numbers
log_info = DataFlowTasks.@log for x in xs
    @dspawn (@W(x); sleep(0.1)) label = "sleep"
end
DataFlowTasks.describe(log_info)
```

Tasks which compute and then sleep run half of the time. While a task sleeps,
its thread runs another task:

```@example numbers
log_info = DataFlowTasks.@log for x in xs
    @dspawn (@W(x); busy(0.05); sleep(0.05)) label = "half"
end
DataFlowTasks.describe(log_info)
```

```@example numbers
plot(log_info; categories = ["half"])
```

Finally, the logging window includes the work done by the program itself, here
before spawning any task:

```@example numbers
log_info = DataFlowTasks.@log begin
    busy(0.2)
    for x in xs
        @dspawn (@W(x); busy(0.05)) label = "work"
    end
end
DataFlowTasks.describe(log_info)
```

### [Limitations of the parallel trace](@id trace-limitations)

Julia measures the time each task spends running, but not *when* it is
descheduled and resumed. Therefore, in the parallel trace:

- a task which is descheduled is shaded according to the fraction of its
  duration it was running, but the moments it was not running are not shown;
- while a task is descheduled, its thread may run other tasks, so that the bars
  of several tasks may overlap (as in the second example above);
- a task which is descheduled may resume on another thread: it is shown on the
  thread where it started.
