module DataFlowTasks_Makie_Ext

using Makie
import DataFlowTasks as DFT
using DataFlowTasks: LogInfo, LogSummary, summarize, idle, nowait

function __init__()
    return @info "Loading DataFlowTasks general plot utilities"
end

#= Colors of `n` categories, followed by the color of the tasks in no category =#
function category_colors(n::Int)
    if n ≥ 4
        grad = cgrad(:tab10)[1:(n + 1)]
        deleteat!(grad, 4) # the red is used for the insertions
    else
        grad = cgrad(:tab10)[1:n]
    end
    return RGBAf[grad..., to_color(:black)]
end

const INSERTION_COLOR = RGBAf(1, 0, 0, 1)
const WAITING_COLOR = RGBAf(0.6, 0.6, 0.6, 0.5)
const GC_COLOR = to_color(cgrad(:sun)[1])
const PREDECESSOR_COLOR = RGBAf(0.1, 0.3, 0.9, 1)
const SUCCESSOR_COLOR = RGBAf(0.9, 0.5, 0, 1)
const SELECTED_COLOR = RGBAf(0.8, 0, 0.8, 1)
# opacity of the part of a bar above its running fraction
const TINT = 0.25

# half of the height of a bar
const BAR = 0.4

"""
    traceplot(loginfo; categories, highlight, critical_path)

Plot the trace of the tasks logged in `loginfo` (see
[`DataFlowTasks.timeline`](@ref)): each task is a bar, from the moment its body
started to the moment it finished. Bars are packed in lanes such that the bars of
a lane do not overlap. A lane is not a thread, since a task may migrate between
threads.

- Bars are colored by category (see [`DataFlowTasks.summarize`](@ref)), and
  filled up to the fraction of their duration the tasks were running, like a
  gauge: a task which only sleeps is an empty (light) bar. Failed tasks are
  outlined in red.
- The insertions in the DAG are shown in lane `0`: the time spent waiting for the
  DAG (in grey), in the garbage collector (in yellow), and analysing the data
  dependencies (in red).
- The tasks of the realized critical path (see
  [`DataFlowTasks.realized_critical_path`](@ref)) are outlined in black.
- The task with tag `highlight` (if any) is outlined in purple, its predecessors
  in blue and its successors in orange, and the predecessor which made it ready
  is linked to it by a dashed line.
"""
@recipe TracePlot (loginfo::LogInfo,) begin
    "Categories of tasks, given as in `DataFlowTasks.summarize`."
    categories = String[]
    "Tag of the task to highlight with its dependencies, or `0` for none."
    highlight = 0
    "Whether to show the realized critical path."
    critical_path = true
end

seconds(l::LogInfo, t) = DFT._seconds(l, t)
bar(lane, start, finish) = Rect2f(start, lane - BAR, finish - start, 2BAR)

