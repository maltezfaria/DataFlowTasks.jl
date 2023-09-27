using DataFlowTasks
using Aqua

# Aqua.jl fails the toml test on 1.6 because of the [deps] entry in the
# Project.toml file. This is a workaround.
test_toml = VERSION >= v"1.9"
test_toml || @warn "Skipping Aqua's `project_toml_formatting` test."
Aqua.test_all(
    DataFlowTasks;
    ambiguities = (broken = true),
    unbound_args = true,
    undefined_exports = true,
    project_extras = true,
    stale_deps = true,
    deps_compat = true,
    project_toml_formatting = test_toml,
    piracy = (; broken = true),
)
