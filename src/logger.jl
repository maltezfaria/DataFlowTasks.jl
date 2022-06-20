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
    label_id::Int64
end

# Contains vectors of TaskLog (as many vectors as there are threads)
const logger = [Vector{TaskLog}() for _ ∈ 1:Threads.nthreads()]

const tracelabels = Vector{String}()
function set_tracelabels(args...)
    empty!(tracelabels)
    push!(tracelabels, args...)
end

should_log() = false

function clear_logger()
    # Empty neighbors
    for thread ∈ logger
        for tasklog ∈ thread
            empty!(tasklog.inneighbors)
        end
        empty!(thread)
    end
end

function get_minmax_times()
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

struct Trace end
struct Graph end

@recipe function f(::Type{Trace})
    # Ensure logger was active
    if !should_log()
        error("Logger is not active")
    end

    # Make sure all tasks are finished
    sync()
    
    (first_time, last_time) = get_minmax_times() .* 10^(-9)

    # Label management
    # ---------------
    if length(tracelabels) == 0
        push!(tracelabels, "task")
    end
    colors = [:purple, :orange, :blue, :green, :yellow, :red]
    already_labeled = [false for _ ∈ 1:length(tracelabels)]

    # General plot features
    size --> (800,600)
    layout := @layout [ a{0.8h} ; [b{0.5w} c{0.5w}]]

    # Informations
    workingtime = length(logger) * (last_time - first_time)
    waitingtime = 0
    timespercategory = zeros(length(tracelabels))

    # Plot each tasklog
    for thread in logger
        
        for tasklog in thread
            # loop all data and plot the lines
            @series begin
                # Plots attributes
                xlabel --> "time (s)"
                ylabel --> "threadid"
                xlims --> (0, last_time - first_time)
                title --> "Trace"
                seriestype := :shape
                seriesalpha  --> 0.5
                subplot := 1

                if length(tracelabels) < tasklog.label_id
                    error("label ids assigned but tracelabels not defined")
                end
                if !already_labeled[tasklog.label_id]
                    label --> tracelabels[tasklog.label_id]
                    already_labeled[tasklog.label_id] = true
                else
                    label --> nothing
                end
                color --> colors[tasklog.label_id]

                x1 = (tasklog.time_start  * 10^(-9)  - first_time)
                x2 = (tasklog.time_finish * 10^(-9) - first_time)
                y1 = tasklog.tid - 0.25
                y2 = tasklog.tid + 0.25

                # Informations
                workingtime -= x2-x1
                waitingtime += x2-x1
                timespercategory[tasklog.label_id] += x2-x1

                [x1,x2,x2,x1,x1],[y1,y1,y2,y2,y1]
            end
        end
    end

    # Informations
    # ------------
    total_time = length(logger) * (last_time - first_time)
    rel_time_waiting = 100 * workingtime / total_time
    @info "Proportion of time waiting   : $rel_time_waiting %"
    @info "Cumulative working time      : $waitingtime s"
    @info "Cumulative waiting time      : $workingtime s"

    # Waiting (s)
    # -----------
    xmax = max(waitingtime, workingtime)
    xmin = 0
    @series begin
        subplot := 2
        seriestype := :bar
        orientation --> :h
        label --> "Working"
        title --> "Activity"
        xlims --> (xmin, xmax)
        xticks --> 0:round(xmax/4, digits=2):xmax
        xlabel --> "time (s)"
        yticks --> nothing
        ["Working"], [waitingtime]
    end
    @series begin
        subplot := 2
        seriestype := :bar
        orientation --> :h
        label --> "Waiting"
        title --> "Activity"
        xlims --> (xmin, xmax)
        xticks --> 0:round(xmax/4, digits=2):xmax
        xlabel --> "time (s)"
        yticks --> nothing
        ["Waiting"], [workingtime]
    end

    # Category repartition
    # --------------------
    tmax = max(timespercategory...)
    for i ∈ 1:length(tracelabels)
        l = tracelabels[i]
        @series begin
            subplot := 3
            seriestype := :bar
            label --> nothing
            title --> "Repartition (%)"
            yticks --> 0:50:100
            ylims --> (0, 100)
            seriesalpha --> 0.5
            color --> colors[i]
            [l], [100 * timespercategory[i]/tmax]
        end
    end
end


function getdag()
    if !should_log()
        error("Logger is not active")
    end

    # Make sure all tasks are finished
    sync()

    # Write DOT graph
    str = "strict digraph dag {rankdir=LR;layout=dot;"

    for thread ∈ logger
        for tasklog ∈ thread
            for neighbor ∈ tasklog.inneighbors
                str *= """ $neighbor -> $(tasklog.tag);"""
            end
        end
    end

    str *= "}"
end
