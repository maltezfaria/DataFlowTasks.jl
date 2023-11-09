# [Hardware information](@id hardware-information)

The examples and benchmarks here were generated using:

## Version info

```@example
using InteractiveUtils
versioninfo()
```

## Topology

```@example
using Hwloc
topology_info()
```

## CPU

```@example
using CpuId
printstyled(cpuinfo())
```
