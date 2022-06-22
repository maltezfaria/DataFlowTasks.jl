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


# Not currently used
# -----------------------------------------
const TraceLogLevel = Logging.LogLevel(-1)
macro trace(expr)
    :(@logmsg $TraceLogLevel $(esc(expr)))
end
# -----------------------------------------


# -------------------------------------------------------
# ---------------------- LOGGING ------------------------
# -------------------------------------------------------

"""
    TaskLog  
Contains informations of a task's progress.
## Arguments :
    - `tid`         : thread on wich the task ran
    - `time_start`  : time the task started running
    - `time_finish` : time the task finished running
    - `tag`         : task id in DAG
    - `inneighbors` : Vector of incoming neighbors in DAG
    - `` 
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
    Logger  
Contains informations on the program's progress
## Arguments :
    - `threadslogs` : Vector of TaskLogs for each thread
"""
struct Logger
    threadlogs::Vector{Vector{TaskLog}}
    function Logger()
        new([Vector{TaskLog}() for _ ∈ 1:Threads.nthreads()])
    end
end

"""
    setlogger!(l::Logger)  
Set global Logger
"""
function setlogger!(l::Logger)
    LOGGER[] = l
end

"""
    getlogger()  
Returns global Logger
"""
function getlogger()
    LOGGER[]
end

"""
    resetlogger()  
Clear LOGGER memory and all logging states
"""
function resetlogger!()
    for threadlog ∈ LOGGER[].threadlogs
        for tasklog ∈ threadlog
            empty!(tasklog.inneighbors)
        end
        empty!(threadlog)
    end
end

"""
    shouldlog()  
Global to switch between logging or not.
"""
function shouldlog()
    false
end

"""
    const LOGGER  
Global Ref Logger.
"""
const LOGGER = Ref{Logger}()



# -------------------------------------------------------
# ----------------------- PLOTTING ----------------------
# -------------------------------------------------------

"""
    LABELS  
Store user defined category labels
"""
const LABELS = Ref{Vector{String}}()

"""
    Trace  
Use to dispatch on plot recipe to visualize parallel trace
"""
struct Trace end

"""
    plot(Trace)  
Plot recipe to visualize parallel trace
"""
@recipe function f(::Type{Trace})
    # Ensure logger was active
    if !shouldlog()
        error("Logger is not active")
    end

    # Make sure all tasks are finished
    sync()
    
    # Get first and last time recorded
    (firsttime, lasttime) = timelimits() .* 10^(-9)

    # General plot features
    size --> (800,600)
    layout := isassigned(LABELS[]) ? @layout[a{0.8h} ; [b{0.5w} c{0.5w}]] : @layout[a{0.8h} ; b]
    colors = [:green, :orange, :purple, :blue, :yellow, :red]
    alr_labeled = [false for _ ∈ LABELS[]]  # we want only 1 label per category

    # Informations
    # ------------
    computingtime = 0
    othertime = length(LOGGER[].threadlogs) * (lasttime - firsttime)
    if isassigned(LABELS[])
        times_per_category = zeros(length(LABELS[]))
    end

    # Loop on all tasklogs to plot computing times
    for threadlog in LOGGER[].threadlogs
        for tasklog in threadlog
            @series begin
                # Plots attributes
                # ---------------
                xlabel --> "time (s)"
                ylabel --> "threadid"
                xlims --> (0, lasttime - firsttime)
                title --> "Trace"
                seriestype := :shape
                seriesalpha  --> 0.6
                subplot := 1

                # Vertices of task square
                # -----------------------
                x1 = (tasklog.time_start  * 10^(-9)  - firsttime)
                x2 = (tasklog.time_finish * 10^(-9) - firsttime)
                y1 = tasklog.tid - 0.25
                y2 = tasklog.tid + 0.25

                # General Informations
                # ------------
                computingtime += x2-x1
                othertime -= x2-x1

                # Task category management
                # ------------------------
                if isassigned(LABELS[])
                    for i ∈ 1:length(LABELS[])
                        if occursin(LABELS[][i], tasklog.label)
                            times_per_category[i] += x2-x1
                            color --> colors[i]
                            if !alr_labeled[i]
                                label --> LABELS[][i]
                                alr_labeled[i] = true
                            else
                                label--> nothing
                            end
                        end
                    end
                else
                    label --> nothing
                end

                # Returns
                [x1,x2,x2,x1,x1],[y1,y1,y2,y2,y1]
            end
        end
    end

    # General Informations
    # --------------------
    total_time = length(LOGGER[].threadlogs) * (lasttime - firsttime)
    rel_time_waiting = 100 * othertime / total_time
    rel_time_working = 100 * computingtime / total_time
    @info "Proportion of time waiting   : $rel_time_waiting %"
    @info "Computing time               : $othertime s"
    @info "Other time                   : $computingtime s"

    # Plot activity (Computing / Other)
    # ---------------------------------
    @series begin
        subplot := 2
        seriestype := :bar
        orientation := :h
        title  --> "Activity (%)"
        label  --> "Other"
        xlims  --> (0, 100)
        xticks --> 0:25:100
        yticks --> nothing
        color  --> :white
        seriesalpha --> 0.8
        [rel_time_working, rel_time_waiting]
    end
    @series begin
        subplot := 2
        seriestype := :bar
        orientation := :h
        title  --> "Activity (%)"
        label  --> "Other"
        xlims  --> (0, 100)
        xticks --> 0:25:100
        yticks --> nothing
        color --> :purple
        seriesalpha --> 0.8
        [rel_time_working]
    end

    # Category Labels
    # ---------------
    if isassigned(LABELS[])       
        # Get max category_time
        tmax = max(times_per_category...)

        @series begin
            subplot := 3
            seriestype := :bar
            label --> nothing
            labels  --> LABELS[]
            ylabel --> "Time (s)"
            title  --> "Times per category (%)"
            ylims  --> (0, tmax)
            yticks --> 0:round(tmax/4, digits=2):tmax
            color  --> colors[1:length(LABELS[])]
            seriesalpha --> 0.8
            LABELS[], times_per_category
        end
    end
end

# Utility function
function timelimits()
    first_time = Inf
    last_time = 0

    # For every tasklog in every thread
    for threadlog in LOGGER[].threadlogs
        for tasklog in threadlog
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


# Label Management
# ----------------

"""
    setlabels()  
Set trace plot task labels and activate it
"""
function setlabels!(labels::Vector{String})
    LABELS[] = labels
end
function setlabels!(labels...)
    resetlabels!()
    LABELS[] = [label for label ∈ labels]
end

"""
    resetlabels()
Reset trace lpot task labels
"""
function resetlabels!()
    empty!(LABELS[])
end



# DAG Plotting
# ------------
"""
    getdag()  
Get DAG's DOT file to be plotted by GraphViz with Graph(getdag())
"""
function getdag()
    if !shouldlog()
        error("Logger is not active")
    end

    # Make sure all tasks are finished
    sync()

    # Write DOT graph
    str = "strict digraph dag {rankdir=LR;layout=dot;"

    for threadlog ∈ LOGGER[].threadlogs
        for tasklog ∈ threadlog
            for neighbor ∈ tasklog.inneighbors
                str *= """ $neighbor -> $(tasklog.tag);"""
            end
        end
    end

    str *= "}"
end
