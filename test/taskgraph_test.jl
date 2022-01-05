using Test
using DataFlowScheduler
using LinearAlgebra
using DataFlowScheduler: num_tasks, num_nodes, num_edges,addtask!, pending_tasks_worker!, adjacency_matrix

@testset "Creation" begin
    tg = TaskGraph()
    # since we want to check that the graph and its dependencies are build
    # correctly, we will only activate the worker that takes pending tasks and
    # pushes them to the dag
    @async DataFlowScheduler.pending_tasks_worker!(tg)
    m,n = 10,10
    A  = rand(m,n)
    B  = rand(m,n)
    C  = rand(m,n)
    cl1 = @codelet rmul!(C,2)
    addtask!(tg,cl1)
    # yield so that task processing pending jobs will run and update dag with
    # new task
    yield()
    @test num_tasks(tg) == 1
    @test num_edges(tg) == 0

    cl2 = @codelet axpy!(2,C,A)
    addtask!(tg,cl2)
    yield()
    @test num_edges(tg) == 1 #edge automatically added to data dependency between cl1 and cl2
    @test num_tasks(tg) == 2
    @test num_nodes(tg.graph) == 2
    cl3 = @codelet rmul!(C,2)
    addtask!(tg,cl3)
    yield()
    @test num_edges(tg) == 2 #edge automatically added between 2 and 3, but NOT between 1 and 3 by transitivity
    @test num_tasks(tg) == 3
    @test adjacency_matrix(tg) == [0 1 0;
                                    0 0 1;
                                    0 0 0]
end
@testset "@schedule" begin
    tg = TaskGraph()
    m,n = 10,10
    A  = rand(m,n)
    @schedule tg rmul!(A,2)
    @schedule tg rmul!(A,2)
end
