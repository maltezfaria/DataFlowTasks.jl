push!(LOAD_PATH,joinpath(@__DIR__, ".."))
using Documenter, HScheduler

makedocs(
    modules = [HScheduler],
    format = Documenter.HTML(; prettyurls = get(ENV, "CI", nothing) == "true"),
    authors = "Luiz M. Faria",
    sitename = "HScheduler.jl",
    pages = Any["index.md"]
    # strict = true,
    # clean = true,
    # checkdocs = :exports,
)

deploydocs(
    repo = "github.com/maltezfaria/HScheduler.jl.git",
)
