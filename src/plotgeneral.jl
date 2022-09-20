@info "Loading DataFlowTasks general plot utilities"

using .Makie


#= Contains data to plot the Gantt Chart (parallel trace).
It's a Struct of Array paradigm where all the entries i
of all the arrays tells us information about a same task. =#
struct Gantt
    threads::Vector{Int64}      # Thread on wich the task ran
    jobids::Vector{Int64}       # Task type
    starts::Vector{Float64}     # Start time
    stops::Vector{Float64}      # End time

    function Gantt()
        threads = Vector{Int64}()
        jobids  = Vector{Int64}()
        starts  = Vector{Float64}()
        stops   = Vector{Float64}()
        new(threads, jobids, starts, stops)
    end
end


#= Contains additional post-processed informations on the LogInfo =#
mutable struct ExtendedLogInfo
    firsttime::Float64              # First measured time
    lasttime::Float64               # Last measured time
    computingtime::Float64          # Cumulative time spent computing
    insertingtime::Float64          # Cumulative time spent inserting
    othertime::Float64              # Cumulative other time
    t∞::Float64                     # Inf. proc time
    t_nowait::Float64               # Time if we didn't wait at all
    timespercat::Vector{Float64}    # timespercat[i] cumulative time for category i
    categories::Vector{Pair{String, Regex}} # (label => regex) pairs for categories
    path::Vector{Int64}             # Critical Path

    function ExtendedLogInfo(logger::LogInfo, categories, path)
        (firsttime, lasttime) = timelimits(logger) .* 10^(-9)
        othertime     = (lasttime-firsttime) * length(logger.tasklogs)

        normalize_category(x) = x
        normalize_category(x::String) = (x=>Regex(x))

        new(
            firsttime, lasttime,
            0, 0, othertime,
            0, 0,
            zeros(length(categories)+1), normalize_category.(categories),
            path
        )
    end
end


#= Gives minimum and maximum times the logger has measured. =#
function timelimits(logger::LogInfo)
    iter = Iterators.flatten(logger.tasklogs)
    minimum(t->t.time_start,iter), maximum(t->t.time_finish,iter)
end


#= Considering a `label` and a the full list of labels `categories`,
gives the index of the occurence of label in `categories`. =#
function jobid(label::String, categories)
    for i in eachindex(categories)
        (title, rx) = categories[i]
        occursin(rx, label) && return i  # find first
    end

    return length(categories)+1
end


#= Initialize gantt and loginfo structures from logger. =#
function extractloggerinfo!(logger::LogInfo, loginfo::ExtendedLogInfo, gantt::Gantt)
    # Gantt data : Initialization TASKLOGS
    # ------------------------------------
    for tasklog ∈ Iterators.flatten(logger.tasklogs)
        # Gantt data
        # ----------
        push!(gantt.threads, tasklog.tid)
        push!(gantt.jobids , jobid(tasklog.label, loginfo.categories))
        push!(gantt.starts , tasklog.time_start  * 10^(-9) - loginfo.firsttime)
        push!(gantt.stops  , tasklog.time_finish * 10^(-9) - loginfo.firsttime)

        # General Informations
        # --------------------
        task_duration  = (tasklog.time_finish - tasklog.time_start) * 10^(-9)
        # ----
        loginfo.othertime     -= task_duration
        loginfo.computingtime += task_duration
        # ----
        loginfo.timespercat[jobid(tasklog.label, loginfo.categories)] += task_duration
        # ----
        tasklog.tag ∈ loginfo.path && (loginfo.t∞ += task_duration)
        loginfo.t_nowait += task_duration
    end

    # Gantt data : Initialization INSERTIONLOGS
    # -----------------------------------------
    for insertionlog ∈ Iterators.flatten(logger.insertionlogs)
        if insertionlog.gc_time != 0
            gc_start = insertionlog.time_start  * 10^(-9) - loginfo.firsttime
            gc_finish = gc_start + insertionlog.gc_time * 10^(-9)
            insertion_start = gc_finish
            insertion_finish = insertionlog.time_finish * 10^(-9) - loginfo.firsttime

            # GC Task
            push!(gantt.threads , insertionlog.tid)
            push!(gantt.jobids  , length(loginfo.categories)+3)
            push!(gantt.starts  , gc_start)
            push!(gantt.stops   , gc_finish)
        else
            insertion_start = insertionlog.time_start  * 10^(-9) - loginfo.firsttime
            insertion_finish = insertionlog.time_finish * 10^(-9) - loginfo.firsttime
        end

        # Gantt data
        # ----------
        push!(gantt.threads, insertionlog.tid)
        push!(gantt.jobids , length(loginfo.categories)+2)
        push!(gantt.starts , insertion_start)
        push!(gantt.stops  , insertion_finish)

        # General Informations
        # --------------------
        task_duration  = (insertionlog.time_finish - insertionlog.time_start) * 10^(-9)
        loginfo.othertime     -= task_duration
        loginfo.insertingtime += task_duration
    end

    loginfo.t_nowait /= length(logger.tasklogs)

    gantt
