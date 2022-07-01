
"""
    struct Gantt  
Contains data to plot the Gantt Chart (parallel trace).  
It's a Struct of Array paradigm where all the entries i 
of all the arrays tells us information about a same task.
"""
struct Gantt
    threads::Vector{Int64}
    jobids::Vector{Int64}
    starts::Vector{Float64}
    stops::Vector{Float64}

    function Gantt()
        threads = Vector{Int64}()
        jobids  = Vector{Int64}()
        starts  = Vector{Float64}()
        stops   = Vector{Float64}()
        new(threads, jobids, starts, stops)
    end
end


"""
    mutable struct LoggerInfo  
Contains additionnal informations on the logger
"""
mutable struct LoggerInfo
    firsttime::Float64              # First measured time
    lasttime::Float64               # Last measured time
    computingtime::Float64          # Cumulative time spent computing
    insertingtime::Float64          # Cumulative time spent inserting
    othertime::Float64              # Cumulative other time
    t∞::Float64                     # Inf. proc time
    timespercat::Vector{Float64}    # timespercat[i] cumulative time for category i
    categories::Vector{String}      # labels
    path::Vector{Int64}             # Critical Path

    function LoggerInfo(logger::Logger, categories, path)
        (firsttime, lasttime) = timelimits(logger) .* 10^(-9)
        othertime     = (lasttime-firsttime) * length(logger.tasklogs)
        new(firsttime, lasttime, 0, 0, othertime, 0, zeros(length(categories)), categories, path)
    end
end


"""
    timelimits(logger) -> (firsttime, lasttime)  
Gives minimum and maximum times the logger has measured.
"""
function timelimits(logger::Logger)
    iter = Iterators.flatten(logger.tasklogs)
    minimum(t->t.time_start,iter), maximum(t->t.time_finish,iter)
end


"""
    jobid(label, categories) -> id  
Considering a `label` and a the full list of labels `categories`,
gives the index of the occurence of label in `categories`.
"""
function jobid(label::String, categories)
    for i ∈ 1:length(categories)
        occursin(categories[i], label) && return i
    end
end


"""
    extractloggerinfo!(logger, loginfo, gantt)  
Initialize `gantt` and `loginfo` structures from `logger`.
"""
function extractloggerinfo!(logger::Logger, loginfo::LoggerInfo, gantt::Gantt)
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
        loginfo.othertime     -= task_duration
        loginfo.computingtime += task_duration
        loginfo.timespercat[jobid(tasklog.label, loginfo.categories)] += task_duration
        (tasklog.tag+1) ∈ loginfo.path && (loginfo.t∞ += task_duration)
    end

    # Gantt data : Initialization INSERTIONLOGS
    # -----------------------------------------
    for insertionlog ∈ Iterators.flatten(logger.insertionlogs)
        # Gantt data
        # ----------
        push!(gantt.threads, insertionlog.tid)
        push!(gantt.jobids , length(loginfo.categories)+1)
        push!(gantt.starts , insertionlog.time_start  * 10^(-9) - loginfo.firsttime)
        push!(gantt.stops  , insertionlog.time_finish * 10^(-9) - loginfo.firsttime)
    
        # General Informations
        # --------------------
        task_duration  = (insertionlog.time_finish - insertionlog.time_start) * 10^(-9)
        loginfo.othertime     -= task_duration
        loginfo.insertingtime += task_duration
    end

    gantt
end


"""
    traceplot(ax, gantt, loginfo)  
Plot the Gantt Chart (parallel trace) on ax.
"""
function traceplot(ax, gantt::Gantt, loginfo::LoggerInfo)
    # Axis attributes
    # ---------------
    ax.xlabel = "Time (s)"
    ax.ylabel = "Thread"
    ax.yticks = 1:max(gantt.threads...)
    xlims!(ax, 0, loginfo.lasttime-loginfo.firsttime)

    # Barplot
    # -------
    barplot!(
        ax,
        gantt.threads,
        gantt.stops,
        fillto = gantt.starts,
        direction = :x,
        color = cgrad(:tab10)[gantt.jobids],
        gap = 0.5,
        strokewidth = 0.5,
        strokecolor = :white,
        width = 1.25
    )

    # Labels
    # ------
    elements = [PolyElement(polycolor = cgrad(:tab10)[i]) for i in unique(gantt.jobids)]
    elements[end].polycolor = :red  # inserting color
    Legend(
        ax.parent[2,1][1,3],
        elements,
        [loginfo.categories..., "insertion"],
        "Task types",
        orientation = :horizontal,
        halign = :right, valign = :center,
        margin = (5, 5, 5, 5)
    )
end


"""
    activityplot(ax, loginfo)  
Plot on ax the activity plot : barplot that indicates the repartition 
between computing, inserting, and other times.
"""
function activityplot(ax, loginfo::LoggerInfo)
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
        color = [:green, :red, :black]
    )
end


