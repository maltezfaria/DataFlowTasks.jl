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
    sz_max::Ref{Int}
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
    return DAG{T}(inoutlist,cond_push,cond_empty,Ref(sz))
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
    push!(dag.inoutlist,kv)
    k,v = kv
    check  && update_edges!(dag,k)
    return dag
end

"""
    update_edges!(dag::DAG,i)

Perform the data-flow analysis to update the edges of node `i`. Both incoming
and outgoing edges are updated.
"""
function update_edges!(dag::DAG,nodej)
    # update dependencies from newer to older and reinfornce transitivity
    for (nodei,_) in Iterators.reverse(dag)
        nodei < nodej  || continue
        dep    = data_dependency(nodei,nodej)
        dep   || continue
        # addedge_transitive!(dag,nodei,nodej)
        addedge!(dag,nodei,nodej)
    end
    return dag
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
    return
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

################################################################################
## visualization
################################################################################
function graphplot(dag)
    str = "strict digraph dag {rankdir=LR;layout=dot;"
    for (k,(inlist,outlist)) in dag.inoutlist
        if isempty(outlist) && isempty(outlist)
            str *= """ $(tag(k));"""
        end

        for j in inlist
            str *= """ $(tag(j)) -> $(tag(k));"""
        end
    end
    str *= "}"
    # return str
    return Graph(str)
end
