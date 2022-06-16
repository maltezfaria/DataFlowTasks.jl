#=
In this file we define a simple log format for keeping track of the various
computations during the execution of the DAG. @trace events are collected by the
logger and written to a file which can later be parsed.

Some basic rules:
1- each logging event writes a new line
2- the first word of the line provides a key to decide how to parse the line
3- after the key, a list of values is provided. Values are separated by a space

The type of keys are:

dag_node tag intag1 intag2 ... intagk
task_info pid start_time end_time tid
length_dag n time
length_finished n time
length_runnable n time

All times are in nanoseconds, collected using `time_ns()`.

The logger contains a `ref_time` that can be used to setup the starting time of
the program. Its default is 0.

As a post-processing step, the logger.io stream can be parsed to generate
relevant data structures which can be e.g. plotted.
=#

const TraceLogLevel = Logging.LogLevel(-1)

macro trace(expr)
    :(@logmsg $TraceLogLevel $(esc(expr)))
end

struct TaskLog
    tid::Int
    time_start::Float64
    time_finish::Float64
    tag::Int
    inneighbors::Vector{Int64}
    label::String
end

# Contains vectors of TaskLog (as many vectors as there are threads)
const logger = [Vector{TaskLog}() for _ ∈ 1:Threads.nthreads()]

should_log() = false
# const task_logger = [TaskLog[] for _ in 1:Threads.nthreads()]
# const dag_logger = Vector{Vector{Int64}}()

function clear_logger()
    # Empty neighbors
    for thread ∈ logger
        for tasklog ∈ thread
            empty!(tasklog.inneighbors)
        end
        empty!(thread)
    end
end

function get_trace_xlims()
    first_time = Inf
    last_time = 0

    # For every tasklog in every thread
    for thread in logger
        for tasklog in thread
            # Update first_time
            if tasklog.time_start < first_time
                first_time = tasklog.time_start
            end

            # Update last_time
            if tasklog.time_finish > last_time
                last_time = tasklog.time_finish
            end
        end
    end

    first_time, last_time
end

struct TraceLog end
struct DagLog end
@recipe function f(::Type{TraceLog})
    if !should_log()
        error("Logger is not active")
    end

    # Make sure all tasks are finished
    sync()
    
    (first_time, last_time) = get_trace_xlims()

    size --> (800,600)
    xlabel --> "time (s)"
    ylabel --> "threadid"
    xlims --> (0, last_time - first_time)
    # yflip  := true
    seriestype := :shape
    for thread in logger
        # yticks --> unique(t.threadid for t in tasklogs)        
        seriesalpha  --> 0.5
        # for (tid,ts,te,tag) in tasklog
        for tasklog in thread
            # loop all data and plot the lines
            @series begin
                label --> nothing
                x1 = (tasklog.time_start  - first_time)
                x2 = (tasklog.time_finish - first_time)
                y1 = tasklog.tid - 0.25
                y2 = tasklog.tid + 0.25
                [x1,x2,x2,x1,x1],[y1,y1,y2,y2,y1]
            end
        end
    end
end



function write_graph()
    str = "strict digraph dag {rankdir=LR;layout=dot;"

    for thread ∈ logger
        for tasklog ∈ thread
            for neighbor ∈ tasklog.inneighbors
                str *= """ $neighbor -> $(tasklog.tag);"""
            end
        end
    end

    str *= "}"

    return str
end

function plot_dag()
    if !should_log()
        error("Logger is not active")
    end

    # Make sure all tasks are finished
    sync()

    # Write DOT graph
    graph_str = write_graph()
    
    Graph(graph_str)
end