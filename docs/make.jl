using DataFlowTasks
using Documenter
using Literate

for example in ["cholesky", "blur-roberts"]
    dir = joinpath(DataFlowTasks.PROJECT_ROOT,"docs","src", "examples", example)
    src = joinpath(dir, "$(example).jl")
    Literate.markdown(src, dir)
    Literate.notebook(src, dir)
end

DocMeta.setdocmeta!(DataFlowTasks, :DocTestSetup, :(using CairoMakie, GraphViz, DataFlowTasks); recursive=true)

makedocs(;
    modules=[DataFlowTasks],
    repo="https://github.com/maltezfaria/DataFlowTasks.jl/blob/{commit}{path}#{line}",
    sitename="DataFlowTasks.jl",
    format=Documenter.HTML(;
        prettyurls=get(ENV, "CI", "false") == "true",
        canonical="https://maltezfaria.github.io/DataFlowTasks.jl",
        assets=String[],
    ),
    pages=[
        "Getting started" => "index.md",
        "Debugging & Profiling" => "profiling.md",
        "Examples" => [
            "examples/cholesky/cholesky.md",
            "examples/blur-roberts/blur-roberts.md",
            # "examples/stencil/stencil.md",
            # "examples/lu/lu.md",
            # "examples/hmat/hmat.md",
        ],
        # "Comparaison with Dagger.jl" => "dagger.md",
        # "Common Issues" => "issues.md",
        "References" => "references.md"
    ],
    strict=true
)

deploydocs(;
    repo="github.com/maltezfaria/DataFlowTasks.jl",
    devbranch="main"
)
