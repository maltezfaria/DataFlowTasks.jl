do: setup doctest generate

setup:
	julia --project -e '                     \
            using Pkg;                           \
            Pkg.develop(PackageSpec(path="..")); \
            Pkg.instantiate()'
	julia --project -e '                                 \
            using DataFlowTasks;                             \
            DataFlowTasks.stack_weakdeps_env!(verbose=true); \
            using GraphViz, CairoMakie'

update: readme-update examples-update

check: readme-check examples-check

doctest:
	julia --project -e '                     \
            using Documenter: DocMeta, doctest;  \
            using DataFlowTasks;                 \
            DataFlowTasks.stack_weakdeps_env!(); \
            using CairoMakie, GraphViz;          \
            DocMeta.setdocmeta!(DataFlowTasks, :DocTestSetup, :(using DataFlowTasks); recursive=true); \
            doctest(DataFlowTasks)'

generate:
	julia --project make.jl

serve:
	julia -e 'using LiveServer; LiveServer.serve(dir="build", port=8998, launch_browser=true)'




# README generation

readme-check:
	make -C readme check

readme-preview:
	make -C readme preview

readme-update:
	make -C readme update


# Examples included in Documenter

examples-check:
	make -C src/examples check

examples-update:
	make -C src/examples update
