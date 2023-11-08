# [Overview](@id examples-overview)

This section contains a variety of examples and benchmarks of applications where
`DataFlowTasks` can be used to parallelize code. These include:

- [Cholesky factorization](@ref tiledcholesky-section)
- [Image filters](@ref blur-roberts-section)
- [Longest common subsequence](@ref lcs-section)
- [Merge sort](@ref example-sort)

 Each example comes with a notebook version, which can be downloaded and run
 locally: give it a try. And if `DataFlowTasks` is useful to you, please
 consider submitting your own example application!

## Hardware and `versioninfo`

The examples and benchmarks here were generated using

```@example
versioninfo()
```

on a hardware with the following topology:

```@example
using Hwloc
topology_info()
```
