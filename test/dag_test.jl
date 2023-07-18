using Test
using LinearAlgebra
using DataFlowTasks
using DataFlowTasks:
    DAG,
    num_nodes,
    num_edges,
    addnode!,
    addedge!,
    has_edge,
    outneighbors,
    inneighbors,
    isconnected,
    addedge_transitive!,
    remove_node!,
    R,
    W,
    RW,
    TaskGraph

@testset "DAG{Int}" begin
    dag = DAG{Int}()
    @test num_nodes(dag) == 0
    addnode!(dag, 1)
    @test num_nodes(dag) == 1
    @test num_edges(dag) == 0
    addnode!(dag, 2)
    @test num_nodes(dag) == 2
    addedge!(dag, 1, 2)
    @test num_edges(dag) == 1
    @test has_edge(dag, 1, 2) == true
    @test has_edge(dag, 2, 1) == false
    @test outneighbors(dag, 1) == Set(2)
    @test inneighbors(dag, 1) == Set()
    @test outneighbors(dag, 2) == Set()
    @test inneighbors(dag, 2) == Set(1)
    addnode!(dag, 3)
    addnode!(dag, 4)
    addedge!(dag, 2, 4)
    @test isconnected(dag, 1, 3) == false
    @test isconnected(dag, 2, 4) == true
    @test isconnected(dag, 1, 4) == true # 1 --> 2 --> 4
    @test num_edges(addedge_transitive!(dag, 1, 4)) == 2 # vtx 1 is already connected to vtx through vtx2
end

@testset "TaskGraph" begin
    dag = TaskGraph()
    C = rand(3, 3)
    cl1 = @dtask rmul!(@RW(C), 2)
    @test num_nodes(dag) == 0
    addnode!(dag, cl1)
    @test num_nodes(dag) == 1
    @test num_edges(dag) == 0
    cl2 = @dtask rmul!(@RW(C), 2)
    addnode!(dag, cl2)
    @test num_nodes(dag) == 2
    addedge!(dag, cl1, cl2)
    @test num_edges(dag) == 1
    @test has_edge(dag, cl1, cl2) == true
    @test has_edge(dag, cl2, cl1) == false
    @test outneighbors(dag, cl1) == Set((cl2,))
    @test inneighbors(dag, cl1) == Set()
    @test outneighbors(dag, cl2) == Set()
    @test inneighbors(dag, cl2) == Set([cl1])
    cl3 = @dtask rmul!(@RW(C), 2)
    cl4 = @dtask rmul!(@RW(C), 2)
    addnode!(dag, cl3)
    addnode!(dag, cl4)
    addedge!(dag, cl2, cl4)
    @test isconnected(dag, cl1, cl3) == false
    @test isconnected(dag, cl2, cl4) == true
    @test isconnected(dag, cl1, cl4) == true # 1 --> 2 --> 4
    @test num_edges(addedge_transitive!(dag, cl1, cl4)) == 2 # vtx 1 is already connected to vtx through vtx2
end

@testset "Buffering" begin
    sz = 10
    dag = DAG{Int}(sz)
    for i in 1:sz
        addnode!(dag, i)
    end
    @test num_nodes(dag) == sz
    t = @async addnode!(dag, 11)
    sleep(0.1)
    @test num_nodes(dag) == sz
    remove_node!(dag, 1)
    sleep(0.1)
    @test num_nodes(dag) == sz
end

@testset "Longest path" begin
    FakeGraph = NamedTuple{(:nodes,)}
    FakeNode  = NamedTuple{(:tag, :weight, :predecessors)}

    DataFlowTasks.topological_sort(g::FakeGraph) = g.nodes
    DataFlowTasks.intags(n::FakeNode) = n.predecessors
    DataFlowTasks.weight(n::FakeNode) = n.weight
    DataFlowTasks.tag(n::FakeNode) = n.tag

    graph = (
        nodes = [
            (tag = 42, weight = 0.1, predecessors = Int[]),
            (tag = 18, weight = 0.1, predecessors = Int[42]),
            (tag = 36, weight = 1.0, predecessors = Int[]),
            (tag = 39, weight = 1.0, predecessors = Int[36]),
            (tag = 10, weight = 0.2, predecessors = Int[]),
            (tag = 11, weight = 0.2, predecessors = Int[10]),
            (tag = 12, weight = 0.2, predecessors = Int[11]),
        ],
    )
    @test DataFlowTasks.longest_path(graph) == [39, 36]

    graph = (
        nodes = [
            (tag = 42, weight = 0.1, predecessors = Int[]),
            (tag = 18, weight = 0.3, predecessors = Int[]),
            (tag = 36, weight = 0.2, predecessors = Int[]),
        ],
    )
    @test DataFlowTasks.longest_path(graph) == [18]
end
