using DataFlowTasks
using SafeTestsets

@safetestset "DataFlowTask tests " begin include("dataflowtask_test.jl") end
@safetestset "Dependencies tests"  begin include("dependencies_test.jl") end
@safetestset "Dag tests"           begin include("dag_test.jl") end
@safetestset "Scheduler tests" begin
    include("juliascheduler_test.jl")
    # other schedulers are left out for now until the API settles. They may not
    # be needed in any case after all....
    # include("priorityscheduler_test.jl")
    # include("staticscheduler_test.jl")
end

@safetestset "LogInfo tests" begin include("loginfo_test.jl") end
