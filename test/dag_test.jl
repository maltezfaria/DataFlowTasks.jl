using LinearAlgebra
using DataFlowScheduler
using DataFlowScheduler: DAG, addnode!, num_nodes, num_edges, addedge!, has_edge, outneighbors, inneighbors,isconnected, adjacency_matrix, addedge_transitive!
using Test

@testset "DAG" begin
    dag = DAG()
    @test num_nodes(dag) == 0
    addnode!(dag,1)
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
    @test isconnected(dag, 1, 4) == false
    addnode!(dag, 3)
    addnode!(dag, 4)
    addedge!(dag,2,4)
    @test isconnected(dag, 2, 4) == true
    @test adjacency_matrix(dag) == [0 1 0 0;
                                    0 0 0 1;
                                    0 0 0 0;
                                    0 0 0 0]
    @test num_edges(addedge_transitive!(dag, 1, 4)) == num_edges(dag) # vtx 1 is already connected to vtx through vtx2
end
