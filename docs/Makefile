do: setup doctest generate

setup:
	julia --project -e '                     \
            using Pkg;                           \
            Pkg.develop(PackageSpec(path="..")); \
            Pkg.instantiate()'

doctest:
	julia --project -e '                    \
            using Documenter: DocMeta, doctest; \
            using CairoMakie, GraphViz;         \
            using DataFlowTasks;                \
            DocMeta.setdocmeta!(DataFlowTasks, :DocTestSetup, :(using DataFlowTasks); recursive=true); \
            doctest(DataFlowTasks)'

generate:
	julia --project make.jl

serve:
	julia -e 'using LiveServer; LiveServer.serve(dir="build", port=8998, launch_browser=true)'
