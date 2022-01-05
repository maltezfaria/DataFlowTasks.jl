push!(LOAD_PATH,joinpath(@__DIR__, ".."))
using Documenter, DataFlowScheduler

makedocs(
    modules = [DataFlowScheduler],
    format = Documenter.HTML(; prettyurls = get(ENV, "CI", nothing) == "true"),
    authors = "Luiz M. Faria",
    sitename = "DataFlowScheduler.jl",
    pages = Any["index.md"]
    # strict = true,
    # clean = true,
    # checkdocs = :exports,
)

deploydocs(
    repo = "github.com/maltezfaria/DataFlowScheduler.jl.git",
)
