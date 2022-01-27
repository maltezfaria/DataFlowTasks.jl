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

TaskLog = @NamedTuple begin
    threadid::Int
    time_start::Int
    time_finish::Int
    task_tag::Int
    task_label::String
end

mutable struct Logger <: AbstractLogger
    stream::IO
    ref_time::Int
    tasklogs::Vector{TaskLog}
    runnablelog::Tuple{Vector{Int},Vector{Int}}
    finishedlog::Tuple{Vector{Int},Vector{Int}}
end

function Logger(io::IOStream)
    Logger(io,0,TaskLog[],(Int[],Int[]),(Int[],Int[]))
end

# abstract logger interface

Logging.shouldlog(logger::Logger, level, _module, group, id) = level == TraceLogLevel

Logging.min_enabled_level(::Logger) = TraceLogLevel

function Logging.handle_message(logger::Logger, level::LogLevel, message, _module, group, id,filepath, line; kwargs...)
    @nospecialize
    buf    = IOBuffer()
    stream = logger.stream
    if !isopen(stream)
        stream = stderr
    end
    iob = IOContext(buf, stream)
    println(iob, message)
    for (key, val) in kwargs
        println(iob, "│   ", key, " = ", val)
    end
    write(stream, take!(buf))
    nothing
end

reset_timer!(logger::Logger) = (logger.ref_time = time_ns())

function reset!(logger::Logger)
    io = logger.stream
    close(io)
    logger.stream = open(io.name,"w+")
    reset_timer!(logger)
end

# parsing the io into data
function parse!(log::Logger)
    _parse_tasks!(log)
    _parse_runnable!(log)
    _parse_finished!(log)
end

function _parse_tasks!(log::Logger)
    io      = log.stream
    seekstart(io)
    events  = log.tasklogs
    for l in eachline(io)
        words = split(l)
        words[1] == "task_info" || continue
        tid,ts,te,tag = parse.(Int,words[2:5])
        if length(words) == 5 # empty label
            push!(events,(threadid=tid,time_start=ts,time_finish=te,task_tag=tag,task_label=""))
        else
            label = words[6:end]
            push!(events,(threadid=tid,time_start=ts,time_finish=te,task_tag=tag,task_label=join(label," ")))
        end
    end
    return log
end

function _parse_runnable!(log::Logger)
    io      = log.stream
    seekstart(io)
    nn,tt = log.runnablelog
    for l in eachline(io)
        words = split(l)
        words[1] == "length_runnable" || continue
        n,t = parse.(Int,words[2:3])
        push!(nn,n)
        push!(tt,t)
    end
    return log
end

function _parse_finished!(log::Logger)
    io      = log.stream
    seekstart(io)
    nn,tt = log.finishedlog
    for l in eachline(io)
        words = split(l)
        words[1] == "length_finished" || continue
        n,t = parse.(Int,words[2:3])
        push!(nn,n)
        push!(tt,t)
    end
    return log
end

# plot the logger

# graphplot(logger::Logger) = graphplot(logger.dag)

@recipe function f(log::Logger)
    xlabel --> "time (s)"
    ylabel --> "threadid"
    xlims --> (0,Inf)
    # yflip  := true
    seriestype := :shape
    tasklogs = log.tasklogs
    yticks --> unique(t.threadid for t in tasklogs)
    seriesalpha  --> 0.5
    # loop all data and plot the lines
    for (tid,ts,te,tag) in log.tasklogs
        @series begin
            label --> nothing
            x1 = (ts-log.ref_time)/1e9
            x2 = (te-log.ref_time)/1e9
            y1 = tid - 0.25
            y2 = tid + 0.25
            [x1,x2,x2,x1,x1],[y1,y1,y2,y2,y1]
        end
    end
end

struct PlotFinished end
struct PlotRunnable end

@recipe function f(::PlotFinished,log::Logger)
    xlabel --> "time (s)"
    ylabel --> "length"
    xlims --> (0,Inf)
    lw --> 2
    label --> "finished channel"
    # yflip  := true
    seriestype := :line
    l,t = log.finishedlog # length,time
    yticks --> unique(l)
    (t .- log.ref_time[])/1e9,l
end

@recipe function f(::PlotRunnable,log::Logger)
    xlabel --> "time (s)"
    ylabel --> "length"
    xlims --> (0,Inf)
    lw --> 2
    label --> "runnable channel"
    # yflip  := true
    seriestype := :line
    l,t = log.runnablelog # length,time
    yticks --> unique(l)
    (t .- log.ref_time[])/1e9,l
end
