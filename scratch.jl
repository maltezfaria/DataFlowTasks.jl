using DataFlowTasks
using DataFlowTasks: R,W,RW

using DataFlowTasks: memory_overlap

struct CirculantMatrix
    data::Vector{Float64}
end

v = rand(5)
M = CirculantMatrix(v)

Base.sum(M::CirculantMatrix) = length(M.data)*sum(M.data)

sum(M)

d1 = @dspawn begin
    sleep(10)
    println("I write to v")
    fill!(v,0)
end (v,) (W,)

d2 = @dspawn begin
    println("d2: I wait for d1 due to an implicit dependency")
    sum(v)
end (v,) (R,)

d3 = @dspawn begin
    res = sum(fetch(d1))
    println("d3: I wait for d1 due to an explicit dependency")
    res
end () ()


fetch(d2)

using DataFlowTasks: R,W,RW

let A=ones(100)

    d1 = @dspawn begin
        # write to A
        sleep(2)
        fill!(A,0)
    end (A,) (W,)

    d2 = @dspawn begin
        # some long computation
        sleep(10)
        # reduce A
        sum(A)
    end (A,) (R,)

    d3 = @dspawn begin
        # another reduction on A
        sum(x->sin(x),A)
    end (A,) (R,)

    t = @elapsed c = fetch(d3)

    t,c
end


function run_task(t::Task)
    Base.sigatomic_begin()
    Base.invokelatest(t.code)
    Base.task_done_hook(t)
end

using Dagger

d1 = Dagger.@spawn begin
    for i in eachindex(A)
        A[i] = log(A[i])
    end
end

d2 = Dagger.@spawn begin
    # reduce A
    sum(A)
end

c = fetch(d2) # 0

n = 100000
A = ones(n)

d1 = Threads.@spawn begin
    for i in eachindex(A)
        A[i] = log(A[i])
    end
end

d2 = Threads.@spawn begin
    # reduce A
    sum(A)
end

c = fetch(d2) # 0
