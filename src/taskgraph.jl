struct TaskGraph{T,S}
    tasks::T
    graph::S
end
TaskGraph() = TaskGraph(Any[],SimpleDiGraph())

gettasks(tg::TaskGraph)  = tg.tasks
gettask(tg::TaskGraph,i) = tg.tasks[i]
getgraph(tg::TaskGraph)  = tg.graph

# function imported from LightGraphs
graph_ops = (:nv,:ne,:add_edge!,:has_edge,:transitivereduction)
for op in graph_ops
    @eval $(op)(tg::TaskGraph,args...;kwargs...) = $(op)(getgraph(tg),args...,kwargs...)
end

function insert_task!(tg::TaskGraph,task)
    _insert_task_no_update!(tg,task)
    _update_graph_last_node!(tg)
    # transitivereduction(tg)
    return tg
end

function _insert_task_no_update!(tg::TaskGraph,task)
    graph = getgraph(tg)
    tasks = gettasks(tg)
    push!(tasks,task)
    add_vertex!(graph)
    return tg
end

function _update_graph_last_node!(task_graph::TaskGraph)
    j          = nv(task_graph)
    tj         = gettask(task_graph,j)
    # NOTE: the reverse order is important here as it will be assume inside of the called _update_edges
    for i in j-1:-1:1
        _update_edges!(task_graph,i,j)
    end
    return task_graph
end

function _update_edges!(graph,i,j)
    @assert i<j
    tasks = gettasks(graph)
    # assumes _update_edges!(k,j) has been called for all k s.t. i<k<j
    tj  = gettask(graph,j)
    ti  = gettask(graph,i)
    dep = dependency_type(ti,tj)
    if Int(dep)>0
        # check that the dependency is really necessary given the transitive nature of graph
        # for k in i+1:j-1
        #     has_edge(graph,i,k) && has_edge(graph,k,j) && (return graph)
        # end
        add_edge!(graph,i,j)
    end
    return graph
end


# ################################################################################
# ## visualization
# ################################################################################
haslabel(x) = false
function graphplot(tg::TaskGraph,args...;kwargs...)
    tasks = gettasks(tg)
    label = [haslabel(tasks[i]) ? getlabel(tasks[i]) : i for i in 1:nv(tg)]
    graph = getgraph(tg)
    graphplot(graph,
              curves=false,
              nodeshape=:ellipse,
              linewidth=2,
              names=label,
              arrow=true,
              shorten=0.3,
              root=:left,
              method=:buchheim,
              args...;kwargs...)
end