"""
    infprocplot(ax, loginfo)  
Plot on ax the barplot comparing the computation time 
if we had an infinite number of procs and the real time.
"""
function infprocplot(ax, loginfo::LoggerInfo)
    # Axis attributes
    # ---------------
    ax.xticks = (1:2, ["Inf. Proc", "Real"])
    ax.ylabel = "Time (s)"

    # Barplot
    # -------
    barplot!(
        ax,
        1:2,
        [loginfo.t∞, (loginfo.lasttime-loginfo.firsttime)],
        color = [:green, :red]
    )
end


"""
    categoriesplot(ax, loginfo)  
Plots the cumulative times for each given category.
"""
function categoriesplot(ax, loginfo::LoggerInfo)
    categories = loginfo.categories

    # Axis attributes
    # ---------------
    ax.xticks = (1:length(categories), categories)
    ax.ylabel = "Time (s)"

    # Barplot
    # -------
    barplot!(
        ax,
        1:length(categories),
        loginfo.timespercat,
        color = cgrad(:tab10)[1:length(categories)]
    )
end


"""
    dagplot(ax)  
Plot the dag to the Makie axis ax
"""
function dagplot(ax, logger)
    # Create GraphViz graph DOT format file
    g = Graph(loggertodot(logger))

    # Node positionning
    GraphViz.layout!(g)

    # Render this to a Cairo context to convert in png
    cs = GraphViz.cairo_render(g)
    Cairo.write_to_png(cs, "./dag_tmp.png")

    # Load the png we juste created
    img = load("./dag_tmp.png")

    # Render the png on the Makie axis
    GLMakie.image!(ax, rotr90(img))

    # Axis attributes
    ax.aspect = DataAspect()
    hidedecorations!(ax)
    hidespines!(ax)

    # Remove the temporary png
    rm("./dag_tmp.png")
end
function dagplot(logger=getlogger())
    fig = Figure()
    dagplot(Axis(fig[1,1], title = "Graph"), logger)
    fig
end


function react(axtrc, logger, loginfo)
    to = Observable("")

    Box(
        axtrc.parent[2,1][1,1:2],
        color = RGBAf(0.5, 0.5, 0.8, 0.2),
        halign=:left,
        width = Relative(0.9),
    )

    header = ""
    header *= "   Task Dag ID\n"
    header *= "   Label\n"
    Label(
        axtrc.parent[2,1][1,1],
        header,
        halign=:left, valign=:center,
        justification=:left,
        width = Relative(0.5)
    )
    l = Label(
        axtrc.parent[2,1][1,2],
        "",
        textsize = 20,
        halign=:left, valign=:center,
        justification=:left,
        width = Relative(0.5)
    )


    on(to) do t
        l.text = t
    end


    on(events(axtrc.parent).mouseposition) do mp
        pos = mouseposition(axtrc.scene)
        
        for tasklog ∈ Iterators.flatten(logger.tasklogs) 
            x1 = tasklog.time_start * 10^(-9) - loginfo.firsttime
            x2 = tasklog.time_finish * 10^(-9) - loginfo.firsttime
            y1 = tasklog.tid - 0.3
            y2 = tasklog.tid + 0.3

            if x1 <= pos[1] <= x2 && y1 <= pos[2] <= y2  
                to[] = "$(tasklog.tag)\n$(tasklog.label)"
            end
        end
    end
end


"""
    plot(logger; categories)  
Main plot function.
"""
function plot(logger::Logger; categories=String[])
    # Figure
    # ------
    fig = Figure(
        backgroundcolor = RGBf(0.98, 0.98, 0.98),
        resolution = (1280, 720)
    )

    # Extract logger informations
    # ---------------------------
    loginfo = LoggerInfo(logger, categories, criticalpath())
    gantt = Gantt()
    extractloggerinfo!(logger, loginfo, gantt)
    shouldplotdag = (nbtasknodes(logger) < 75)  # arbitrary limit

    # Layouts (conditionnal depending on DAG size)
    # --------------------------------------------
    axtrc = Axis(fig[1,1]     , title="Parallel Trace")
    axact = Axis(fig[3,1][1,1], title="Activity")
    axinf = Axis(fig[3,1][1,2], title="Time Infinite Proc")
    axcat = Axis(fig[3,1][1,3], title="Times per Category")
    if !shouldplotdag
        @info "The dag has too many nodes, plot it separately with `dagplot()` so it can be readable"
    else
        axdag = Axis(fig[1:3,2]   , title="Graph")
        colsize!(fig.layout, 1, Relative(3/4))
    end
    # -------
    rowsize!(fig.layout, 1, Relative(2/3))


    # Plot each part
    # --------------
    traceplot(axtrc, gantt, loginfo)
    activityplot(axact, loginfo)
    infprocplot(axinf, loginfo)
    categoriesplot(axcat, loginfo)
    shouldplotdag && dagplot(axdag, logger)

    # Events management
    react(axtrc, logger, loginfo)

    # Terminal Informations
    # ---------------------
    @info "Computing    : $(loginfo.computingtime)"
    @info "Inserting    : $(loginfo.insertingtime)"
    @info "Other        : $(loginfo.othertime)"

    fig
end