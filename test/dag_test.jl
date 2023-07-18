using Test
using LinearAlgebra
import DataFlowTasks as DFT

@testset "DAG{Int}" begin
    dag = DFT.DAG{Int}()
    @test DFT.num_nodes(dag) == 0
    DFT.addnode!(dag, 1)
    @test DFT.num_nodes(dag) == 1
    @test DFT.num_edges(dag) == 0
    DFT.addnode!(dag, 2)
    @test DFT.num_nodes(dag) == 2
    DFT.addedge!(dag, 1, 2)
    @test DFT.num_edges(dag) == 1
    @test DFT.has_edge(dag, 1, 2) == true
    @test DFT.has_edge(dag, 2, 1) == false
    @test DFT.outneighbors(dag, 1) == Set(2)
    @test DFT.inneighbors(dag, 1) == Set()
    @test DFT.outneighbors(dag, 2) == Set()
    @test DFT.inneighbors(dag, 2) == Set(1)
    DFT.addnode!(dag, 3)
    DFT.addnode!(dag, 4)
    DFT.addedge!(dag, 2, 4)
    @test DFT.isconnected(dag, 1, 3) == false
    @test DFT.isconnected(dag, 2, 4) == true
    @test DFT.isconnected(dag, 1, 4) == true # 1 --> 2 --> 4
    @test DFT.num_edges(DFT.addedge_transitive!(dag, 1, 4)) == 2 # vtx 1 is already connected to vtx through vtx2
end

@testset "Buffering" begin
    sz = 10
    dag = DFT.DAG{Int}(sz)
    for i in 1:sz
        DFT.addnode!(dag, i)
    end
    @test DFT.num_nodes(dag) == sz
    t = @async DFT.addnode!(dag, 11)
    sleep(0.1)
    @test DFT.num_nodes(dag) == sz
    DFT.remove_node!(dag, 1)
    sleep(0.1)
    @test DFT.num_nodes(dag) == sz
end

@testset "Longest path" begin
    FakeGraph = NamedTuple{(:nodes,)}
    FakeNode  = NamedTuple{(:tag, :weight, :predecessors)}

    DFT.topological_sort(g::FakeGraph) = g.nodes
    DFT.intags(n::FakeNode) = n.predecessors
    DFT.weight(n::FakeNode) = n.weight
    DFT.tag(n::FakeNode) = n.tag

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
    @test DFT.longest_path(graph) == [39, 36]

    graph = (
        nodes = [
            (tag = 42, weight = 0.1, predecessors = Int[]),
            (tag = 18, weight = 0.3, predecessors = Int[]),
            (tag = 36, weight = 0.2, predecessors = Int[]),
        ],
    )
    @test DFT.longest_path(graph) == [18]
end
