using DataFlowTasks
using SafeTestsets

@safetestset "Aqua.jl tests" begin
    include("aqua_test.jl")
end
@safetestset "DataFlowTask tests " begin
    include("dataflowtask_test.jl")
end
@safetestset "Dependencies tests" begin
    include("dependencies_test.jl")
end
@safetestset "Dag tests" begin
    include("dag_test.jl")
end

@safetestset "Taskgraph tests" begin
    include("taskgraph_test.jl")
end

@safetestset "LogInfo tests" begin
    include("loginfo_test.jl")
end
