using DataFlowTasks
using Documenter

DocMeta.setdocmeta!(DataFlowTasks, :DocTestSetup, :(using CairoMakie, GraphViz, DataFlowTasks); recursive=true)

makedocs(;
    modules=[DataFlowTasks],
    authors="Luiz M. Faria <maltezfaria@gmail.com> and contributors",
    repo="https://github.com/maltezfaria/DataFlowTasks.jl/blob/{commit}{path}#{line}",
    sitename="DataFlowTasks.jl",
    format=Documenter.HTML(;
        prettyurls=get(ENV, "CI", "false") == "true",
        canonical="https://maltezfaria.github.io/DataFlowTasks.jl",
        assets=String[],
    ),
    pages=[
        "Getting started" => "index.md",
        "Examples" => "examples.md",
        # "Comparaison with Dagger.jl" => "dagger.md",
        "Profiling" => "profiling.md",
        "Common Issues" => "issues.md",
        "References" => "references.md"
    ],
)

deploydocs(;
    repo="github.com/maltezfaria/DataFlowTasks.jl",
    devbranch="main"
)
