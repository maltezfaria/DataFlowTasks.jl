using Test
using DataFlowTasks
using DataFlowTasks.TiledFactorization
using LinearAlgebra
using BenchmarkTools
using VectorizationBase

nc = min(Int(VectorizationBase.num_cores()), Threads.nthreads())

PLOT = true

const TILESIZE = 256
const CAPACITY = 20
sch = DataFlowTasks.JuliaScheduler(CAPACITY)
DataFlowTasks.setscheduler!(sch)

nn    = 500:500:7000 |> collect
t_openblas = Float64[]
# t_forkjoin = Float64[]
t_dataflow = Float64[]

for m in nn
    # create an SPD matrix
    A = rand(m,m)
    A = (A + adjoint(A))/2
    A = A + m*I
    nt = Threads.nthreads()

    # test open blas
    @info "OpenBLAS cholesky"
    @info BLAS.get_config()
    BLAS.set_num_threads(nc)
    @info "NBLAS = $(BLAS.get_num_threads())"
    b = @benchmark cholesky!(B) setup=(B=copy(A)) evals=1
    push!(t_openblas,minimum(b).time)


    # test DataFlowTasks parallelism
    @info "pseudotiled cholesky"
    BLAS.set_num_threads(1)
    @info "NBLAS = $(BLAS.get_num_threads())"
    b = @benchmark TiledFactorization.cholesky!(B) setup=(B=copy(A)) evals=1
    push!(t_dataflow,minimum(b).time)

    # test fork-join parallelism
    # b = @benchmark TiledFactorization._cholesky_forkjoin!(B) setup=(B=PseudoTiledMatrix(copy(A),TILESIZE))
    # push!(t_forkjoin,minimum(b).time)

    # compute the error
    DataFlowTasks.TASKCOUNTER[] = 1 # reset task counter to display how many tasks were created for
    F = TiledFactorization.cholesky(A)

    BLAS.set_num_threads(8)
    er = norm(F.L*F.U-A,Inf)

    F = cholesky!(copy(A))
    er_blas = norm(F.L*F.U-A,Inf)

    # I don't know how to "trampoline" between OpenBLAS and MKL, so this should
    # be benchmarked separetly for now.
    # using MKL
    # @info "MKL cholesky"
    # @info BLAS.get_config()
    # BLAS.set_num_threads(nc)
    # @info "NBLAS = $(BLAS.get_num_threads())"
    # b = @benchmark cholesky!(B) setup=(B=copy(A)) evals=1

    # for m×m tiled matrix, there should be 1/6*(m^3-m) + 1/2*(m^2-m) + m tasks
    # created
    println("="^80)
    @info "m                 = $(m)"
    @info "Number of tasks   = $(DataFlowTasks.TASKCOUNTER[])"
    @info "Number of threads = $(nt)"
    @info "Number of cores   = $(nc)"
    @info "er                = $er"
    @info "er_blas           = $er_blas"
    println("="^80)
end

# if PLOT
#     using Plots
#     plot(nn,t_openblas./(nn.^3),label="openblas",xlabel="n",ylabel="time (s)",m=:x,title="Cholesky factorization")
#     # plot!(nn,t_forkjoin./1e9,label="forkjoin",m=:x)
#     plot!(nn,t_dataflow./(nn.^3),label="TiledFactorization+dataflow",m=:x)
# end

if PLOT
    using Plots
    flops = @. 1/3*nn^3 + 1/2*nn^2
    plot(nn,flops./(t_openblas),label="openblas",xlabel="n",ylabel="GFlops/second",m=:x,title="Cholesky factorization")
    # plot!(nn,t_forkjoin./1e9,label="forkjoin",m=:x)
    plot!(nn,flops./(t_dataflow),label="TiledFactorization+dataflow",m=:x)
    # peakflops vary, not sure how to measure it. Maybe use cpuinfo?
    # peak = LinearAlgebra.peakflops()
    # plot!(nn,peak/1e9*ones(length(nn)))
end
