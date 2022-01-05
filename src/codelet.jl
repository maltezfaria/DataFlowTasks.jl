"""
    abstract type AbstractCodelet

A basic unit of code which takes some data and does some computations on it.

A codelet should specify the data is uses, and how it accesses it (see [`AccessMode`](@ref)).

# Extended help

Codelets are added to a [`TaskGraph`](@ref) where their dependencies is analyzed
based on the data they access and `AcessMode`. The output of the analysis is
graph with nodes given by the codelets and edges given by a
[`DependencyType`](@ref).
"""
abstract type AbstractCodelet end

"""
    data(cl::AbstractCodelet,[i])

Data to which the codelet has access.
"""
data(cl::AbstractCodelet)        = cl.data
data(cl::AbstractCodelet,i)      = cl.data[i]

"""
    access_mode(cl::AbstractCodelet,[i])

How the codelet can access its data (see [`AccessMode`](@ref)).
"""
access_mode(cl::AbstractCodelet)   = cl.access_mode
access_mode(cl::AbstractCodelet,i) = cl.access_mode[i]

_func(cl::AbstractCodelet) = cl.func

"""
    execute(cl::AbstractCodelet)

Immediately executes the codelet's function, returning the last statement of the function.
"""
execute(cl::AbstractCodelet)      = _func(cl)(data(cl)...)

"""
    label(cl::AbstractCodelet)

Return a string with a label for the codelet. Useful for plotting or debugging.
"""
label(cl::AbstractCodelet)     = cl.label

"""
    Task(cl::AbstractCodelet,[deps])

Creates a `Task` from the codelet which waits for `deps` before executing, where
`deps` is an iterable collection of `Task`s.
"""
Base.Task(cl::AbstractCodelet)     = Task(() -> execute(cl))

function Base.Task(cl::AbstractCodelet, deps)
    Task() do
        for dep in deps
            wait(dep)
        end
        execute(cl)
    end
end

"""
    Codelet <: AbstractCodelet

A generic implementation of [`AbstractCodelet`](@ref) which is not parametrized
on the type of its fields.
"""
Base.@kwdef struct Codelet <: AbstractCodelet
    func
    data
    access_mode
    label::String = ""
    status::Ref{CodeletStatus} = NOSCHEDULER
end

function Base.show(io::IO,cdlt::Codelet)
    print(io,"Codelet for function ")
    print(io,string(cdlt.func))
    print(io," (Status $(cdlt.status[]))")
end

getstatus(cdlt::Codelet) = cdlt.status[]
setstatus(cdlt::Codelet,st::CodeletStatus) = (cdlt.status[] = st)

function execute(cl::Codelet)
    setstatus(cl,RUNNING)
    @debug "$cl on thread $(Threads.threadid())"
    _func(cl)(data(cl)...)
    setstatus(cl,FINISHED)
    return cl
end

"""
    dependency_type(cl1::AbstractCodelet,cl2::AbstractCodelet)

Determines the dependency between `cl1` and `cl2` based on the data they read
from and write to.

This function can be overloaded to further refine the inferred dependency to
include e.g. mutex dependencies.

See also: [`DependencyType`](@ref)
"""
function dependency_type(ti::AbstractCodelet, tj::AbstractCodelet)
    _dependency_type(ti.data, tj.data, ti.access_mode, tj.access_mode)
    # for (di,mi) in zip(data(ti),access_mode(ti))
    #     for (dj,mj) in zip(data(tj),access_mode(tj))
    #         # treat the data overlap case
    #         mi == READ && mj == READ && continue
    #         if memory_overlap(di,dj)
    #             cond1 = (mi==READ || mi==READWRITE) && (mj==WRITE || mj==READWRITE)
    #             cond2 = (mj==READ || mj==READWRITE) && (mi==WRITE || mi==READWRITE)
    #             if cond1 || cond2
    #                 return InferredSequential
    #             end
    #         end
    #     end
    # end
    # return InferredIndependent
end

@generated function _dependency_type(idata::Tuple, jdata::Tuple, iaccess::NTuple{M}, jaccess::NTuple{N}) where {M,N}
    acc = :(nothing)
    for i in 1:M
        for j in 1:N
            ex = quote
                cond1 = iaccess[$i] == READ &&  jaccess[$j] == READ
                cond2 = iaccess[$i] == NOCHECK
                cond3 = jaccess[$j] == NOCHECK
                if !(cond1 || cond2 || cond3)
                    if memory_overlap(idata[$i], jdata[$j])
                        return InferredSequential
                    end
                end
            end
            acc = :($acc;$ex)
        end
    end
    acc = :($acc;(return InferredIndependent))
    acc
end

"""
    memory_overlap(di,dj)::Bool

Determine if data `di` and `dj` have overlapping memory in the sense that
mutating `di` can change `dj` (or vice versa). This function is used to build
the dependency graph between codelets.

A generic version is implemented returning `true` (but printing a warning)
unless `di` or `dj` is of bitstype. Users of [`@codelet`](@ref) should overload
this function for the specific data types used in the arguments to avoid having
a `TaskGraph` with unnecessary connection.
"""
function memory_overlap(di,dj)
    # if either is of bits type there is no dependency
    if isbits(di) || isbits(dj)
        return false
    else
        @warn "memory_overlap(::$(typeof(di)),::$(typeof(dj))) not implemented. Defaulting to `true`"
        return true
    end
end

"""
    @codelet f(x...)

Create a codelet from the function `f(x...)`. This macros uses the
[`CODELET_DICT`](@ref) to automatically fill in the [`AcessMode`](@ref) for the
arguments `x...`. To extend it to work on your own functions you should append
the required entry to `CODELET_DICT`.

# Examples
```julia
using DataFlowScheduler
using LinearAlgebra
A = rand(5,5)
cdlt = @codelet rmul!(A,2)
```
"""
macro codelet(ex)
    @capture(ex, f_(xs__))
    n   = length(xs)
    key = (f, n)
    modes = get(CODELET_DICT, key, nothing)
    if modes === nothing
        msg =  "@codelet macro unable to match $key to an entry in `CODELET_DICT`."
        return :(error($msg))
    else
        args = ntuple(i -> xs[i], n)
        args = :($(args...),)
        return esc(:(Codelet(func=$f, data=$args, access_mode=$modes)))
    end
end
