"""
    struct DAG{T}

Representation of a directed acyclic graph containing nodes of type `T`. The
list of nodes with edges coming into a node `i` can be retrieved using
[`inneighbors(dag,i)`](@ref); similarly, the list of nodes with edges leaving
from `i` can be retrieved using [`outneighbors(dag,i)`](@ref).

`DAG` is a buffered structure with a buffer of size `sz_max`: calling
[`addnode!`](@ref) on it will block if the `DAG` has more than `sz_max`
elements.

The `DAG` is thread-safe: mutating operations acquire `dag.lock`, and the
conditions `cond_push` and `cond_empty` are associated with that same lock.
"""
struct DAG{T}
    inoutlist::OrderedDict{T, Tuple{Set{T}, Set{T}}}
    cond_push::Threads.Condition
    cond_empty::Threads.Condition
    lock::ReentrantLock
    sz_max::Base.RefValue{Int}
    _buffer::Set{Int} # used to keep track of visited nodes when needed
end

# Tags of the `DataFlowTask`s, unique across all the DAGs so that a log can hold
# the tasks of several DAGs. Within a DAG, they are increasing in insertion order.
const TASK_COUNTER = Threads.Atomic{Int}(0)

"""
    DAG{T}(sz)

Create a buffered `DAG` holding a maximum of `sz` nodes of type `T`.
"""
function DAG{T}(sz = typemax(Int)) where {T}
    sz = sz == Inf ? typemax(Int) : Int(sz)
    if sz <= 0
        throw(ArgumentError("DAG buffer size must be a positive integer"))
    end
    inoutlist = OrderedDict{T, Tuple{Set{T}, Set{T}}}()
    lock = ReentrantLock()
    cond_push = Threads.Condition(lock)
    cond_empty = Threads.Condition(lock)
    _buffer = Set{Int}()
    return DAG{T}(inoutlist, cond_push, cond_empty, lock, Ref(sz), _buffer)
end

function Base.resize!(dag::DAG, sz)
    sz = sz == Inf ? typemax(Int) : Int(sz)
    msg = """cannot resize `dag` (desired capacity too small to contain the
    already present nodes)"""
    lock(dag)
    try
        num_nodes(dag) > sz && error(msg)
        dag.sz_max[] = sz
        # wake up tasks waiting for room in the dag
        notify(dag.cond_push)
    finally
        unlock(dag)
    end
    return sz
end

Base.isempty(dag::DAG) = isempty(dag.inoutlist)
Base.getindex(dag::DAG, i) = dag.inoutlist[i]

Base.lock(dag::DAG) = lock(dag.lock)
Base.unlock(dag::DAG) = unlock(dag.lock)

"""
    nodes(dag::DAG)

Return an iterator over the nodes of `dag`.
"""
nodes(dag::DAG) = keys(dag.inoutlist)

"""
    num_nodes(dag::DAG)

Number of nodes in the `DAG`.
"""
num_nodes(dag::DAG) = dag |> nodes |> length

"""
    num_edges(dag::DAG)

Number of edges in the `DAG`.
"""
function num_edges(dag::DAG)
    acc = 0
    for (_, (inlist, _)) in dag.inoutlist
        acc += length(inlist)
    end
    return acc
end

"""
    inneighbors(dag,i)

List of predecessors of `i` in `dag`.
"""
inneighbors(dag::DAG, i) = dag.inoutlist[i][1]

"""
    outneighbors(dag,i)

List of successors of `j` in `dag`.
"""
outneighbors(dag::DAG, i) = dag.inoutlist[i][2]

"""
    capacity(dag)

The maximum number of nodes that `dag` can contain.
"""
capacity(dag::DAG) = dag.sz_max[]

function Base.empty!(dag::DAG)
    lock(dag)
    try
        empty!(dag.inoutlist)
        notify(dag.cond_push)
        notify(dag.cond_empty)
    finally
        unlock(dag)
    end
    return dag
end

Iterators.reverse(dag::DAG) = Iterators.reverse(dag.inoutlist)
Base.iterate(dag::DAG, state = 1) = iterate(dag.inoutlist, state)

"""
    addedge!(dag,i,j)

Add (directed) edge connecting node `i` to node `j` in the `dag`.
"""
function addedge!(dag::DAG{T}, i::T, j::T) where {T}
    @assert i < j
    push!(outneighbors(dag, i), j)
    push!(inneighbors(dag, j), i)
    return dag
end

"""
    addnode!(dag,(k,v)::Pair[, check=false, logger=nothing, time_request=0])
    addnode!(dag,k[, check=false, logger=nothing, time_request=0])

Add a node to the `dag`. If passed only a key `k`, the value `v` is initialized
as empty (no edges added). The `check` flag is used to indicate if a data flow
analysis should be performed to update the dependencies of the newly inserted
node.

If a `logger` is given, the insertion is recorded in it as an
[`InsertionLog`](@ref), requested at `time_request` (by default, when the
insertion begins).
"""
function addnode!(dag::DAG{T}, i::T, check = false, logger = nothing, time_request = UInt64(0)) where {T}
    return addnode!(dag, i => (Set{T}(), Set{T}()), check, logger, time_request)
end

function addnode!(dag::DAG, kv::Pair, check = false, logger = nothing, time_request = UInt64(0))
    k, v = kv
    lock(dag)
    try
        while num_nodes(dag) >= dag.sz_max[]
            wait(dag.cond_push)
        end
        # without a logger, the insertion is not timed to avoid any overhead
        if isnothing(logger)
            _addnode!(dag, kv, check)
        else
            t₀ = time_ns()
            stats = Base.gc_num()
            _addnode!(dag, kv, check)
            diff = Base.GC_Diff(Base.gc_num(), stats)
            t₁ = time_ns()
            tid = Threads.threadid()
            time_request == 0 && (time_request = t₀)
            record!(logger, InsertionLog(time_request, t₀, t₁, diff.total_time, tag(k), tid))
        end
    finally
        unlock(dag)
    end
    return dag
