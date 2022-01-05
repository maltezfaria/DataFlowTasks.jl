using DataFlowScheduler
using SafeTestsets

@safetestset "Codelet tests " begin include("codelet_test.jl") end
@safetestset "Dependencies tests" begin include("dependencies_test.jl") end
@safetestset "Dag tests" begin include("dag_test.jl") end
@safetestset "Taskgraph tests" begin include("taskgraph_test.jl") end
