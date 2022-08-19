# DataFlowTasks.jl

[![Stable](https://img.shields.io/badge/docs-stable-blue.svg)](https://maltezfaria.github.io/DataFlowTasks.jl/stable)
[![Dev](https://img.shields.io/badge/docs-dev-blue.svg)](https://maltezfaria.github.io/DataFlowTasks.jl/dev)
[![Build
Status](https://github.com/maltezfaria/DataFlowTasks.jl/workflows/CI/badge.svg)](https://github.com/maltezfaria/DataFlowTasks.jl/actions)
[![codecov](https://codecov.io/gh/maltezfaria/DataFlowTasks.jl/branch/main/graph/badge.svg?token=UOWU691WWG)](https://codecov.io/gh/maltezfaria/DataFlowTasks.jl)
![Lifecycle](https://img.shields.io/badge/lifecycle-experimental-blue.svg)

`DataFlowTasks.jl` is a Julia package dedicated to parallel programming on multi-core shared memory CPUs. From user annotations (READ, WRITE, READWRITE) on program data, `DataFlowTasks.jl` automatically infers dependencies between parallel tasks.

`DataFlowTasks.jl` is particularly easy to use with programs manipulating Julia
arrays, but can be extended to work with any custom data structure.

## Installation

```julia
using Pkg
Pkd.add("https://github.com/maltezfaria/DataFlowTasks.jl.git")
```

## Basic Usage

The use of `DataFlowTask`s is intended to be as similar to Julia native `Task`s as possible. The API implements three macros :
* `@dspawn`
* `@dtask`
* `@dasync`

which behave like their `Base` counterparts, except they need additional annotations to specify access modes. This is done with the three macros :
* `@R`
* `@W`
* `@RW`

where, in a function argument or at the beginning of a task block, `@R(A)` implies that A will be in read mode in the function/block.

Let's look at a simple example:

```julia
using DataFlowTasks
using GraphViz

DataFlowTasks.reset!()
write!(X, alpha) = (X .= alpha)
readwrite!(X) = (X .+= 2)
n = 1000
A = ones(n)
let
    @dspawn readwrite!(@RW(A))              # 1
    @dspawn write!(@W(@view A[1:500]), 2)   # 2
    @dspawn write!(@W(@view A[501:n]), 3)   # 3
    @dspawn readwrite!(@RW(A))              # 4
end
DataFlowTasks.sync()
DataFlowTasks.dagplot()
```

![SimpleDag](docs/src/simple_dag_example.svg)

This will generate the DAG (Directed Acyclic Graph) above that represents the dependencies between tasks. This means that the task 2 and 3 can be run in parallel. We see how it's the memory that matters here.

## Example : Parallel Cholesky Factorization

As a less contrived example, we illustrate below the use of `DataFlowTasks` to parallelize a tiled Cholesky factorization. The implementation shown here is delibarately made as simple as possible; a more complex and more efficient implementation can be found in the [TiledFactorization](https://github.com/maltezfaria/TiledFactorization) package.

The Cholesky factorization algorithm takes a symmetric positive definite matrix A and finds a lower triangular matrix L such that `A = LLᵀ`. The tiled version of this algorithm decomposes the matrix A into tiles (of even sizes, in this simplified version). At each step of the algorithm, we do a Cholesky factorization on the diagonal tile, use a triangular solve to update all of the tiles at the right of the diagonal tile, and finally update all the tiles of the submatrix with a schur complement.

If we have a matrix A decomposed in `n x n` tiles, then the algorithm will have `n` steps. The `i`-th step (with `i ∈ [1:n]`) will perform 
- `1` cholesky factorization of the (i,i) block (I),
- `(i-1)` triangular solves (one for each block in the `i`-th row) (II),
- `i*(i-1)/2` matrix multiplications to update the submatrix (III).

We illustrate the 2nd step of the algorithm in the following image.

![Cholesky_Image](docs/src/Cholesky_2ndStep.png)

A sequential tiled factorization algorithm can be implemented as:

```julia
tilerange(ti, ts) = (ti-1)*ts+1:ti*ts
function cholesky_tiled!(A, ts)
    m,n = size(A)
    n%ts != 0 && error("Tilesize doesn't fit the matrix")
    tn = n÷ts

    Atile = [view(A, tilerange(ti, ts), tilerange(tj, ts)) for ti in 1:tn, tj in 1:tn]

    for ti in 1:tn
        # Diagonal cholesky serial factorization (I)
        cholesky!(Atile[ti,ti])

        # Left blocks update (II)
        L = adjoint(UpperTriangular(Atile[ti,ti]))
        for tj in ti+1:tn
            ldiv!(L, Atile[ti,tj])
        end

        # Submatrix update (III)
        for tj in ti+1:tn
            for tk in tj:tn
                mul!(Atile[tj,tk], adjoint(Atile[ti,tj]), Atile[ti,tk])
            end
        end
    end

    # Construct the factorized object
    return Cholesky(A,'U',zero(LinearAlgebra.BlasInt))
end
```

In order to parallelize the code with DataFlowTasks, it will only be necessary to wrap function calls within a `@dspawn`, and add a synchronization point at the end. The parallelized code will be :

```julia
using DataFlowTasks
using LinearAlgebra
function cholesky_dft!(A, ts)
    m,n = size(A)
    n%ts != 0 && error("Tilesize doesn't fit the matrix")
    tn = n÷ts

    Atile = [view(A, tilerange(ti, ts), tilerange(tj, ts)) for ti in 1:tn, tj in 1:tn]

    for ti in 1:tn
        # Diagonal cholesky serial factorization (I)
        @dspawn cholesky!(@RW(Atile[ti,ti])) label="chol ($ti,$ti)"

        # Left blocks update (II)
        U = UpperTriangular(Atile[ti,ti])
        for tj in ti+1:tn
            @dspawn ldiv!(adjoint(@R(U)), @RW(Atile[ti,tj])) label="ldiv ($ti,$tj)"
        end

        # Submatrix update (III)
        for tj in ti+1:tn
            for tk in tj:tn
                Ajk = Atile[tj,tk]
                Aik = Atile[ti,tk]
                @dspawn mul!(@RW(Ajk), adjoint(@R(Atile[ti,tj])), @R(Aik), -1, 1) label="schur ($tj,$tk)"
            end
        end
    end
    # Construct the factorized object
    r = @dspawn Cholesky(A,'U',zero(LinearAlgebra.BlasInt))
    return fetch(r)
end
```

The code below shows how to use this `cholesky_dft!` function, how to profile the program and get the most information from the visualization. 

```julia
import DataFlowTask as DFT

# DataFlowTasks environnement setup
DFT.reset!()
DFT.enable_log()
DFT.setscheduler!(DFT.JuliaScheduler(50))

# Context
n  = 4096
ts = 512
A = rand(n, n)
A = (A + adjoint(A))/2
A = A + n*I

# Compilation
cholesky_tiled!(copy(A), ts)

# Reset environnement
DFT.resetlogger!()
GC.gc()

# Real work to be analysed
F = cholesky_tiled!(A ,ts)
@info err  = norm(F.L*F.U-A,Inf)/max(norm(A),norm(F.L*F.U))

# Parallel Trace Plot
DFT.plot(categories=["chol", "ldiv", "schur"])

# Dag Plot
DFT.dagplot()
```

## Profiling

DataFlowTasks comes with 2 main profiling : a parallel trace and a DAG visualization.

Here is the parallel trace for a matrix of size (4096, 4096) divided in tiles of size (512, 512) :

![Trace Plot](docs/src/cholesky_simplified.png)

Next is the DAG (graph) that represent the dependencies between tasks for the same algorithm but with only $4*4$ tiles.

![Dag Plot](exampledag.svg)

We'll cover in details the usage and possibilities of the visualization in the documentation.

Note that the visualization tools are not loaded by default, it requires a `Makie` backend and/or `GraphViz` loaded in the REPL. It's meant to be used in development, so it won't pollute the environment you want to use DFT in.

# Performances

The next results are obtained with a slightly modified version of the function presented above. We used the `LoopVectorization` for the serial cholesky (I), `TriangularSolve`'s `ldiv!` and `Octavian`'s `matmul_serial!`.

The package `TiledFactorization` contains this implementation, you can use it with the following lines :

```julia
import Pkg
Pkg.add("https://github.com/maltezfaria/TiledFactorization.git")
using TiledFactorization: cholesky!
```

We compare the performances achieved with this version of the Cholesky factorization with the MKL one, and we obtain the next figure. Here the blocks are of size (256, 256).

![Perf](scalability_lfaria.png)