function Makie.plot!(p::TracePlot)
    map!(
        p, [:loginfo, :categories],
        [:tasks, :bars, :tints, :fills, :colors, :strokecolors, :insertion_bars, :insertion_colors, :path],
    ) do l, categories
        categories = map(DFT._category, categories)
        tasks = DFT.timeline(l)
        palette = category_colors(length(categories))
        bars = [bar(t.lane, t.started, t.finished) for t in tasks]
        colors = [palette[DFT.jobid(t.label, categories)] for t in tasks]
        tints = [RGBAf(c.r, c.g, c.b, TINT) for c in colors]
        # the bars are filled from the bottom up to the running fraction
        fills = map(tasks) do t
            d = t.finished - t.started
            fraction = d == 0 ? 1.0 : clamp(t.running / d, 0, 1)
            return Rect2f(t.started, t.lane - BAR, d, 2BAR * fraction)
        end
        strokecolors = [t.failed ? RGBAf(1, 0, 0, 1) : RGBAf(0.5, 0.5, 0.5, 1) for t in tasks]
        # insertions: waiting for the dag, then garbage collection (if any), then
        # analysis of the data dependencies
        insertion_bars, insertion_colors = Rect2f[], RGBAf[]
        for i in l.insertionlogs
            gc_finish = i.time_start + i.gc_time
            for (start, finish, color) in (
                    (i.time_request, i.time_start, WAITING_COLOR),
                    (i.time_start, gc_finish, GC_COLOR),
                    (gc_finish, i.time_finish, INSERTION_COLOR),
                )
                finish > start || continue
                push!(insertion_bars, bar(0, seconds(l, start), seconds(l, finish)))
                push!(insertion_colors, color)
            end
        end
        bytag = Dict(DFT.tag(t) => t for t in tasks)
        path = [(t = bytag[k]; bar(t.lane, t.started, t.finished)) for k in DFT.realized_critical_path(l)]
        return tasks, bars, tints, fills, colors, strokecolors, insertion_bars, insertion_colors, path
    end
    map!(
        p, [:tasks, :highlight],
        [:highlight_bars, :highlight_colors, :highlight_link],
    ) do tasks, highlight
        bars, colors, link = Rect2f[], RGBAf[], Point2f[]
        k = findfirst(t -> DFT.tag(t) == highlight, tasks)
        isnothing(k) && return bars, colors, link
        t = tasks[k]
        for s in tasks
            color = if s === t
                SELECTED_COLOR
            elseif DFT.tag(s) ∈ t.predecessors
                PREDECESSOR_COLOR
            elseif DFT.tag(t) ∈ s.predecessors
                SUCCESSOR_COLOR
            else
                continue
            end
            push!(bars, bar(s.lane, s.started, s.finished))
            push!(colors, color)
            if DFT.tag(s) == t.ready_by
                push!(link, Point2f(s.finished, s.lane), Point2f(t.started, t.lane))
            end
        end
        return bars, colors, link
    end
    poly!(p, p.insertion_bars; color = p.insertion_colors)
    poly!(p, p.bars; color = p.tints, strokecolor = p.strokecolors, strokewidth = 0.5)
    poly!(p, p.fills; color = p.colors)
    poly!(p, p.path; color = :transparent, strokecolor = :black, strokewidth = 2, visible = p.critical_path)
    poly!(p, p.highlight_bars; color = :transparent, strokecolor = p.highlight_colors, strokewidth = 2)
    linesegments!(p, p.highlight_link; color = :black, linestyle = :dash)
    return p
end

DFT.traceplot(args...; kwargs...) = traceplot(args...; kwargs...)
DFT.traceplot!(args...; kwargs...) = traceplot!(args...; kwargs...)

#= Legend of the trace =#
function tracelegend(position, loginfo::LogInfo, summary::LogSummary)
    palette = category_colors(length(summary.categories))
    elements = Any[PolyElement(; polycolor = c) for c in palette]
    labels = String[first.(summary.categories)..., "uncategorized"]
    if summary.running_per_category[end] == 0 # no uncategorized task
        pop!(elements), pop!(labels)
    end
    push!(elements, PolyElement(; polycolor = WAITING_COLOR), PolyElement(; polycolor = INSERTION_COLOR))
    push!(labels, "waiting for the DAG", "insertion")
    if any(i -> i.gc_time > 0, loginfo.insertionlogs)
        push!(elements, PolyElement(; polycolor = GC_COLOR))
        push!(labels, "gc")
    end
    push!(elements, PolyElement(; polycolor = :transparent, strokecolor = :black, strokewidth = 2))
    percent(x) = string(round(Int, 100 * x / summary.elapsed), "%")
    push!(
        labels,
        "realized critical path ($(percent(summary.realized_bodies)) task bodies, " *
            "$(percent(summary.realized_waiting)) waiting to start, " *
            "$(percent(summary.realized_before)) before its first task)",
    )
    return Legend(position, elements, labels; orientation = :horizontal, framevisible = false)
end

#= The task under the mouse position `pos` (in data coordinates), if any =#
function task_at(tasks, pos)
    lane = round(Int, pos[2])
    abs(pos[2] - lane) <= BAR || return nothing
    k = findfirst(t -> t.lane == lane && t.started <= pos[1] <= t.finished, tasks)
    return isnothing(k) ? nothing : tasks[k]
end

ms(t) = string(round(1000t; sigdigits = 3), " ms")

