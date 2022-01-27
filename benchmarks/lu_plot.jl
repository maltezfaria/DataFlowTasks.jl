using Test
using DataFlowTasks
using DataFlowTasks.TiledFactorization
using LinearAlgebra
using BenchmarkTools
using VectorizationBase
using RecursiveFactorization

nc = min(Int(VectorizationBase.num_cores()), Threads.nthreads())

PLOT = true
SAVEFIG = true

const TILESIZE = 256
const CAPACITY = 20
sch = DataFlowTasks.JuliaScheduler(CAPACITY)
DataFlowTasks.setscheduler!(sch)

nn = 500:500:5000 |> collect
t_openblas = Float64[]
t_recursive = Float64[]
t_forkjoin = Float64[]
t_dataflow = Float64[]

for m in nn
    # create an SPD matrix
    A = rand(m, m)
    A = (A + adjoint(A)) / 2
    A = A + m * I
    nt = Threads.nthreads()

    # test open blas
    @info "LinearAlgebra"
    @info BLAS.get_config()
    BLAS.set_num_threads(nc)
    @info "NBLAS = $(BLAS.get_num_threads())"
    b = @benchmark lu!(B) setup = (B = copy(A)) evals = 1
    push!(t_openblas, minimum(b).time)

    # test DataFlowTasks parallelism
    @info "DataFlowTasks"
    BLAS.set_num_threads(1)
    @info "NBLAS = $(BLAS.get_num_threads())"
    b = @benchmark TiledFactorization.lu!(B, TILESIZE) setup = (B = copy(A)) evals = 1
    push!(t_dataflow, minimum(b).time)

    @info "RecursiveFactorization"
    BLAS.set_num_threads(1)
    @info "NBLAS = $(BLAS.get_num_threads())"
    b = @benchmark RecursiveFactorization.lu!(B, Val(false)) setup = (B = copy(A)) evals = 1
    push!(t_recursive, minimum(b).time)

    # test fork-join parallelism
    b = @benchmark TiledFactorization._lu_forkjoin!(B) setup = (B = PseudoTiledMatrix(copy(A), TILESIZE))
    push!(t_forkjoin, minimum(b).time)

    # compute the error
    DataFlowTasks.TASKCOUNTER[] = 1 # reset task counter to display how many tasks were created for
    F = TiledFactorization.lu(A)

    BLAS.set_num_threads(8)
    er = norm(F.L * F.U - A, Inf)

    # for m×m tiled matrix, there should be 1/6*(m^3-m) + 1/2*(m^2-m) + m tasks
    # created
    println("="^80)
    @info "m                 = $(m)"
    @info "Number of tasks   = $(DataFlowTasks.TASKCOUNTER[])"
    @info "Number of threads = $(nt)"
    @info "Number of cores   = $(nc)"
    @info "er                = $er"
    println("="^80)
end

if PLOT
    using Plots
    flops = @. 2 / 3 * nn^3 + nn^2
    plot(nn, flops ./ (t_openblas), label = "OpenBlas", xlabel = "n", ylabel = "GFlops/second", m = :x, title = "LU factorization", legend = :bottomright)
    plot!(nn, flops ./ (t_recursive), label = "RecursiveFactorization", m = :x)
    plot!(nn, t_forkjoin ./ 1e9, label = "forkjoin", m = :x)
    plot!(nn, flops ./ (t_dataflow), label = "TiledFactorization", m = :x)
    # peakflops vary, not sure how to measure it. Maybe compute theoretical from
    # cpuinfo?
    # peak = LinearAlgebra.peakflops()
    # plot!(nn,peak/1e9*ones(length(nn)))
    SAVEFIG && savefig(joinpath(DataFlowTasks.PROJECT_ROOT, "benchmarks/luperf.png"))
end
