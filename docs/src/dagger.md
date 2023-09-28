# [Comparison with Dagger.jl](@id dagger-section)


## What's `Dagger.jl`

Dagger is a package for parallel computing, inspired by Python's Dask library, that is meant to be `flexible` and easy to use. It's supposed to help the parallelization of a complex serial code without the need to refactor everything. It uses a `functionnal` paradigm to easily imply dependencies between tasks, so they are not to be thought by the user. An example from Dagger.jl's documentation :  

```@julia
using Dagger

add1(value) = value + 1
add2(value) = value + 2
combine(a...) = sum(a)

p = Dagger.@spawn add1(4)
q = Dagger.@spawn add2(p)
r = Dagger.@spawn add1(3)
s = Dagger.@spawn combine(p, q, r)

@assert fetch(s) == 16
```  

The result of the first task will be stored in `p`, and Dagger detects that `q` needs `p` to run, etc.. So the dependencies are automatically computed, and give the next DAG :  

![Dagger's DAG](DaggersDag.png)  

Under the hood, what's happening is we don't manipulate numbers, and matrices, but `EagerThunks`. After the fisrt line, `p` has become an EagerThunk, a sort of task carrying all the informations needed by Dagger.

Because we now know the dependencies between all tasks, we can give that to a `scheduler` (Dagger.jl implements his own), and give those tasks to different cores.

Dagger.jl's abstraction handles `multi-threading` and `distributed` parallel computing.

Like Dask, Dagger.jl comes with it's own data structures, mainly `DArrays`, for distributed memory computing.


## Comparison

The main points that separate working with DataFlowTasks and Dagger are :
* The approach : dependencies are not implied by variable `names`, but by variable's associated `memory`.
* Data structure : data structures are not wrapped into a package's own data structure (EagerThunk).
* `Distributed` parallelism : not supported by DataFlowTasks. 
* Dagger use a `functionnal` paradigm.
* Scheduler : Dagger has it's own `scheduler`, where DataFlowTasks uses Julia's default one.
* `Performances` (see below)


## Case study

DataFlowTasks is oriented towards linear algebra matrix computations, let's see how it can be prefered as Dagger.jl in that case by looking at the cholesky tiled factorization algorithm. We'll consider our matrix `A` already divided in blocks, where `Aij` is a view of the block at index `(i,j)`.  
The pseudo-code for this algorithm would be :

```julia
Requires : A of size m*n 
for i in 1:m
    Aii <- cholesky(Aii)
    for j in i+1:m
        Aij <- ldiv(Aii,Aij)
    end
    for j in i+1:m
        for k in j:n
            Ajk <- schurcomplement(Ajk, Aji, Aik)
        end
    end
end
```

In the first place, we can see that Dagger.jl's functionnal paradigm behaves like what we are used to write in pseudo-code : `Aii <- cholesky(Aii)`. Usually though, code would written like : `cholesky!(Aii)`, the function modifying the variable.  

The problem here is that in this code, we'll only use a couple of variables names : `Aii`, `Aij`, `Ajk` etc... that will represent, depending on the iteration, a different matrix block.  
To illustrate :

```@julia
p = Dagger.@spawn add1(4)
p = Dagger.@spawn add2(2)
q = Dagger.@spawn add1(p)
```

Here the first task is shadowed by second, q will only wait for the second task.  
Therefore in the cholesky tiled factorization, we have to have a single variable name for every block of memory. Before computing anything we have to change our paradigm : we can't manipulate blocks of memory, we have to manipulate `Eagerthunks` previously mapped to blocks of memory.

```@julia
# Map thunks to blocks of memory
thunks = Matrix{Dagger.EagerThunk}(undef, m, n)
# ...

# Work on thunks
for i in 1:m
    thunks[i, i] = Dagger.@spawn cholesky(thunks[i, i])
    # ...
end

# Reverse mapping from thunks to blocks of memory
for i in 1:m, j in i:n
    Aij .= fetch(thunks[i, j])
end
```

It can be more natural to reason on memory access, rather than on return values stored by variables. The DataFlowTasks cholesky tiled factorization would look more similar to the common pseudo-code showed above :

```@julia
for i in 1:m
    @dpsawn cholesky!(@RW(Aii))
    for j in i+1:m
        @spawn ldiv!(@R(L), @RW(Aij))
    end
    for j in i+1:m
        for k in j:n
            @spawn matmul!(@RW(Ajk), @R(Aji), @R(Aik))
        end
    end
end
```

With DataFlowTasks, the approach is thinking in an isolated way, at the moment of writing the function call, what are the modes of access of the variables. There's no need to take the whole code into account.

## Write After Read

Dagger.jl doesn't detect this kind of dependcies (WAR). Although it's not the most common type of depency, it's still worth noticing. Let's look at a simple example.

Let a vector of 4 elements `X = ones(4)`, with 2 views `X₁ = @views X[1:2]` and `X₂ = @views X[3:4]`. We reproduce here the behaviour of the data structures we used in the cholesky tiled factorization exemple. We will use the 2 next functions to work on this data structure.

```julia
function longTask(Xᵢ...)
    sleep(2)
    Xᵢ[1] .*= (2.0 .+ Xᵢ[2])
end
function shortTask(Xᵢ...)
    Xᵢ[1] .+= 1.0
end
```

The work we want to do will be of type : `RW(X₁) -> RW(X₂) R(X₁) -> RW(X₁)`, and we will name those 3 tasks `tᵢ` with `i ∈ [1, 2, 3]`. The code will be :

```julia
X₁ = Dagger.@spawn shortTask(X₁)
X₂ = Dagger.@spawn longTask(X₂, X₁)
# fetch(X₂) needs to be added if we want it to work
X₁ = Dagger.@spawn shortTask(X₁)

fetch(X₁)
fetch(X₂)
X
```

We could think that because X₁ is in argument in t₂, when we'll want to write on X₁ in t₃, we will wait for t₂ to be finished. If it's the case, will have the following stats for X (the middle bar represent the separation X₁ and X₂ induce) :

```
1 1 | 1 1
2 2 | 1 1  --> t₁
1 1 | 4 4  --> t₂
3 3 | 4 4  --> t₃
```

Instead if we don't wait for t₂, we'll have an inversion of t₃ and t₂. We will have :

```
1 1 | 1 1
2 2 | 1 1  --> t₁
3 3 | 1 1  --> t₃
3 3 | 5 5  --> t₂
```

Actually, it's the case when the tasks are meant to be of different times like they are now (to illustrate the point). If they are not so different with each other, the code becomes non-determinstic.


!!! TO DO : PERFORMANCE DIFFERENCES !!!