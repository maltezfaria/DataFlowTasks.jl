using DataFlowTasks
using Documenter
using Literate

for example in ["cholesky", "blur-roberts"]
    dir = joinpath(DataFlowTasks.PROJECT_ROOT, "docs", "src", "examples", example)
    src = joinpath(dir, "$(example).jl")
    Literate.markdown(src, dir)
    Literate.notebook(src, dir)
end

on_CI = get(ENV, "CI", "false") == "true"

DataFlowTasks.stack_weakdeps_env!()
DocMeta.setdocmeta!(
    DataFlowTasks,
    :DocTestSetup,
    :(using CairoMakie, GraphViz, DataFlowTasks);
    recursive = true,
)

modules = [DataFlowTasks]
if isdefined(Base, :get_extension)
    using GraphViz, CairoMakie
    const GraphViz_Ext = Base.get_extension(DataFlowTasks, :DataFlowTasks_GraphViz_Ext)
    const Makie_Ext    = Base.get_extension(DataFlowTasks, :DataFlowTasks_Makie_Ext)
    append!(modules, (GraphViz_Ext, Makie_Ext))
end

makedocs(;
    modules = modules,
    repo = "",
    sitename = "DataFlowTasks.jl",
    format = Documenter.HTML(;
        prettyurls = on_CI,
        canonical = "https://maltezfaria.github.io/DataFlowTasks.jl",
        assets = String[],
    ),
    pages = [
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
        "References" => "references.md",
    ],
    warnonly = on_CI ? false : Documenter.except(:linkcheck_remotes),
    pagesonly = true,
)

deploydocs(;
    repo = "github.com/maltezfaria/DataFlowTasks.jl",
    devbranch = "main",
    push_preview = true,
)
