module DataFlowTasks_Makie_Ext

using Makie
using DataFlowTasks: LogInfo, longest_path, ExtendedLogInfo, extractloggerinfo, Gantt

function __init__()
    @info "Loading DataFlowTasks general plot utilities"
end

#= Handles the gantt chart trace part of the global plot =#
function traceplot(ax, logger::LogInfo, gantt::Gantt, loginfo::ExtendedLogInfo)
    hasdefault = (loginfo.timespercat[end] != 0 ? true : false)

    lengthx = length(loginfo.categories) + 1
    hasdefault && (lengthx += 1)

    # Axis attributes
    # ---------------
    ax.xlabel = "Time (s)"
    ax.ylabel = "Thread"
    ax.yticks = 1:max(gantt.threads...)
    xlims!(ax, 0, loginfo.lasttime - loginfo.firsttime)

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
        gantt.stops;
        fillto = gantt.starts,
        direction = :x,
        color = colors[gantt.jobids],
        gap = 0.5,
        strokewidth = 0.5,
        strokecolor = :grey,
        width = 1.25,
    )

    # Check if we measured some gc
    didgc = false
    for insertionlog in Iterators.flatten(logger.insertionlogs)
        insertionlog.gc_time != 0 && (didgc = true)
    end

    # Labels
    c = [grad...]
    hasdefault && (c = [c..., :black])
    c = [c..., :red]
    didgc && (c = [c..., cgrad(:sun)[1]])
    elements = [PolyElement(; polycolor = i) for i in c]

    y = String[]
    push!(y, first.(loginfo.categories)...)
    # y = [first.(loginfo.categories)...]
    hasdefault && push!(y, "default")
    push!(y, "insertion")
    didgc && push!(y, "gc")

    return Legend(
        ax.parent[1, 1],
        elements,
        y;
        orientation = :horizontal,
        halign = :right,
        valign = :top,
        margin = (5, 5, 5, 5),
    )
end

#= Handles the plot that indicates the repartition between computing, inserting, and other times =#
function activityplot(ax, loginfo::ExtendedLogInfo)
    # Axis attributes
    # ---------------
    ax.xticks = (1:3, ["Computing", "Task\nInsertion", "Other\n(idle)"])
    ax.ylabel = "Time (s)"

    # Barplot
    # -------
    return barplot!(
        ax,
        1:3,
        [loginfo.computingtime, loginfo.insertingtime, loginfo.othertime];
        color = cgrad(:PRGn)[1:3],
    )
end

#= Handles the time boundaries part of the global plot =#
function boundsplot(ax, loginfo::ExtendedLogInfo)
    # Axis attributes
    # ---------------
    ax.xticks = (1:3, ["Critical\nPath", "No-Wait", "Elapsed"])
    ax.ylabel = "Time (s)"

    # Barplot
    # -------
    return barplot!(
        ax,
        1:3,
        [loginfo.t∞, loginfo.t_nowait, (loginfo.lasttime - loginfo.firsttime)];
        color = cgrad(:sun)[1:3],
    )
end

#= Handles the sorting by labeled categories part of the plot =#
function categoriesplot(ax, loginfo::ExtendedLogInfo)
    categories = loginfo.categories
    hasdefault = (loginfo.timespercat[end] != 0 ? true : false)

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
    return barplot!(ax, 1:lengthx, y; color = grad)
end

#= Handles the interactivity part of the plot =#
function react(ax, logger::LogInfo, gantt::Gantt)
    to = Observable("")

    on(events(ax.parent).mouseposition) do mp
        pos = mouseposition(ax.scene)

        k = 1
        match = false
        for tasklog in Iterators.flatten(logger.tasklogs)
            condx = gantt.starts[k] <= pos[1] <= gantt.stops[k]
            condy = gantt.threads[k] - 0.3 <= pos[2] <= gantt.threads[k] + 0.3
            if condx && condy
                match = true
                tasklog.label != "" && (to[] = "$(tasklog.label)")
            end

            k += 1
        end

        return !match && (to[] = "Task Label")
    end
    on(to) do t
        return ax.title = "Parallel Trace\n$t"
    end
end

"""
    plot(log_info; categories)

Plot DataFlowTasks `log_info` labeled informations with categories.

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
function Makie.plot(loginfo::LogInfo; categories = String[])
    # Figure
    # ------
    fig = Figure(; backgroundcolor = RGBf(0.98, 0.98, 0.98), resolution = (1280, 720))

    # Extract logger informations
    # ---------------------------
    extloginfo, gantt = extractloggerinfo(loginfo; categories)

    # Layouts
    # --------------------------------------------
    axtrc = Axis(fig[1, 1]; title = "Parallel Trace\n Task Label")
    axact = Axis(fig[2, 1][1, 1]; title = "Run time: breakdown by activity")
    axinf = Axis(fig[2, 1][1, 2]; title = "Elapsed time & bounds")
    axcat = Axis(fig[2, 1][1, 3]; title = "Computing time: breakdown by category")
    # -------
    rowsize!(fig.layout, 1, Relative(2 / 3))

    # Plot each part
    # --------------
    traceplot(axtrc, loginfo, gantt, extloginfo)
    activityplot(axact, extloginfo)
    boundsplot(axinf, extloginfo)
    categoriesplot(axcat, extloginfo)

    # Events management
    react(axtrc, loginfo, gantt)

    # Terminal Informations
    # ---------------------
    @info "Computing    : $(extloginfo.computingtime)"
    @info "Inserting    : $(extloginfo.insertingtime)"
    @info "Other        : $(extloginfo.othertime)"

    return fig
end

end
