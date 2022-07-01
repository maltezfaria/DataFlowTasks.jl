"""
    struct TaskLog

Logs the execution trace of a [`DataFlowTask`](@ref).

## Fields:
- `tag`         : task id in DAG
- `time_start`  : time the task started running
- `time_finish` : time the task finished running
- `tid`         : thread on wich the task ran
- `inneighbors` : vector of incoming neighbors in DAG
- `label`       : a string used for displaying and/or postprocessing tasks
"""
struct TaskLog
    tag::Int
    time_start::UInt64
    time_finish::UInt64
    tid::Int
    inneighbors::Vector{Int64}
    label::String
end

"""
    struct InsertionLog

Logs the execution trace of a [`DataFlowTask`](@ref) insertion.

## Fields:
- `time_start`  : time the insertion began
- `time_finish` : time the insertion finished
- `taskid`      : the thread it is inserting
- `tid`         : the thread on wich the insertion is happening
"""
struct InsertionLog
    time_start::UInt64
    time_finish::UInt64
    taskid::Int
    tid::Int
end


"""
    struct Logger

Contains informations on the program's progress. For thread-safety, the `Logger`
structure uses one vector of [`TaskLog`](@ref) per thread.
"""
struct Logger
    tasklogs::Vector{Vector{TaskLog}}
    insertionlogs::Vector{Vector{InsertionLog}}
    function Logger()
        # internal constructor to guarantee that there is always one vector per
        # thread to do the loggin
        new(
            [Vector{TaskLog}()      for _ ∈ 1:Threads.nthreads()],
            [Vector{InsertionLog}() for _ ∈ 1:Threads.nthreads()]
        )
    end
end

"""
    setlogger!(l::Logger)

Set the global (default) logger to `l`.
"""
function setlogger!(l::Logger)
    LOGGER[] = l
end

"""
    getlogger()

Return the global logger.
"""
function getlogger()
    LOGGER[]
end

"""
    resetlogger(logger=getlogger())

Clear the `logger`'s memory and logging states.
"""
function resetlogger!(logger=getlogger())
    map(empty!, logger.tasklogs)
    map(empty!, logger.insertionlogs)
end

"""
    nbtasknodes(logger=getlogger())  
Returns the number of task nodes
"""
function nbtasknodes(logger=getlogger())
    sum(length(threadlog) for threadlog ∈ logger.tasklogs)
end

"""
    const LOGGER::Ref{Logger}

Global `Logger` being used to record the events. Can be changed using [`setlogger!`](@ref).
"""
const LOGGER = Ref{Logger}()


############################################################################
#                           To Plot DAG                                  
############################################################################

"""
    loggertodot(logger)  --> dagstring
Return a string in the
[DOT](https://en.wikipedia.org/wiki/DOT_(graph_description_language)) format
representing the underlying graph in `logger`
and to be plotted by GraphViz with Graph(logger_to_dot())
"""
function loggertodot(logger=getlogger())
    path = criticalpath()
    
    # Write DOT graph
    # ---------------
    str = "strict digraph dag {rankdir=LR;layout=dot;rankdir=TB;"
    str *= """concentrate=true;"""

    for tasklog ∈ Iterators.flatten(logger.tasklogs)
        # Tasklog.tag node attributes
        str *= """ $(tasklog.tag) """ 
        tasklog.label != "" && (str *= """ [label="$(tasklog.label)"] """)
        tasklog.tag+1 ∈ path && (str *= """ [color=red] """)
        str *= """[penwidth=2];"""
            
        # Defines edges
        for neighbour ∈ tasklog.inneighbors
            red = false

            # Is this connection is in critical path
            (neighbour+1 ∈ path && tasklog.tag+1 ∈ path) && (red=true)
            
            # Edge
            str *= """ $neighbour -> $(tasklog.tag) """
            red && (str *= """[color=red] """)
            str *= """[penwidth=2];"""
        end
    end

    str *= "}"
end

"""
    criticalpath() --> path  
Finds the critical path of the logger's DAG
"""
function criticalpath()
    # Declaration of the adjacency matrix for DAG analysis
    # Note : we add a virtual first node 1 that represent the beginning of the DAG
    nb_nodes = nbtasknodes()
    adj = NaN * ones(nb_nodes+1, nb_nodes+1)
    
    # Find Critical Path
    # ------------------
    for tasklog ∈ Iterators.flatten(getlogger().tasklogs)
        # Weight of the arc from tasklog.tag to other nodes
        task_duration = (tasklog.time_finish - tasklog.time_start) * 10^(-9)

        # If no inneighbors than it's one of the first tasks
        # Note : considering we remove nodes from the dag, it's not necessarly true
        if length(tasklog.inneighbors) == 0
            adj[1, tasklog.tag + 1] = 0
        end

        # Defines edges
        for neighbor ∈ tasklog.inneighbors
            adj[neighbor+1, tasklog.tag+1] = task_duration
        end
    end
    longestpath(adj, 1)
end