end


#= Handles the gantt chart trace part of the global plot =#
function traceplot(ax, logger::LogInfo, gantt::Gantt, loginfo::ExtendedLogInfo)
    hasdefault = (loginfo.timespercat[end] !=0 ? true : false)

    lengthx = length(loginfo.categories)+1
    hasdefault && (lengthx += 1)

    # Axis attributes
    # ---------------
    ax.xlabel = "Time (s)"
    ax.ylabel = "Thread"
    ax.yticks = 1:max(gantt.threads...)
    xlims!(ax, 0, loginfo.lasttime-loginfo.firsttime)

    if length(loginfo.categories) ≥ 4
        grad = cgrad(:tab10)[1:length(loginfo.categories)+1]
        deleteat!(grad, 4)
    else
        grad = cgrad(:tab10)[1:length(loginfo.categories)]
    end
    colors = [grad..., :black, :red, cgrad(:sun)[1]]

    # Barplot
    # -------
    barplot!(
        ax,
        gantt.threads,
        gantt.stops,
        fillto = gantt.starts,
        direction = :x,
        color = colors[gantt.jobids],
        gap = 0.5,
        strokewidth = 0.5,
        strokecolor = :grey,
        width = 1.25
    )

    # Check if we measured some gc
    didgc = false
    for insertionlog ∈ Iterators.flatten(logger.insertionlogs)
        insertionlog.gc_time != 0 && (didgc=true)
    end

    # Labels
    c = [grad...]
    hasdefault && (c = [c..., :black])
    c = [c..., :red]
    didgc && (c = [c..., cgrad(:sun)[1]])
    elements = [PolyElement(polycolor = i) for i in c]

    y = String[]
    push!(y, first.(loginfo.categories)...)
    # y = [first.(loginfo.categories)...]
    hasdefault && push!(y, "default")
    push!(y, "insertion")
    didgc && push!(y, "gc")

    Legend(
        ax.parent[1,1],
        elements,
        y,
        orientation = :horizontal,
        halign = :right, valign = :top,
        margin = (5, 5, 5, 5)
    )
end


#= Handles the plot that indicates the repartition between computing, inserting, and other times =#
function activityplot(ax, loginfo::ExtendedLogInfo)
    # Axis attributes
    # ---------------
    ax.xticks = (1:3, ["Computing", "Inserting", "Other"])
    ax.ylabel = "Time (s)"

    # Barplot
    # -------
    barplot!(
        ax,
        1:3,
        [
            loginfo.computingtime,
            loginfo.insertingtime,
            loginfo.othertime
        ],
        color = cgrad(:PRGn)[1:3]
    )
end


#= Handles the time boundaries part of the global plot =#
function boundsplot(ax, loginfo::ExtendedLogInfo)
    # Axis attributes
    # ---------------
    ax.xticks = (1:3, ["Critical\nPath", "Without\nWaiting" , "Real"])
    ax.ylabel = "Time (s)"

    # Barplot
    # -------
    barplot!(
        ax,
        1:3,
        [loginfo.t∞, loginfo.t_nowait , (loginfo.lasttime-loginfo.firsttime)],
        color = cgrad(:sun)[1:3]
    )
