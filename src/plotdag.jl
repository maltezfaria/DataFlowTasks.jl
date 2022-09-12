@info "Loading DataFlowTasks dag plot utilities"

using .GraphViz

"""
    dagplot(logger)

Plot the dag in DOT format
"""
function dagplot(logger)
    # Create GraphViz graph DOT format file
    g = GraphViz.Graph(loggertodot(logger))
end

"""
    savedag(filepath, graph)
Save svg dag image in filepath
"""
function savedag(filepath::String, graph::GraphViz.Graph)
    !graph.didlayout && GraphViz.layout!(graph)
    open(filepath, "w") do io
        GraphViz.render(io, graph)
    end
end

"""
    loggertodot(logger)  --> dagstring
Return a string in the
[DOT](https://en.wikipedia.org/wiki/DOT_(graph_description_language)) format
representing the underlying graph in `logger`
and to be plotted by GraphViz with Graph(logger_to_dot())
"""
function loggertodot(logger)
    path = criticalpath(logger)

    # Write DOT graph
    # ---------------
    str = "strict digraph dag {rankdir=LR;layout=dot;rankdir=TB;"
    str *= """concentrate=true;"""

    for tasklog ∈ Iterators.flatten(logger.tasklogs)
        # Tasklog.tag node attributes
        str *= """ $(tasklog.tag) """
        tasklog.label != "" && (str *= """ [label="$(tasklog.label)"] """)
        tasklog.tag ∈ path && (str *= """ [color=red] """)
        str *= """[penwidth=2];"""

        # Defines edges
        for neighbour ∈ tasklog.inneighbors
            red = false

            # Is this connection is in critical path
            (neighbour ∈ path && tasklog.tag ∈ path) && (red=true)

            # Edge
            str *= """ $neighbour -> $(tasklog.tag) """
            red && (str *= """[color=red] """)
            str *= """[penwidth=2];"""
        end
    end

    str *= "}"
end
