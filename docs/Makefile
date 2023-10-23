do: build-docs

setup:
	julia --project -e 'using Pkg; Pkg.develop(path=".."); Pkg.resolve(); Pkg.instantiate()'

build-docs: setup
	julia --project make.jl
