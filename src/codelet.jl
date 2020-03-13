abstract type AbstractCodelet end

getdata(cl::AbstractCodelet)      = cl.data
getdata_read(cl::AbstractCodelet) = [cl.data[i] for i in 1:length(cl.data) if cl.access_modes[i]===R || cl.access_modes[i]===RW]
getdata_write(cl::AbstractCodelet)= [cl.data[i] for i in 1:length(cl.data) if cl.access_modes[i]===W || cl.access_modes[i]===RW]
cpu_func(cl::AbstractCodelet)     = cl.cpu_func
gpu_func(cl::AbstractCodelet)     = cl.cpu_func
execute_cpu(cl::AbstractCodelet)  = cpu_func(cl)(getdata(cl)...)
execute_gpu(cl::AbstractCodelet)  = gpu_func(cl)(getdata(cl)...)
execute(cl::AbstractCodelet)      = execute_cpu(cl)
getlabel(cl::AbstractCodelet)     = cl.label
haslabel(cl::AbstractCodelet)     = getlabel(cl) != ""

Base.Task(cl::AbstractCodelet)     = Task(() -> execute_cpu(cl))
Base.schedule(cl::AbstractCodelet) = schedule(Task(cl))

function Base.Task(cl::AbstractCodelet,deps::Vector{Task})
    Task() do
        for dep in deps
            wait(dep)
        end
        execute_cpu(cl)
    end
end

Base.@kwdef struct GenericCodelet <: AbstractCodelet
    cpu_func = nothing
    gpu_func = nothing
    data     = nothing
    access_modes = nothing
    label::String = ""
end

Base.@kwdef struct Codelet{T1,T2,T3,T4} <: AbstractCodelet
    cpu_func::T1 = nothing
    gpu_func::T2 = nothing
    data::T3     = nothing
    access_modes::T4 = nothing
    label::String = ""
end

@enum DependencyType Independent=0 Sequential Mutex

function dependency_type(ti::AbstractCodelet,tj::AbstractCodelet)
    dw_i  = getdata_write(ti)  #data read from for task i
    dr_j  = getdata_read(tj)   #data written to for task j
    # if ti writes, and tj reads, then tj must wait for ti
    for di in dw_i
        for dj in dr_j
            if memory_overlap(di,dj)
                return Sequential
            end
        end
    end
    dr_i  = getdata_read(ti)   #data read for  task i
    dw_j  = getdata_write(tj)  #data write for task j
    # if ti reads, and tj writes, then tj must wait for ti
    for di in dr_i
        for dj in dw_j
            if memory_overlap(di,dj)
                return Sequential
            end
        end
    end
    return Independent
end
