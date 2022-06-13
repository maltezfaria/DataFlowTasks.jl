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
    threadid::Int
    time_start::Float64
    time_finish::Float64
    task_tag::Int
    task_label::String
end

const LOGGER = [TaskLog[] for _ in 1:Threads.nthreads()]
should_log() = true


# # plot the logger

@recipe function f(logger::Vector{Vector{TaskLog}})
    # Get ref time
    first_time = Inf
    last_time = 0
    for tasklogs in logger
        for tasklog in tasklogs
            if tasklog.time_start < first_time
                first_time = tasklog.time_start
            end
            if tasklog.time_finish > last_time
                last_time = tasklog.time_finish
            end
        end
    end

    xlabel --> "time (s)"
    ylabel --> "threadid"
    xlims --> (0, (last_time - first_time)/1e9)
    # yflip  := true
    seriestype := :shape
    for tasklogs in logger
        # yticks --> unique(t.threadid for t in tasklogs)        
        seriesalpha  --> 0.5
        # for (tid,ts,te,tag) in tasklog
        for tasklog in tasklogs
            # loop all data and plot the lines
            @series begin
                label --> nothing
                x1 = (tasklog.time_start  - first_time) / 1e9
                x2 = (tasklog.time_finish - first_time) / 1e9
                y1 = tasklog.threadid - 0.25
                y2 = tasklog.threadid + 0.25
                [x1,x2,x2,x1,x1],[y1,y1,y2,y2,y1]
            end
        end
    end
end

# struct PlotFinished end
# struct PlotRunnable end

# @recipe function f(::PlotFinished,log::Logger)
#     xlabel --> "time (s)"
#     ylabel --> "length"
#     xlims --> (0,Inf)
#     lw --> 2
#     label --> "finished channel"
#     # yflip  := true
#     seriestype := :line
#     l,t = log.finishedlog # length,time
#     yticks --> unique(l)
#     (t .- ref_time[])/1e9,l
# end

# @recipe function f(::PlotRunnable,log::Logger)
#     xlabel --> "time (s)"
#     ylabel --> "length"
#     xlims --> (0,Inf)
#     lw --> 2
#     label --> "runnable channel"
#     # yflip  := true
#     seriestype := :line
#     l,t = log.runnablelog # length,time
#     yticks --> unique(l)
#     (t .- ref_time[])/1e9,l
# end
