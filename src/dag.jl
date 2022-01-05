"""
    DAG{T<:Unsigned}

Simple representation of a directed acyclic graph with up to `typemax(T)` nodes.

Each node is identified by an integer `i::T`. The `DAG` stores explicitly the
list of incoming and outgoing edges.

This `DAG` structure represents a computation graph, where the computation of
`node[i]` must wait for the computation of all other nodes in
`inneighbors(dag,i)`. The index `i` is the natural order under which the
computations would be carried out on a serial execution. Because of this, it is
implicit in this graph that if `j ∈ outlist[i]`, then `j>i`; i.e. the graph
connects values in an increasing order. In particular this means that for each
node `i`, all elements of `inneighbors(dag,i)` should be smaller than `i`, and  all
elements in `outneighbors(dag,i)` should be larger than `i`.
"""
Base.@kwdef struct DAG{T<:Unsigned}
    inoutlist::Dict{T,Tuple{Set{T},Set{T}}}  = Dict{UInt,Tuple{Set{UInt},Set{UInt}}}()
end

"""
    num_nodes(dag::DAG)

Number of nodes in the `DAG`.
"""
num_nodes(dag::DAG) = length(dag.inoutlist)

"""
    ne(dag::DAG)

Number of edges in the `DAG`.
"""
function num_edges(dag::DAG)
    acc = 0
    for (k,(inlist,outlist)) in dag.inoutlist
        acc += length(inlist)
    end
    return acc
end

inneighbors(dag::DAG,i)  = dag.inoutlist[i][1]
outneighbors(dag::DAG,i) = dag.inoutlist[i][2]

function Base.empty!(dag::DAG)
    empty!(dag.inoutlist)
    return dag
end

"""
    addedge!(dag,i,j)

Add (directed) edge connecting node `i` to node `j` in the `dag`.
"""
function addedge!(dag::DAG,i,j)
    push!(outneighbors(dag,i),j)
    push!(inneighbors(dag,j),i)
    return dag
end

addnode!(dag::DAG{T},kv::Pair) where {T} = push!(dag.inoutlist,kv)
addnode!(dag::DAG{T},i::Int) where {T}   = push!(dag.inoutlist,i=>(Set{T}(),Set{T}()))

"""
    isconnected(dag,i,j)

Check if there is path connecting `i` to `j`.
"""
function isconnected(dag::DAG,i,j)
    for k in outneighbors(dag,i)
        if k==j
            return true
        elseif k>j
            continue
        else#k<i
            isconnected(dag,k,j) && (return true)
        end
    end
    return false
end

"""
    addedge_transitive!(dag,i,j)

Add edge connecting nodes `i` and `j` if there is no path connecting them already.
"""
addedge_transitive!(dag,i,j) = isconnected(dag,i,j) ? dag : addedge!(dag,i,j)

"""
    has_edge(dag,i,j)

Check if there is an edge connecting `i` to `j`.
"""
has_edge(dag::DAG,i,j) = j ∈ outneighbors(dag,i)

function remove_node!(dag,i)
    @assert isempty(inneighbors(dag,i))
    # remove i from the inlist of all its outneighbors
    for j in outneighbors(dag,i)
        pop!(inneighbors(dag,j),i)
    end
    return dag
end

"""
    adjacency_matrix(dag)

Construct the adjacency matrix of `dag`.
"""
function adjacency_matrix(dag::DAG)
    n = num_nodes(dag)
    S = zeros(Bool,n,n)
    for i in 1:n
        J = outneighbors(dag,i)
        for j in J
            S[i,j] = 1
        end
    end
    return S
end

################################################################################
## visualization
################################################################################
graphplot(dag::DAG,args...;kwargs...) = graphplot(adjacency_matrix(dag),args...;kwargs...)
