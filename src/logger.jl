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
    struct Logger

Contains informations on the program's progress. For thread-safety, the `Logger`
structure uses one vector of [`TaskLog`](@ref) per thread.
"""
struct Logger
    threadlogs::Vector{Vector{TaskLog}}
    function Logger()
        # internal constructor to guarantee that there is always one vector per
        # thread to do the loggin
        new([Vector{TaskLog}() for _ ∈ 1:Threads.nthreads()])
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
    map(empty!,logger.threadlogs)
end

"""
    const LOGGER::Ref{Logger}

Global `Logger` being used to record the events. Can be changed using [`setlogger!`](@ref).
"""
const LOGGER = Ref{Logger}()

# -------------------------------------------------------
# ----------------------- PLOTTING ----------------------
# -------------------------------------------------------

"""
    plot(logger::Logger;categories)

Plot recipe to visualize the logged events in `logger`.
"""
@recipe function f(logger::Logger;categories=String[])
    if isempty(Iterators.flatten(logger.threadlogs))
        error("logger is empty: nothing to plot")
    end

    # Get first and last time recorded
    (firsttime, lasttime) = timelimits(logger) .* 10^(-9)

    # Get critical path
    path = criticalpath()
    t∞ = 0

    # General plot features
    size --> (1000,600)
    layout := !isempty(categories) ? @layout[a{0.8h} ; [b{0.33w} c{0.34w} d{0.33w}]] : @layout[a{0.8h} ; [b{0.5w} c{0.5w}]]
    colors = [:green, :orange, :purple, :blue, :yellow, :red]
    alr_labeled = [false for _ ∈ categories]  # we want only 1 label per category

    # Informations
    # ------------
    computingtime = 0
    othertime = length(logger.threadlogs) * (lasttime - firsttime)
    times_per_category = zeros(length(categories))

    # Loop over all tasklogs to plot computing times
    for threadlog in logger.threadlogs
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
                if tasklog.tag ∈ path
                    t∞ += x2 - x1
                end

                # Task category management
                # ------------------------
                if !isempty(categories)
                    for i ∈ 1:length(categories)
                        if occursin(categories[i], tasklog.label)
                            times_per_category[i] += x2-x1
                            color --> colors[i]
                            if !alr_labeled[i]
                                label --> categories[i]
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
    total_time = length(logger.threadlogs) * (lasttime - firsttime)
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
        labels  --> ["Computing" "Other"]
        xlims  --> (0, 100)
        xticks --> 0:25:100
        yticks --> nothing
        fillcolor  --> [:purple :red]
        seriesalpha --> 0.8
        [1 2],[rel_time_working rel_time_waiting]
    end

    # Plot infinite proc time
    # -----------------------
    @series begin
        subplot := 3
        seriestype := :bar
        title --> "Infinite Proc"
        label --> nothing
        fillcolor --> [:green :red]
        seriesalpha --> 0.8
        ["Inf. proc. t" "Real total t"], [t∞ (lasttime - firsttime)]
    end

    # Category Labels
    # ---------------
    if !isempty(categories)
        @series begin
            subplot := 4
            seriestype := :bar
            label --> nothing
            labels  --> categories
            ylabel --> "Time (s)"
            title  --> "Times per category"
            color  --> colors[1:length(categories)]
            seriesalpha --> 0.8
            categories, times_per_category
        end
    end
end

function timelimits(logger)
    iter = Iterators.flatten(logger.threadlogs)
    minimum(t->t.time_start,iter), maximum(t->t.time_finish,iter)
end



############################################################################
#                           Dag Plotting                                  
############################################################################

"""
    logger_to_dot(logger)  --> dagstring
Return a string in the
[DOT](https://en.wikipedia.org/wiki/DOT_(graph_description_language)) format
representing the underlying graph in `logger`
and to be plotted by GraphViz with Graph(logger_to_dot())
"""
function logger_to_dot(logger=getlogger())
    path = criticalpath()
    
    # Write DOT graph
    # ---------------
    str = "strict digraph dag {rankdir=LR;layout=dot;"
    str *= """concentrate=true;"""
    for tasklog ∈ Iterators.flatten(logger.threadlogs)
        # Defines edges
        for neighbor ∈ tasklog.inneighbors
            str *= """ $neighbor -> $(tasklog.tag)"""
            if neighbor+1 ∈ path && tasklog.tag+1 ∈ path
                str *= """ [color=red];"""
                str *= """ $neighbor [color=red];"""
                str *= """ $(tasklog.tag) [color=red]"""
            end
            str *= """;"""
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
    nb_nodes = sum(length(threadlog) for threadlog ∈ LOGGER[].threadlogs)
    adj = NaN * ones(nb_nodes+1, nb_nodes+1)
    
    # Find Critical Path
    # ------------------
    for threadlog ∈ LOGGER[].threadlogs
        for tasklog ∈ threadlog
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
    end
    longestpath(adj, 1)
end