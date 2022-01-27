using Test
using DataFlowTasks
using DataFlowTasks.TiledFactorization
using LinearAlgebra
using BenchmarkTools
using VectorizationBase
using RecursiveFactorization

nc = min(Int(VectorizationBase.num_cores()), Threads.nthreads())

sch = DataFlowTasks.JuliaScheduler(20)
DataFlowTasks.setscheduler!(sch)

m         = 4000
# create an SPD matrix
A = rand(m,m)
# A = (A + adjoint(A))/2
# A = A + m*I
nt = Threads.nthreads()

@info "OpenBLAS"
@info BLAS.get_config()
BLAS.set_num_threads(nc)
@info "NBLAS = $(BLAS.get_num_threads())"
tnat = @btime lu!(B) setup=(B=copy(A)) evals=1

@info "DataFlowTasks"
BLAS.set_num_threads(1)
@info "NBLAS = $(BLAS.get_num_threads())"
tdf = @btime TiledFactorization.lu!(B) setup=(B=copy(A)) evals=1
# tfj = @btime TiledFactorization._cholesky_forkjoin!(B) setup=(B=PseudoTiledMatrix(copy(A),150))

DataFlowTasks.TASKCOUNTER[] = 0

# F = TiledFactorization._cholesky_forkjoin!(PseudoTiledMatrix(copy(A),256))
F = TiledFactorization.lu(A)

BLAS.set_num_threads(8)
er = norm(F.L*F.U-A,Inf)

F = RecursiveFactorization.lu(A,NoPivot())
er_blas = norm(F.L*F.U-A,Inf)

using MKL
@info "MKL cholesky"
@info BLAS.get_config()
BLAS.set_num_threads(nc)
@info "NBLAS = $(BLAS.get_num_threads())"
tnat = @btime cholesky!(B) setup=(B=copy(A)) evals=1

# for m×m tiled matrix, there should be 1/6*(m^3-m) + 1/2*(m^2-m) + m tasks created
@info "Number of tasks = $(DataFlowTasks.TASKCOUNTER[])"
@info "Number of threads = $(nt)"
@info "Number of cores = $(nc)"
@info er,er_blas
