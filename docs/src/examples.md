# [Examples](@id examples-section)

TODO: 
- add a description of the examples and more hardware info
- mention the effects of `tilesize` ahd `capacity` on the results of tiled factorization
- compare 'fork-join' approach to `HLU` to dataflow approach
 
## [Tiled Cholesky factorization](@id tiledcholesky-section)

### Computer 1
![Cholesky 8
cores](https://github.com/maltezfaria/DataFlowTasks.jl/blob/9958341ed6f2a1b94b6e4323a64bf12533bcf2ab/benchmarks/mac_choleskyperf_capacity_50_tilesize_256_cores_8.png)



### Computer 2
![Cholesky 20
cores](https://github.com/maltezfaria/DataFlowTasks.jl/blob/9958341ed6f2a1b94b6e4323a64bf12533bcf2ab/benchmarks/workstation_choleskyperf_capacity_50_tilesize_256_cores_20.png)

## [Tiled LU factorization](@id tiledlu-section)

!!! tip
    See [this page](https://hpc2n.github.io/Task-based-parallelism/branch/spring2021/task-basics-lu/)
    for a discussion on thread-based parallelization of `LU` factorization.

## [Hierarchical `LU` factorization]
