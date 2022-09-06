"""
    struct DAG{T}

Representation of a directed acyclic graph containing nodes of type `T`. The
list of nodes with edges coming into a node `i` can be retrieved using
[`inneighbors(dag,i)`](@ref); similarly, the list of nodes with edges leaving
from `i` can be retrieved using [`outneighbors(dag,i)`](@ref).

`DAG` is a buffered structure with a buffer of size `sz_max`: calling [`addnode!`](@ref) on it will block
if the `DAG` has more than `sz_max` elements.
"""
struct DAG{T}
    inoutlist::OrderedDict{T,Tuple{Set{T},Set{T}}}
    cond_push::Condition
    cond_empty::Condition
    lock::ReentrantLock
    sz_max::Ref{Int}
    _buffer::Set{Int} # used to keep track of visited nodes when needed
end

"""
    DAG{T}(sz)

Create a buffered `DAG` holding a maximum of `s` nodes of type `T`.
"""
function DAG{T}(sz = typemax(Int)) where T
    sz = sz == Inf ? typemax(Int) : Int(sz)
    if sz <= 0
        throw(ArgumentError("DAG buffer size must be a positive integer"))
    end
    inoutlist  = OrderedDict{T,Tuple{Set{T},Set{T}}}()
    cond_push  = Condition()
    cond_empty = Condition()
    lock = ReentrantLock()
    _buffer    = Set{Int}()
    return DAG{T}(inoutlist,cond_push,cond_empty,lock,Ref(sz),_buffer)
end

function Base.resize!(dag::DAG,sz)
    sz = sz == Inf ? typemax(Int) : Int(sz)
    msg = """cannot resize `dag` (desired capacity too small to contain the
    already present nodes)"""
    num_nodes(dag) > sz && error(msg)
    dag.sz_max[] = sz
end

"""
    const TaskGraph = DAG{DataFlowTask}

A directed acyclic graph of `DataFlowTask`s.
"""
const TaskGraph = DAG{DataFlowTask}

Base.isempty(dag::DAG)     = isempty(dag.inoutlist)
Base.getindex(dag::DAG,i)  = dag.inoutlist[i]

Base.lock(dag::DAG)   = lock(dag.lock)
Base.unlock(dag::DAG) = unlock(dag.lock)

"""
    num_nodes(dag::DAG)

Number of nodes in the `DAG`.
"""
function num_nodes(dag::DAG)
    length(dag.inoutlist)
end

"""
    num_edges(dag::DAG)

Number of edges in the `DAG`.
"""
function num_edges(dag::DAG)
    acc = 0
    for (k,(inlist,outlist)) in dag.inoutlist
        acc += length(inlist)
    end
    return acc
end

"""
    inneighbors(dag,i)

List of predecessors of `i` in `dag`.
"""
inneighbors(dag::DAG,i)  = dag.inoutlist[i][1]

"""
    outneighbors(dag,i)

List of successors of `j` in `dag`.
"""
outneighbors(dag::DAG,i) = dag.inoutlist[i][2]

function Base.empty!(dag::DAG)
    empty!(dag.inoutlist)
end

Iterators.reverse(dag::DAG) = Iterators.reverse(dag.inoutlist)
Base.iterate(dag::DAG,state=1) = iterate(dag.inoutlist,state)

"""
    addedge!(dag,i,j)

Add (directed) edge connecting node `i` to node `j` in the `dag`.
"""
function addedge!(dag::DAG{T},i::T,j::T) where {T}
    @assert i < j
    push!(outneighbors(dag,i),j)
    push!(inneighbors(dag,j),i)
    return dag
end

"""
    addnode!(dag,(k,v)::Pair[, check=false])
    addnode!(dag,k[, check=false])

Add a node to the `dag`. If passed only a key `k`, the value `v` is initialized
as empty (no edges added). The `check` flag is used to indicate if a data flow
analysis should be performed to update the dependencies of the newly inserted
node.
"""
function addnode!(dag::DAG{T},i::T,check=false) where {T}
    addnode!(dag,i=>(Set{T}(),Set{T}()),check)
end

function addnode!(dag::DAG,kv::Pair,check=false)
    while num_nodes(dag) == dag.sz_max[]
        wait(dag.cond_push)
    end
    lock(dag)
    try
        t₀ = time_ns()
        stats = Base.gc_num()
        # -------
        push!(dag.inoutlist,kv)
        k,v = kv
        check  && update_edges!(dag,k)

        # -------
        diff = Base.GC_Diff(Base.gc_num(), stats)
        t₁ = time_ns()
        tid = Threads.threadid()
        _log_mode() && push!(getlogger().insertionlogs[tid], InsertionLog(t₀, t₁, diff.total_time, tag(k), tid))
    finally
        unlock(dag)
    end
    return dag
end

