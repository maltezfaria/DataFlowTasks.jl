do: setup doctest generate

setup:
	julia --project -e '                     \
            using Pkg;                           \
            Pkg.develop(PackageSpec(path="..")); \
            Pkg.instantiate()'

readme-preview:
	julia readme/make.jl preview

readme-check:
	julia readme/make.jl check

readme-update:
	julia -t 4 readme/make.jl update

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
