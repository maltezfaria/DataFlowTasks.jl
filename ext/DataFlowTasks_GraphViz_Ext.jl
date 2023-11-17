module DataFlowTasks_GraphViz_Ext

using GraphViz
using DataFlowTasks
using DataFlowTasks: LogInfo, longest_path, loggertodot

function __init__()
    @info "Loading DataFlowTasks dag plot utilities"
end

"""
    GraphViz.Graph(log_info::LogInfo)

Produce a `GraphViz.Graph` representing the DAG of tasks collected in `log_info`.

See also: [`DataFlowTasks.@log`](@ref)
"""
GraphViz.Graph(log_info::LogInfo) = GraphViz.Graph(loggertodot(log_info))

function DataFlowTasks.savedag(filepath::String, graph::GraphViz.Graph)
    !graph.didlayout && GraphViz.layout!(graph)
    open(filepath, "w") do io
        return GraphViz.render(io, graph)
    end
end

end
