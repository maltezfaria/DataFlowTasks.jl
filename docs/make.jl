using Documenter
using Literate
using DataFlowTasks

using GraphViz, CairoMakie

draft = false

const ON_CI = get(ENV, "CI", "false") == "true"
const GIT_HEAD = chomp(read(`git rev-parse HEAD`, String))
# a single `Pkg.add` into the fresh environment: on Julia 1.13.2, a later `Pkg.add`
# that changes the version of an indirect dependency fails with `Unknown package`
# (JuliaLang/Pkg.jl#4866)
const SETUP = """
#nb import Pkg
#nb Pkg.activate(temp=true)
#nb Pkg.add([Pkg.PackageSpec(name="DataFlowTasks", rev="$GIT_HEAD"); Pkg.PackageSpec.(DEPENDENCIES)])
"""

ON_CI && (draft = false) # always full build on CI

function insert_setup(content)
    ON_CI || return content
    return replace(content, "#nb ## __NOTEBOOK_SETUP__" => SETUP)
end

# generate examples
for example in ["cholesky", "blur-roberts", "lcs", "sort"]
    println("\n*** Generating $example example")
    @time begin
        dir = joinpath(DataFlowTasks.PROJECT_ROOT, "docs", "src", "examples", example)
        src = joinpath(dir, "$(example).jl")
        Literate.markdown(src, dir)
        draft || Literate.notebook(src, dir; preprocess = insert_setup)
    end
end

# generate readme
println("\n*** Generating README")
@time cd(joinpath(DataFlowTasks.PROJECT_ROOT, "docs", "src", "readme")) do
    src = joinpath(pwd(), "README.jl")

    # Run code
    include(src)

    # Generate notebook
    draft || Literate.notebook(src, pwd())

    # Generate markdown
    # -> fix image paths to link to github.io
    Literate.markdown(src, pwd(), flavor = Literate.CommonMarkFlavor())
    contents = read("README.md", String)
    contents = replace(contents, "![](" => "![](https://maltezfaria.github.io/DataFlowTasks.jl/dev/readme/")
    write("README.md", contents)

    try
        run(`diff -u ../../../README.md README.md`)
    catch
        @warn "README not up-to-date!"
    end
end


println("\n*** Generating documentation")

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
    const Makie_Ext = Base.get_extension(DataFlowTasks, :DataFlowTasks_Makie_Ext)
    append!(modules, (GraphViz_Ext, Makie_Ext))
end

makedocs(;
    modules = modules,
    repo = "",
    sitename = "DataFlowTasks.jl",
    format = Documenter.HTML(;
        prettyurls = ON_CI,
        canonical = "https://maltezfaria.github.io/DataFlowTasks.jl",
        assets = String[],
    ),
    pages = [
        "Getting started" => "index.md",
        "Debugging & Profiling" => "profiling.md",
        "Examples" => [
            "examples/cholesky/cholesky.md",
            "examples/blur-roberts/blur-roberts.md",
            "examples/lcs/lcs.md",
            "examples/sort/sort.md",
            # "examples/stencil/stencil.md",
            # "examples/lu/lu.md",
            # "examples/hmat/hmat.md",
            "examples/hardware.md",
        ],
        # "Comparaison with Dagger.jl" => "dagger.md",
        # "Common Issues" => "issues.md",
        "Troubleshooting" => "troubleshooting.md",
        "References" => "references.md",
    ],
    warnonly = ON_CI ? false : Documenter.except(:linkcheck_remotes),
    pagesonly = true,
    draft,
)

deploydocs(;
    repo = "github.com/maltezfaria/DataFlowTasks.jl",
    devbranch = "main",
    push_preview = true,
)
