### A Pluto.jl notebook ###
# v0.19.32

using Markdown
using InteractiveUtils

# ╔═╡ 8cfb34be-3941-485f-a377-1c43c46f23c3
begin
	import Pkg
	Pkg.add(name="DataFlowTasks", rev="main")
	using DataFlowTasks
	DataFlowTasks.stack_weakdeps_env!()
	using GraphViz, CairoMakie, Random, BenchmarkTools
end

# ╔═╡ 1124b141-f175-4729-8a90-0a220a6142fd
md"""
# Demo: parallel merge sort
"""

# ╔═╡ 707b374a-74a2-48d0-926f-175df43aafac
begin
	v = randperm(32)
	barplot(v)
end

# ╔═╡ 7155532d-6598-45ee-9078-afd7b3fe6431
begin
	@views sort!(v[1:16])
	@views sort!(v[17:32])
	
	barplot(v; color=ceil.(Int, eachindex(v)./16), colormap=:Paired_4, colorrange=(1,4))
end

# ╔═╡ 8a06f256-76a0-477a-9d48-f7b086d8afb6
function merge!(dest, left, right)
    (i, j) = (1, 1)
    (I, J) = (length(left), length(right))
    @assert I + J == length(dest)
    @inbounds for k in eachindex(dest)
        if i <= I && (j > J || left[i] < right[j])
            dest[k] = left[i]; i += 1
        else
            dest[k] = right[j]; j+=1
        end
    end
end

# ╔═╡ d64244b8-5faf-451e-b78e-9b16afe59546
begin
	buf = similar(v)
	@views merge!(buf, v[1:16], v[17:32])
	barplot(buf)
end

# ╔═╡ 46317a46-f987-4293-bb6c-460bd5d2a19d
function merge_sort!(vec, buf=similar(vec))
    N = length(vec)
    if N < 64
        sort!(vec, alg=InsertionSort)
        return vec
    end

    mid = N ÷ 2

    @assert length(buf) == N
    left  = @view vec[begin:mid]; left_buf  = @view buf[begin:mid]
    right = @view vec[mid+1:end]; right_buf = @view buf[mid+1:end]

    merge_sort!(left,  left_buf)
    merge_sort!(right, right_buf)

    merge!(buf, left, right)
    copyto!(vec, buf)
end


# ╔═╡ 4fc17777-1d09-4853-84fc-aed5909db94f
begin
	N = 100_000
	data = rand(N)
	buf_ = similar(data)
	@assert issorted(merge_sort!(copy(data)))
	bench_seq = @benchmark merge_sort!(w, $buf_) setup=(w=copy(data)) evals=1
end

# ╔═╡ 1a56c2a4-167f-49fa-ac06-4f71d21f6227
function merge_sort_dft_async!(vec, buf=similar(vec))
    N = length(vec)
    if N < 8192
        return @dspawn merge_sort!(@RW(vec), @W(buf)) label="sort\n$N"
    end

    @assert length(buf) >= N
    
    mid = N ÷ 2

    left  = @view vec[begin:mid]; left_buf  = @view buf[begin:mid]
    right = @view vec[mid+1:end]; right_buf = @view buf[mid+1:end]
    merge_sort_dft_async!(left,  left_buf)
    merge_sort_dft_async!(right, right_buf)

    @dspawn merge!(@W(buf), @R(left), @R(right)) label="merge\n$N"
    @dspawn copyto!(@W(vec), @R(buf)) label="copy\n$N"
end

# ╔═╡ ad0b2021-51f1-4c93-87f2-360393bf464d
merge_sort_dft!(vec, buf=similar(vec)) = fetch(merge_sort_dft_async!(vec, buf))

# ╔═╡ 88e1992e-7e8d-40ef-a552-ff966482aa0a
begin
	@assert issorted(merge_sort_dft!(copy(data)))
	bench_dft = @benchmark merge_sort_dft!(w, $buf_) setup=(w=copy(data)) evals=1
end

# ╔═╡ b00f3a55-59d8-4ae7-9f2f-fbfee58f9101
(; nthreads = Threads.nthreads(),
speedup = minimum(bench_seq).time / minimum(bench_dft).time)

# ╔═╡ faebd63f-ff87-4e7a-9b6c-4168c3dd82f0
log_info = DataFlowTasks.@log merge_sort_dft!(copy(data))

# ╔═╡ 2dc9f8b7-ed10-4978-ac8d-b31f3db17555
begin
	categories = ["sort", "merge", "copy"]
	DataFlowTasks.describe(log_info; categories)
end

# ╔═╡ b09e1a18-01b3-48d0-8ac3-4bb981d79da6

g = GraphViz.Graph(log_info)

# ╔═╡ 5d0e38cd-8f77-4d28-8f2d-43ceb4e7005c
plot(log_info; categories)

# ╔═╡ Cell order:
# ╟─1124b141-f175-4729-8a90-0a220a6142fd
# ╠═8cfb34be-3941-485f-a377-1c43c46f23c3
# ╠═707b374a-74a2-48d0-926f-175df43aafac
# ╠═7155532d-6598-45ee-9078-afd7b3fe6431
# ╠═8a06f256-76a0-477a-9d48-f7b086d8afb6
# ╠═d64244b8-5faf-451e-b78e-9b16afe59546
# ╠═46317a46-f987-4293-bb6c-460bd5d2a19d
# ╠═4fc17777-1d09-4853-84fc-aed5909db94f
# ╠═1a56c2a4-167f-49fa-ac06-4f71d21f6227
# ╠═ad0b2021-51f1-4c93-87f2-360393bf464d
# ╠═88e1992e-7e8d-40ef-a552-ff966482aa0a
# ╠═b00f3a55-59d8-4ae7-9f2f-fbfee58f9101
# ╠═faebd63f-ff87-4e7a-9b6c-4168c3dd82f0
# ╠═2dc9f8b7-ed10-4978-ac8d-b31f3db17555
# ╠═b09e1a18-01b3-48d0-8ac3-4bb981d79da6
# ╠═5d0e38cd-8f77-4d28-8f2d-43ceb4e7005c
