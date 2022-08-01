# DataFlowTasks.jl

[![Stable](https://img.shields.io/badge/docs-stable-blue.svg)](https://maltezfaria.github.io/DataFlowTasks.jl/stable)
[![Dev](https://img.shields.io/badge/docs-dev-blue.svg)](https://maltezfaria.github.io/DataFlowTasks.jl/dev)
[![Build
Status](https://github.com/maltezfaria/DataFlowTasks.jl/workflows/CI/badge.svg)](https://github.com/maltezfaria/DataFlowTasks.jl/actions)
[![codecov](https://codecov.io/gh/maltezfaria/DataFlowTasks.jl/branch/main/graph/badge.svg?token=UOWU691WWG)](https://codecov.io/gh/maltezfaria/DataFlowTasks.jl)
![Lifecycle](https://img.shields.io/badge/lifecycle-experimental-blue.svg)

`DataFlowTasks.jl` is a Julia package dedicated to parallel programming on multi-core shared memory CPUs. From user annotations (READ, WRITE, READWRITE) on program data, `DataFlowTasks.jl` automatically infers dependencies between parallel tasks.

The usual linear algebra data types (Julia arrays) are particularly easy to use with `DataFlowTasks.jl`.

## Installation

```julia
using Pkg
Pkd.add("https://github.com/maltezfaria/DataFlowTasks.jl.git")
```

## Basic Usage

The use of a `DataFlowTask`s is intended to be as similar to a Julia native `Task`s as possible. The API implements these three macros :
* `@dspawn`
* `@dtask`
* `@dasync`

which behaves like there `Base` counterparts, except they need additional annotations to specify access modes. This is done with the three macros :
* `@R`
* `@W`
* `@RW`

where, in a function argument or at the beginning of a task block, `@R(A)` implies that A will be in read mode in the function/block.

Let's look at how it can parallelize with safety insurance.

```julia
write!(X, alpha) = (X .= alpha)
readwrite!(X) = (X .+= 2)

n = 1000
A = ones(n)

@dspawn write!(@R(A), 1)          # 1
@dspawn write!(@R(A[1:500]), 2)   # 2
@dspawn write!(@R(A[501:n]), 3)   # 3
@dspawn begin                     # 4
  @RW A
  readwrite!(A)
end

DataFlowTasks.sync()
```

This will generate the DAG (Directed Acyclic Graph) below that represents the dependencies between tasks. This means that the task 2 and 3 can be run in parallel. We see how it's the memory that matters here.

![Basic](graph.png)

## Example : Parallel Cholesky Factorization

Let's take for use case the Cholesky tiled factorization algorithm. The serialized code would take a *tiled* matrix (divided into views of blocks) and would be something like :


```julia
1   function cholesky!(A::TiledMatrix)
2       # Number of blocks
3       m,n = size(A)
4   
5       # Core
6       for i in 1:m
7           # Diagonal cholesky serial factorization
8           serial_cholesky!(A[i,i])
9   
10          # Left blocks update
11          L = adjoint(UpperTriangular(A[i,i]))
12          for j in i+1:n
13              ldiv!(L,A[i,j])
14          end
15  
16          # Submatrix update
17          for j in i+1:m
18              for k in j:n
19                  Aji = adjoint(A[i,j])
20                  schur_complement!(A[j,k], Aji, A[i,k])
21              end
22          end
23      end
24  
25      # Construct the factorized object
26      return Cholesky(A.data,'U',zero(LinearAlgebra.BlasInt))
27  end
```

In order to parallelize `DataFlowTasks.jl`, one has to add a `@dspawn` macro before function calls (lines 8, 13 and 20) and add a synchronization point `DataFlowTasks.sync()` before returning the solution (line 24) :

```julia
1   function cholesky!(A::TiledMatrix)
2       # Number of blocks
3       m,n = size(A)
4   
5       # Core
6       for i in 1:m
7           # Diagonal cholesky serial factorization
8           @dspawn serial_cholesky!(@RW(A[i,i]))
9   
10          # Left blocks update
11          L = adjoint(UpperTriangular(A[i,i]))
12          for j in i+1:n
13              @dspawn ldiv!(@R(L), @RW(A[i,j]))
14          end
15  
16          # Submatrix update
17          for j in i+1:m
18              for k in j:n
19                  Aji = adjoint(A[i,j])
20                  @dspawn schur_complement!(@RW(A[j,k]), @R(Aji), @R(A[i,k]))
21              end
22          end
23      end
24      DataFlowTasks.sync()
25      # Construct the factorized object
26      return Cholesky(A.data,'U',zero(LinearAlgebra.BlasInt))
27  end
```


## Profiling

We can illustrate the parallelization implied by those modifications. `DataFlowTasks.jl` comes with 2 main visualization tools whose outputs for the case presented above, with a matrix of size (2000, 2000) divided in blocks of (500, 500), are as follows :

![Trace Plot](example.png)
![Dag Plot](exampledag.svg)

We'll cover in details the usage and possibilities of the visualization in the documentation.

Note that the visualization tools are not loaded by default, it requires a `Makie` backend and/or `GraphViz` loaded in the REPL. It's meant to be used in development, so it won't pollute the environment you want to use DFT in.

# Performances

We compare the performances achieved with this version of the Cholesky factorization with the MKL one, and we obtain the next figure. Here the blocks are of size (256, 256).

![Perf](scalability_lfaria.png)