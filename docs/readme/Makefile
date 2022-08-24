check: setup
	julia update.jl --check-only

update: setup
	julia update.jl

setup:
	julia --project="../.." -e "import Pkg; Pkg.instantiate()"
