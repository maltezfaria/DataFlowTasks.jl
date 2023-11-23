using DataFlowTasks
using Aqua

Aqua.test_all(
    DataFlowTasks;
    ambiguities = true,
    unbound_args = true,
    undefined_exports = true,
    project_extras = true,
    stale_deps = true,
    deps_compat = true,
    piracies = true,
    persistent_tasks = true,
)
