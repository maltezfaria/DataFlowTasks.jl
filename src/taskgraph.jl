const WINDOWSIZE = Ref(100)

"""
    TaskGraph

A computational graph with nodes representing units of computation to be carried
out. The indices in the `graph` reference entries in `nodes`.
"""
Base.@kwdef struct TaskGraph{T}
    tasks::Vector{Codelet} = Codelet[]
    graph::DAG{T} = DAG{UInt64}()
    pending::Channel{Codelet} = Channel{Codelet}(100)
    runnable::Channel{Int}    = Channel{Int}(100)
    finished::Channel{Int}    = Channel{Int}(100)
    # FIXME: the only reason active_count exists is so that trying to add a node
    # to the graph will block if the count is bigger than certain nmax. There
    # has to be a simpler way to achieve this which avoids using a dummy
    # channel.
    _active_count::Channel{Nothing}  = Channel{Nothing}(WINDOWSIZE[])
end

function addtask!(tg::TaskGraph,t)
    put!(tg.pending,t)
    return tg
end

function process_pending_tasks!(tg::TaskGraph)
    @debug Threads.threadid()
    @assert Threads.threadid() == 1
    put!(tg._active_count,nothing)
    g = graph(tg)
    cdlt = take!(tg.pending)
    push!(tg.tasks,cdlt)
    i = length(tg.tasks)
    # add node i then update the edges
    addnode!(g,i)
    _update_edges!(tg,i)
    # if i has no dependency, add it to runnable list
    isempty(inneighbors(tg,i)) && put!(tg.runnable,i)
    return tg
end

function pending_tasks_worker!(tg)
    while true
        process_pending_tasks!(tg)
    end
end

function process_runnable_tasks!(tg::TaskGraph)
    i    = take!(tg.runnable)
    execute(gettask(tg,i))
    put!(tg.finished,i)
    return tg
end

function runnable_tasks_worker!(tg)
    while true
        process_runnable_tasks!(tg)
    end
end

function process_finished_tasks!(tg::TaskGraph)
    @assert Threads.threadid() == 1
    dag  = graph(tg)
    i    = take!(tg.finished)
    @info i
    # remove node `i` from the dag
    (inlist,outlist) = pop!(dag.inoutlist,i)
    # Update all nodes in the outlist of i. If `i` was the last
    # dependency, then that node is now runnable
    for j in outlist
        pop!(inneighbors(dag,j),i)
        isempty(inneighbors(dag,j)) && put!(tg.runnable,j)
    end
    # indicate that dag has now one active node less
    take!(tg._active_count)
    return tg
end

function finished_tasks_worker!(tg)
    while true
        process_finished_tasks!(tg)
    end
end

function initialize_workers(tg)
    @async pending_tasks_worker!(tg)
    # spawn the heavy workers on background threads
    for i in 2:Threads.nthreads()
        @tspawnat i runnable_tasks_worker!(tg)
    end
    @async finished_tasks_worker!(tg)
    return tg
end

tasks(tg::TaskGraph)          = tg.tasks
gettask(tg::TaskGraph,i)      = tg.tasks[i]
graph(tg::TaskGraph)          = tg.graph

num_tasks(tg::TaskGraph) = length(tasks(tg))

"""
    dependencies(tg::TaskGraph,i)

Return the indices of the nodes in `tg` upon which node `i` depends on.
"""
dependencies(tg::TaskGraph,i) = inneighbors(tg,i)

function setdata(tg::TaskGraph,data)
    tg.data = data
end

"""
    _update_edges!(tg::TaskGraph,i)

Perform the data-flow analysis to update the edges after insertion of node `i`.
"""
function _update_edges!(tg::TaskGraph,j)
    nodej  = gettask(tg,j)
    dag    = graph(tg)
    # determine how nodej is connected to the rest of the graph
    for i in j-1:-1:1
        nodei  = gettask(tg,i)
        dep    = dependency_type(nodei,nodej)
        isindependent(dep) && continue
        # check for transitive reductions and add edge
        addedge_transitive!(dag,i,j)
    end
    return tg
end

macro schedule(tg,ex)
    esc(:(DataFlowScheduler.addtask!($tg,@codelet $ex)))
end

macro schedule(ex)
    tg = :(DataFlowScheduler.TASKGRAPH)
    esc(:(DataFlowScheduler.addtask!($tg,@codelet $ex)))
end

function Base.empty!(tg::TaskGraph)
    empty!(tasks(tg))
    empty!(graph(tg))
    return tg
end

# delegate a few functions to the underlying graph
let
    graph_ops = (:num_edges,:num_nodes,:addedge!,:hasedge,
                 :inneighbors,:outneighbors,:isconnected,:adjacency_matrix,
                :addedge_transitive!)
    for op in graph_ops
        @eval $(op)(tg::TaskGraph,args...;kwargs...) = $(op)(graph(tg),args...,kwargs...)
    end
end

# # ################################################################################
# # ## visualization
# # ################################################################################
function graphplot(tg::TaskGraph,args...;kwargs...)
    tasks = tasks(tg)
    names = ["$i. " * label(tasks[i]) for i in 1:num_nodes(tg)]
    graphplot(
        graph(tg),
        curves=false,
        arrow =true,
        root  = :left,
        names=names,
        # method = :buchheim,
        # args...;
        # kwargs...
    )
    # graphplot(graph(tg),
    #           method=:buchheim,
    #           curves=false,
    #           nodeshape=:ellipse,
    #           arrow=true,
    #           shorten=0.1,
    #           root=:left,
    #           args...;kwargs...)
    # -#     graphplot(graph,
    #     -#               curves=false,
    #     -#               nodeshape=:ellipse,
    #     -#               linewidth=2,
    #     -#               names=label,
    #     -#               arrow=true,
    #     -#               shorten=0.3,
    #     -#               root=:left,
    #     -#               method=:buchheim,
    #     -#               args...;kwargs...)
    #     -# end
end
