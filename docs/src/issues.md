# [Common Issues](@id issues-section)

* time(`Critical Path`) = 0 : there's no dependencies between tasks (or you didn't give any, or it didn't work the way it was supposed to).

* Huge `Other` times : the `DataFlowTasks.resetlogger!()` was probably forgotten, hence the first measurerd time currently in the logger's memory is one from a previous run.

* Mention let block discussions