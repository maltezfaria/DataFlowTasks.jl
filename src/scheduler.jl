struct Scheduler
    task_graph::TaskGraph
end

function run(sch::Scheduler)
    tasks = gettasks(sch.task_graph)
    for codelet in tasks
        task = schedule(codelet)
        wait(task)
    end
end

function run(sch::Scheduler)
    tasks = gettasks(sch.task_graph)
    for codelet in tasks
        task = schedule(codelet)
        wait(task)
    end
end