"""
    update_edges!(dag::DAG,i)

Perform the data-flow analysis to update the edges of node `i`. Both incoming
and outgoing edges are updated.
"""
function update_edges!(dag::DAG,nodej)
    transitively_connected = dag._buffer
    empty!(transitively_connected)
    # update dependencies from newer to older and reinfornce transitivity by
    # skipping predecessors of nodes which are already connected
    for (nodei,_) in Iterators.reverse(dag)
        ti     = tag(nodei)
        (ti ∈ transitively_connected) && continue
        @assert nodei ≤ nodej
        nodei == nodej  && continue
        dep    = data_dependency(nodei,nodej)
        dep   || continue
        addedge!(dag,nodei,nodej)
        update_transitively_connected!(transitively_connected,nodei,dag)
        # addedge_transitive!(dag,nodei,nodej)
    end
    return dag
end

function update_transitively_connected!(transitively_connected,node,dag)
    for nodei in inneighbors(dag,node)
        ti = tag(nodei)
        (ti ∈ transitively_connected) && continue
        push!(transitively_connected,ti)
        update_transitively_connected!(transitively_connected,nodei,dag)
    end
    return transitively_connected
end

"""
    isconnected(dag,i,j)

Check if there is path in `dag` connecting `i` to `j`.
"""
function isconnected(dag::DAG,i,j)
    for k in inneighbors(dag,j)
        if k==i
            return true
        elseif k<i
            continue
        else#k>i
            isconnected(dag,i,k) && (return true)
        end
    end
    return false
end

"""
    addedge_transitive!(dag,i,j)

Add edge connecting nodes `i` and `j` if there is no path connecting them already.
"""
function addedge_transitive!(dag,i,j)
    isconnected(dag,i,j) ? dag : addedge!(dag,i,j)
end

"""
    has_edge(dag,i,j)

Check if there is an edge connecting `i` to `j`.
"""
has_edge(dag::DAG,i,j) = j ∈ outneighbors(dag,i)

"""
    remove_node!(dag::DAG,i)

Remove node `i` and all of its edges from `dag`.
"""
function remove_node!(dag::DAG,i)
    lock(dag)
    try
        if !isempty(inneighbors(dag,i))
            @warn "removing a node with incoming neighbors"
        end
        (inlist,outlist) = pop!(dag.inoutlist,i)
        # remove i from the inlist of all its outneighbors
        for j in outlist
            pop!(inneighbors(dag,j),i)
        end
        # notify a task waiting to push into the dag
        notify(dag.cond_push,nothing;all=false)
        # if dag is empty, notify
        isempty(dag) && notify(dag.cond_empty)
    finally
        unlock(dag)
    end
    return
end

function reset!()
    dag = getscheduler().dag

    for pair ∈ dag.inoutlist
        node = pair.first
        try
            wait(node)
        catch
            remove_node!(dag, node)
        end
    end

    sync()
    resetlogger!()
    resetcounter!()
end

"""
    adjacency_matrix(dag)

Construct the adjacency matrix of `dag`.
"""
function adjacency_matrix(dag::DAG{T}) where {T}
    n = num_nodes(dag)
    S = zeros(Bool,n,n)
    # map the nodes in the `dag` to integer indices from 1 to n
    dict = Dict{T,Int}(c=>i for (i,c) in enumerate(keys(dag.inoutlist)))
    for i in keys(dag.inoutlist)
        J = outneighbors(dag,i)
        for j in J
            S[dict[i],dict[j]] = 1
        end
    end
    return S
end

function Base.show(io::IO, dag::DAG{T}) where {T}
    n = num_nodes(dag)
    e = num_edges(dag)
    s1 = n==1 ? "" : "s"
    s2 = e==1 ? "" : "s"
    print(io, typeof(dag)," with $n node$s1 and $e edge$s2 (capacity of $(dag.sz_max[]) nodes)")
end


############################################################################
#                           Critical Path
############################################################################

#=
    notvisited_min(dist, visited) --> minnode
Extract the index minnode of the minimum value of dist
such that visited[minnode] = false
=#
function notvisited_min(dist, visited)
    minnode = Int64
    mindist = Inf
    for node ∈ 1:length(dist)
        visited[node] && continue
        if dist[node] < mindist
            minnode = node
            mindist = dist[node]
        end
    end
    minnode
end


#=
    longestpath(adj) -> path
Finds the critical path of a DAG G by using Dijsktra's shortest path algorithm on G
Returns the nodes constituting the path
=#
function longestpath(adj)
    n = length(adj)                  # number of nodes
    dist     = [-Inf   for _ ∈ 1:n]  # dist[i] gives the shortest path from source to i
    previous = [0     for _ ∈ 1:n]   # previous[i] gives the antecedent of i in longest path
    path     = Vector{Int64}()       # explicit storage for the longest path
    dist[1] = 0

    for currnode ∈ 1:n
        if dist[currnode] != -Inf
            for (neighbour, weight) ∈ adj[currnode]
                if dist[neighbour] < dist[currnode] + weight
                    dist[neighbour] = dist[currnode] + weight
                    previous[neighbour] = currnode
                end
            end
        end
    end

    # Extract path
    # ------------
    # Get node of longest past and push in path
    currnode = argmin(-dist)
    push!(path, currnode-1)

    # Run through previous[] to get the path
    while currnode != 1
        currnode = previous[currnode]
        push!(path, currnode-1)
    end
    filter!(x->x!=0, path)

    path
end
