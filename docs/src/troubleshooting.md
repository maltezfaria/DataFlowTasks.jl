# Troubleshooting / known issues

## Suggested workflow

Writing parallel code is hard, specially when it involves shared memory. While
`DataFlowTasks` tries to alleviate some of the burden, it comes with its own
sharp corners. A suggested workflow for writing parallel code with
`DataFlowTasks` is the following:

1. Write the serial code, make sure it works. This may sound obvious, but it is
   easy to get carried away with the parallelization and forget this crucial
   step!
2. Add [`@dspawn`](@ref) to the chunks of your code that you want to run in
   parallel. If it works as expected, you are an awesome programmer! But then,
   probably you would not be reading this section, if that were the case, so
   let's assume that you run into some issues.
3. Run [`DataFlowTasks.force_sequential`](@ref)`(true)` and try your code again. This will
   make `@dspawn` a no-op, and if your sequential code worked, it should work.
4. Enable `@dspawn` again with `force_sequential(false)`, and run
   [`DataFlowTasks.force_linear_dag`](@ref)`(true)`. This makes sure
   `DataFlowTask`s are created and schedule, but it forces the underlying `DAG`
   to be linear (i.e. node `i` is always connected to node `i+1`). This is
   closer to the *real thing* than `force_sequential` since closures are created
   and variables are capture in the task bodies. If you have an issue here,
   consider reading the following section on [captured variables](@ref
   troubleshooting-captures).
5. Deactivate the `force_linear_dag(false)` and see results are correct. If they
   are not, the problem is likely related to incorrectly declared data
   dependencies in your `@dspawn` blocks. Look at the code, scratch your head,
   and continue debugging...

## [Tricky behavior of captured variables](@id troubleshooting-captures)

It is easy to forget that `DataFlowTasks.@dspawn`, like its siblings `@async` or
`Threads.@spawn`, wraps its body in an anonymous function. This can lead to
unexpected behavior when variables are captured in these closures at task spawn
time, and re-bound before task execution time.

Let's illustrate this with a simple example using plain asynchronous tasks. In
the following snippet, the intention is to start with an initial array, double
all elements and copy them to a temporary buffer, then double them again and
copy them back to the original array:

```@example
arr = ones(3)
buf = fill(NaN, length(arr))

# The following is performed at "task spawn time"
begin
    # Warning: these variable bindings will be captured in the task body
    (from, to) = (arr, buf)
    task1 = @task to .= 2 .* from
    
    # Swap source & destination arrays:
    # Warning: this re-binds the captures in t1
    (from, to) = (to, from)
    task2 = @task begin
        wait(task1) # make sure the data has been copied before copying it back
        to .= 2 .* from
    end
end

# This is "task run time"
foreach(schedule, (task1, task2))
wait(task2)

arr  # expected all 4 after the round-trip
```

There is however a subtle issue in the code above: the body of `task1` captures
*bindings* `from` and `to` (not their *values* at task spawn time). Therefore,
when `from` and `to` are later re-bound, this affects the captures in
`task1`. If `task1` starts afterwards (which we ensure here by only scheduling
it later), it "sees" the swapped version of `from` and `to`, and therefore
copies `NaN`s into the original array.

!!! note

    In a real code, one would probably schedule the task as soon as it is created
    (using `@async`, `Threads.@spawn` or `DataFlowTasks.@dspawn`). In such cases, the
    result may vary from run to run, depending on whether the task actually starts
    before the bindings are swapped, or not.

The fix for such problems usually involves using `let`-blocks to ensure that
task bodies only capture local variables (or at least no variable that is
susceptible to be rebound later). For example, the following implementation is
safe:

```@example
arr = ones(3)
buf = fill(NaN, length(arr))

# The following is performed at "task spawn time"
begin
    (from, to) = (arr, buf)
    
    # Thanks to the let-block, the task body captures local bindings
    task1 = let (src, dest) = (from, to)
        @task dest .= 2 .* src
    end

    # Swap source & destination arrays
    # This rebinds `from` and `to`, but does not affect the captures in task1
    (from, to) = (to, from)
    task2 = let (src, dest) = (from, to)
        @task begin
            wait(task1)
            dest .= 2 .* src
        end
    end
end

# This is "task run time"
foreach(schedule, (task1, task2))
wait(task2)

arr  # expect all 4 after the round-trip
```

!!! note
    The [Parallel Merge Sort example](@ref example-sort) shows a real-world
    situation in which such issues could arise.

## [Nested task graph](@id nested-tasks)