end

#= Handles the sorting by labeled categories part of the plot =#
function categoriesplot(ax, loginfo::ExtendedLogInfo)
    categories = loginfo.categories
    hasdefault = (loginfo.timespercat[end] !=0 ? true : false)

    # Axis attributes
    lengthx = length(categories)
    ticks = first.(categories)
    hasdefault && (lengthx += 1)
    hasdefault && (ticks = [ticks..., "default"])
    ax.xticks = (1:lengthx, ticks)
    ax.ylabel = "Time (s)"


    # Colors
    if length(loginfo.categories) ≥ 4
        grad = cgrad(:tab10)[1:length(loginfo.categories)+1]
        deleteat!(grad, 4)
    else
        grad = cgrad(:tab10)[1:length(loginfo.categories)]
    end
    hasdefault && (grad = [grad..., :black])

    # Barplot
    # -------
    y = loginfo.timespercat[1:end]
    !hasdefault && (y = y[1:end-1])
    barplot!(
        ax,
        1:lengthx,
        y,
        color = grad
    )

end

#= Handles the interactivity part of the plot =#
function react(ax, logger::LogInfo, gantt::Gantt)
    to = Observable("")

    on(events(ax.parent).mouseposition) do mp
        pos = mouseposition(ax.scene)

        k = 1
        match = false
        for tasklog ∈ Iterators.flatten(logger.tasklogs)
            condx = gantt.starts[k] <= pos[1] <= gantt.stops[k]
            condy = gantt.threads[k] - 0.3 <= pos[2] <= gantt.threads[k] + 0.3
            if condx && condy
                match = true
                tasklog.label != "" && (to[] = "$(tasklog.label)")
            end

            k += 1
        end

        !match && (to[] = "Task Label")

    end
    on(to) do t
        ax.title = "Parallel Trace\n$t"
    end
end


"""
    plot(loginfo; categories)

Plot DataFlowTasks `loginfo` labeled informations with categories.

Entries in `categories` define how to group tasks in categories for
plotting. Each entry can be:
- a `String`: in this case, all tasks having labels in which the string occurs
  are grouped together. The string is also used as a label for the category
  itself.
- a `String => Regex` pair: in this case, all tasks having labels matching the
  regex are grouped together. The string is used as a label for the category
  itself.

See the
[documentation](https://maltezfaria.github.io/DataFlowTasks.jl/dev/profiling/)
for more information on how to profile and visualize `DataFlowTasks`.
"""
function plot(logger; categories=String[])
    # Figure
    # ------
    fig = Figure(
        backgroundcolor = RGBf(0.98, 0.98, 0.98),
        resolution = (1280, 720)
    )

    # Extract logger informations
    # ---------------------------
    loginfo = ExtendedLogInfo(logger, categories, longest_path(logger))
    gantt = Gantt()
    extractloggerinfo!(logger, loginfo, gantt)

    # Layouts
    # --------------------------------------------
    axtrc = Axis(fig[1,1]     , title="Parallel Trace\n Task Label")
    axact = Axis(fig[2,1][1,1], title="Activity")
    axinf = Axis(fig[2,1][1,2], title="Time Bounds")
    axcat = Axis(fig[2,1][1,3], title="Times per Category")
    # -------
    rowsize!(fig.layout, 1, Relative(2/3))

    # Plot each part
    # --------------
    traceplot(axtrc, logger, gantt, loginfo)
    activityplot(axact, loginfo)
    boundsplot(axinf, loginfo)
    categoriesplot(axcat, loginfo)

    # Events management
    react(axtrc, logger, gantt)

    # Terminal Informations
    # ---------------------
    @info "Computing    : $(loginfo.computingtime)"
    @info "Inserting    : $(loginfo.insertingtime)"
    @info "Other        : $(loginfo.othertime)"

    fig
end
