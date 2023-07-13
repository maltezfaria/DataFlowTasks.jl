using DataFlowTasks
using Aqua

# Aqua.jl fails the toml test on 1.6 because of the [deps] entry in the
# Project.toml file. This is a workaround.
test_toml = VERSION >= v"1.9"
test_toml || @warn "Skipping Aqua's `project_toml_formatting` test."
Aqua.test_all(DataFlowTasks; project_toml_formatting=test_toml)