#= Describe the lifecycle of task `t` =#
function describe_task(t)
    head = "Task $(DFT.tag(t))" * (isempty(t.label) ? "" : " \"$(t.label)\"")
    d = t.finished - t.started
    return string(
        head, "\n",
        "insertion: ", ms(t.inserted - t.requested),
        " (waiting ", ms(t.insertion_start - t.requested), ")",
        " · ready after ", t.ready_by == 0 ? "its insertion" : "task $(t.ready_by)",
        " · latency: ", ms(t.started - t.ready),
        " · duration: ", ms(d), " (", round(Int, 100 * (d == 0 ? 1 : t.running / d)), "% running)",
    )
end

#= Highlight the task under the mouse, and describe it in the title of `ax` =#
function react(ax, tp)
    title = ax.title[]
    on(events(ax.parent).mouseposition) do _
        t = task_at(tp.tasks[], mouseposition(ax.scene))
        tag = isnothing(t) ? 0 : DFT.tag(t)
        if tag != tp.highlight[]
            tp.highlight = tag
            ax.title = isnothing(t) ? title : describe_task(t)
        end
        return Consume(false)
    end
    return
end

#= Handles the plot of the time of the workers (running or idle), and of the
time spent blocked in tasks and inserting them =#
function activityplot(ax, summary::LogSummary)
    # Axis attributes
    # ---------------
    ax.xticks = (1:4, ["Running", "Idle", "Blocked\nin tasks", "Task\ninsertion"])
    ax.ylabel = "Time (s)"

    # Barplot
    # -------
    return barplot!(
        ax,
        1:4,
        [summary.running, idle(summary), summary.blocked, summary.insertion];
        color = cgrad(:PRGn)[1:4],
    )
end

#= Handles the time boundaries part of the global plot =#
function boundsplot(ax, summary::LogSummary)
    # Axis attributes
    # ---------------
    ax.xticks = (1:3, ["Critical\nPath", "No-Wait", "Elapsed"])
    ax.ylabel = "Time (s)"

    # Barplot
    # -------
    return barplot!(
        ax,
        1:3,
        [summary.critical_path, nowait(summary), summary.elapsed];
        color = cgrad(:sun)[1:3],
    )
end

#= Handles the sorting by labeled categories part of the plot =#
function categoriesplot(ax, summary::LogSummary)
    categories = summary.categories
    hasdefault = (summary.running_per_category[end] != 0 ? true : false)

    # Axis attributes
    lengthx = length(categories)
    ticks = first.(categories)
    hasdefault && (lengthx += 1)
    hasdefault && (ticks = [ticks..., "uncategorized"])
    ax.xticks = (1:lengthx, ticks)
    ax.ylabel = "Time (s)"

    # Colors
    grad = category_colors(length(categories))
    hasdefault || pop!(grad)

    # Barplot
    # -------
    y = summary.running_per_category[1:end]
    !hasdefault && (y = y[1:(end - 1)])
    return barplot!(ax, 1:lengthx, y; color = grad)
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
    fig = Figure(; backgroundcolor = RGBf(0.98, 0.98, 0.98), size = (1280, 720))

    # Extract logger informations
    # ---------------------------
    summary = summarize(loginfo; categories)

    # Layouts
    # --------------------------------------------
    axtrc = Axis(
        fig[1, 1];
        title = "Parallel trace\n(hover over a task for details)",
        xlabel = "Time (s)",
        ylabel = "Lane",
    )
    axact = Axis(fig[2, 1][1, 1]; title = "Time: breakdown by activity")
    axinf = Axis(fig[2, 1][1, 2]; title = "Elapsed time & bounds")
    axcat = Axis(fig[2, 1][1, 3]; title = "Running time: breakdown by category")
    # -------
    rowsize!(fig.layout, 1, Relative(2 / 3))

    # Plot each part
    # --------------
    tp = traceplot!(axtrc, loginfo; categories)
    xlims!(axtrc, 0, summary.elapsed)
    lanes = maximum((t.lane for t in tp.tasks[]); init = 0)
    axtrc.yticks = (0:lanes, ["insertion", string.(1:lanes)...])
    tracelegend(fig[0, 1], loginfo, summary)
    activityplot(axact, summary)
    boundsplot(axinf, summary)
    categoriesplot(axcat, summary)

    # Events management
    react(axtrc, tp)

    return fig
end

end