It may sometimes be useful, or even necessary, to spawn a `DataFlowTask` inside
another. This, although possible, can be a bit tricky to get right. To
understand why that is the case, let us walk through a simple example:

```@example nested-tasks

using DataFlowTasks

function nested_tasks()
    A,B = ones(10), ones(10)
    @dspawn begin
        sleep(0.1)
        @RW A B
        @dspawn begin
            @RW(view(A,1:5)) .= 0
        end label = "1a"
        @dspawn begin
            @RW(view(A,6:10)) .= 0 
        end label = "1b"
        B .= 0
    end label = "1"
    res = @dspawn begin
        (sum(@R(A)),sum(@R(B))) 
    end label = "2"
    fetch(res)
end

```

If we were to disable `@dspawn` (make it a `no-op`) in the code above, the
sequential execution would proceed as follows:

1. `A` and `B` are initialized to ones.
2. After a small nap, `A[1:5]` is filled with `0` in block `1a`
3. `A[6:10]` is filled with `0` in block `1b`
4. A reduction of both `A` and `B` is performed in block `2`, yielding `(0.,0.)`

The sequential code will therefore *always* yield `(0.,0.)`, and that could be
considered the *correct* answer as per a *sequential consistency* criterion. We
can check that this is actually the case by running
[`DataFlowTasks.force_sequential()`](@ref) before executing the code:

```@example nested-tasks
DataFlowTasks.force_sequential(true)
nested_tasks()
```

If you reactivate `DataFlowTasks` and re-run the code above a few times,
however, you will notice that summing `B` will always give `0`, but summing `A`
will not

```@example nested-tasks
DataFlowTasks.force_sequential(false)
map(i -> nested_tasks(), 1:10)
```

The reason is that while we are guaranteed that task `2` will be created *after*
task `1`, we don't have much control on when tasks `1a` and `1b` will be created
relative to task `2`. Because of that, while `2` will always wait on `1` before
running due to the data conflict, `2` could very well be spawned *before* `1a`
and/or `1b`, in which case it won't wait for them! The result of `sum(A)`,
therefore, is not deterministic in our program.

The problem is that if we allow for several paths of execution to `spawn`
`DataFlowTask`s on the same task graph concurrently, the order upon which these
tasks are added to the task graph is impossible to control. This makes the
*direction of dependency* between two tasks `ti` and `tj` with conflicting data
accesses undetermined: we will infer that `ti` depends on `tj` if `ti` is created
first, and that `tj` depends on `ti` if `tj` is created first.

One way to resolve this ambiguity in the example above is to modify function to
avoid nested tasks. For this admittedly contrived example, we could have written
instead:

```@example nested-tasks
function linear_tasks()
    A,B = ones(10), ones(10)
    sleep(0.1)
    @dspawn begin
        @RW(view(A,1:5)) .= 0
    end label = "1a"
    @dspawn begin
        @RW(view(A,6:10)) .= 0 
    end label = "1b"
    @dspawn @W(B) .= 0 label = "1"
    res = @dspawn begin
        (sum(@R(A)),sum(@R(B))) 
    end label = "2"
    fetch(res)
end
@show linear_tasks()
```

You can check that the code above will consistently yield `(0.,0.)` as a result.

When nesting tasks is unavoidable, or when the performance hit from *flattening
out* our nested algorithm is too large, a more advanced option is to create a
*separate task graph* for each level of nesting. That way we manually handle the
logic, and recover a predictable order in each task graph:

```@example nested-tasks
using DataFlowTasks: TaskGraph, with_taskgraph

function nested_taskgraphs()
    A,B = ones(10), ones(10)
    @dspawn begin
        sleep(0.1)
        @RW A B
        tg = TaskGraph() # a new taskgraph
        with_taskgraph(tg) do
            @dspawn begin
                @RW(view(A,1:5)) .= 0
            end label = "1a"
            @dspawn begin
                @RW(view(A,6:10)) .= 0 
            end label = "1b"
        end
        wait(tg)
        B .= 0
    end label = "1"
    res = @dspawn begin
        (sum(@R(A)),sum(@R(B))) 
    end label = "2"
    fetch(res)
end
nested_taskgraphs()
```

In this last solution, there are two task graphs: the *outer* one containing
tasks `1` and `2`, and an *inner* one, created by task `1`, which spawns tasks
`1a` and `1b`. The inner task graph is waited on by task `1`, so that task `2`
will only start after both `1a` and `1b` have completed. Note that because a new
task graph is created for `1a` and `1b`, they will never depend on task `2`,
which could create a deadlock!

In the future we may provide a more convenient syntax for creating nested task;
at present, the suggestion is to avoid them if possible.
