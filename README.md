# DataFlowTasks.jl

[![Stable](https://img.shields.io/badge/docs-stable-blue.svg)](https://maltezfaria.github.io/DataFlowTasks.jl/stable)
[![Dev](https://img.shields.io/badge/docs-dev-blue.svg)](https://maltezfaria.github.io/DataFlowTasks.jl/dev)
[![Build
Status](https://github.com/maltezfaria/DataFlowTasks.jl/workflows/CI/badge.svg)](https://github.com/maltezfaria/DataFlowTasks.jl/actions)
[![codecov](https://codecov.io/gh/maltezfaria/DataFlowTasks.jl/branch/main/graph/badge.svg?token=UOWU691WWG)](https://codecov.io/gh/maltezfaria/DataFlowTasks.jl)
![Lifecycle](https://img.shields.io/badge/lifecycle-experimental-blue.svg)

DataFlowTasks is a package for task-based parallel computing, oriented towards linear algebra, in native julia. When writing a task, the user will specify the access modes (read, write, read/write) for each data. These informations will infer the dependencies between all existing tasks automatically.

## Installation

```julia
using Pkg
Pkd.add("https://github.com/maltezfaria/DataFlowTasks.jl.git")
```

## Basic Usage

The use of a `DataFlowTask` is intended to be as similar to a native `Task` as possible. The API revolves around three macros :
* `@dspawn`
* `@dtask`
* `@dasync`

which behaves like there base counterparts, with additionnal annotations needed to specify access modes. A syntax exemple :

```julia
(A, B, C) = [rand(5,5) for _ in 1:3]

@dspawn mul!(@W(C), @R(A), @R(B))

@dspawn begin
    @W C
    @R A B
    mul!(C, A, B)
end
```

Let's look at how it can parallelize with safety insurance.

```julia
write!(X, alpha) = (X .= alpha)
readwrite!(X) = (X .+= 2)

n = 1000
A = ones(n)

@dspawn write!(@R(A), 1)
@dspawn write!(@R(A[1:500]), 2)
@dspawn write!(@R(A[501:n]), 3)
@dspawn readwrite!(@RW(A))

DataFlowTasks.sync()
```

This will generate the DAG (Directed Acyclic Graph) below that represents the depencies between tasks. This means that the task 1 and 2 can be ran in parallel. We see how it's the memory that matters here.

![Basic](graph.png)

## Example

Let's take for use case the cholesky tiled factorization algorithm. The serialized code would take a "tiled" matrix (divided into views of blocks) and would be something like :

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
11          L = adjoint(UpperTriangular(Aii))
12          for j in i+1:n
13              ldiv!(L,A[i,j])
14          end
15  
16          # Submatrix update
17          for j in i+1:m
18              for k in j:n
19                  Aji = adjoint(A)
20                  schur_complement!(A[j,k], Aji, A[i,k])
21              end
22          end
23      end
24  
25      # Construct the factorized object
26      return Cholesky(A.data,'U',zero(LinearAlgebra.BlasInt))
27  end
```

If we were to parallelize this code with DataFlowTasks, we woud only have to wrap function calls within a `@dspawn`. We would have to change the lines 8, 13, and 20 (as well as add a synchronization point at the end) as follows :

```julia
8   @dspawn serial_cholesky!(@RW(A[i,i]))

13  @dspawn ldiv!(@R(L), @RW(A[i,j]))

20  @dspawn schur_complement!(@RW(A[j,k]), @R(Aji), @R(A[i,k]))

24  DataFlowTasks.sync()
```

## Visualization

We can illustrate the parallelization implied by thoses modifications. DataFlowTasks comes with 2 main visualization tools whose outputs for the the case presented above, with a matrix of size (2000, 2000) divided in blocks of (500, 500), are as follows :

![Trace Plot](example.png)
![Dag Plot](exampledag.svg)

We'll cover in details the usage and possibilities of the visualization in the documentation.

Note that the visualization tools are not loaded by default, it requires a Makie backend and/or GraphViz loaded in the REPL. It's meant to be used in developpement, so it won't pollute the environnement you want to use DataFlowTasks in.

# Performances

We compare the performances achieved with this version of the cholesky factorization with the MKL one, and we obtain the next figure. Here the blocks are of size (256, 256).

![Perf](scalability_lfaria.png)