end

function _addnode!(dag::DAG, kv::Pair, check)
    k, _ = kv
    k isa DataFlowTask && (k.tag = Threads.atomic_add!(TASK_COUNTER, 1) + 1)
    push!(dag.inoutlist, kv)
    check && update_edges!(dag, k)
    return dag
end

"""
    update_edges!(dag::DAG, i, linear = _linear_dag())

Perform the data-flow analysis to update the edges of node `i`. Both incoming
and outgoing edges are updated. If `linear` is `true`, `i` only depends on the
previous node (see [`force_linear_dag`](@ref)).
"""
function update_edges!(dag::DAG, nodej, linear = _linear_dag())
    transitively_connected = dag._buffer
    empty!(transitively_connected)
    # update dependencies from newer to older and reinfornce transitivity by
    # skipping predecessors of nodes which are already connected
    for (nodei, _) in Iterators.reverse(dag)
        nodei == nodej && continue
        if linear
            addedge!(dag, nodei, nodej)
            break
        end
        ti = tag(nodei)
        (ti ∈ transitively_connected) && continue
        # tasks are handled differently when they appear in the data in that
        # they are checked directly agains the nodej.task field
        data_dependency(nodei, nodej) || continue
        addedge!(dag, nodei, nodej)
        update_transitively_connected!(transitively_connected, nodei, dag)
    end

    return dag
end

function update_transitively_connected!(transitively_connected, node, dag)
    for nodei in inneighbors(dag, node)
        ti = tag(nodei)
        (ti ∈ transitively_connected) && continue
        push!(transitively_connected, ti)
        update_transitively_connected!(transitively_connected, nodei, dag)
    end
    return transitively_connected
end

"""
    isconnected(dag,i,j)

Check if there is a path in `dag` connecting `i` to `j`.
"""
function isconnected(dag::DAG, i, j)
    for k in inneighbors(dag, j)
        if k == i
            return true
        elseif k < i
            continue
        else #k>i
            isconnected(dag, i, k) && (return true)
        end
    end
    return false
end

"""
    addedge_transitive!(dag,i,j)

Add edge connecting nodes `i` and `j` if there is no path connecting them already.
"""
function addedge_transitive!(dag, i, j)
    return isconnected(dag, i, j) ? dag : addedge!(dag, i, j)
end

"""
    has_edge(dag,i,j)

Check if there is an edge connecting `i` to `j`.
"""
has_edge(dag::DAG, i, j) = j ∈ outneighbors(dag, i)

"""
    remove_node!(dag::DAG,i[, logger=nothing])

Remove node `i` and all of its edges from `dag`. If a `logger` is given, the
removal is recorded in it as a [`CleanupLog`](@ref).
"""
function remove_node!(dag::DAG, i, logger = nothing)
    # without a logger, the removal is not timed to avoid any overhead
    t₀ = isnothing(logger) ? UInt64(0) : time_ns()
    lock(dag)
    try
        # `i` may have been removed by `empty!` while it was running
        haskey(dag.inoutlist, i) || return
        if !isempty(inneighbors(dag, i))
            @warn "removing a node with incoming neighbors"
        end
        (inlist, outlist) = pop!(dag.inoutlist, i)
        # remove i from the inlist of all its outneighbors
        for j in outlist
            pop!(inneighbors(dag, j), i)
        end
        # recorded before notifying, so that the removal is logged once waiting
        # for the dag to be empty returns
        isnothing(logger) || record!(logger, CleanupLog(tag(i), t₀, time_ns()))
        # notify a task waiting to push into the dag
        notify(dag.cond_push, nothing; all = false)
        # if dag is empty, notify
        isempty(dag) && notify(dag.cond_empty)
    finally
        unlock(dag)
    end
    return
end

function Base.show(io::IO, dag::DAG{T}) where {T}
    n = num_nodes(dag)
    e = num_edges(dag)
    s1 = n == 1 ? "" : "s"
    s2 = e == 1 ? "" : "s"
    return print(
        io,
        typeof(dag),
        " with $n node$s1 and $e edge$s2 (capacity of $(dag.sz_max[]) nodes)",
    )
end

############################################################################
#                           Longest Path
############################################################################

#=
    longest_path(graph) -> path

Finds the longest path of a DAG `graph`, and returns the nodes constituting it
in reverse order.

Required interface for the graph:
- topological_sort(graph) -> collection of nodes in `graph`, sorted in topological order
- intags(node)            -> collection of predecessors of `node` (identified by their tags)
- weight(node)            -> cost of `node` (a positive Float64)
- tag(node)               -> id of `node` (a strictly positive Int)
=#
function longest_path(graph)
    # lp[n] = (length, n′)   where:
    # - length is the length of the longest path leading to n
    # - n′ is the predecessor of n in this path (or 0 if n is the first node in the path)
    lp = Dict{Int64, Tuple{Float64, Int}}()

    for node in topological_sort(graph)
        # Find the predecessor with the longest path leading to it
        path_length = 0.0
        predecessor = 0
        for n in intags(node)
            pl, _ = lp[n]
            if pl > path_length
                path_length = pl
                predecessor = n
            end
        end

        # Augment the longest path with the weight of the current node
        path_length += weight(node)
        lp[tag(node)] = (path_length, predecessor)
    end

    # Find the node with the longest path
    node = argmax(lp)
    path = [node]

    # Backtrack to the beginning of the path
    while true
        _, node = lp[node]
        node == 0 && break
        push!(path, node)
    end
    return path
end
