```@meta
DocTestSetup  = quote
    using HScheduler
end
```
# HScheduler

*Documentation goes here.*


## Example blocks

### Script: @example

```@example
import Random   # hide
Random.seed!(1) # hide
A = rand(3, 3)
b = [1, 2, 3]
A \ b
```

### REPL: @repl

```@repl
1 + 1
```

## Documentation tests

### Script

```jldoctest
a = 1
b = 2
a + b

# output

3
```

### REPL

```jldoctest
julia> a = 1
1

julia> b = 2;

julia> c = 3;  # comment

julia> a + b + c
6
```

## Reference

### @autodocs

```@autodocs
Modules = [HScheduler]
Order   = [:function, :type]
```
