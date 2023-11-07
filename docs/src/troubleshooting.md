# Troubleshooting / known issues

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
