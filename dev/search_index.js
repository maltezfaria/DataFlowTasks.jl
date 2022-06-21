var documenterSearchIndex = {"docs":
[{"location":"references/#references-section","page":"References","title":"References","text":"","category":"section"},{"location":"references/","page":"References","title":"References","text":"Modules =   [DataFlowTasks,\n            DataFlowTasks.TiledFactorization]","category":"page"},{"location":"references/#DataFlowTasks.DataFlowTasks","page":"References","title":"DataFlowTasks.DataFlowTasks","text":"moduel DataFlowTask\n\nCreate Tasks wich keep track of how data flows through it.\n\n\n\n\n\n","category":"module"},{"location":"references/#DataFlowTasks.SCHEDULER","page":"References","title":"DataFlowTasks.SCHEDULER","text":"const SCHEDULER::Ref{TaskGraphScheduler}\n\nThe active scheduler being used.\n\n\n\n\n\n","category":"constant"},{"location":"references/#DataFlowTasks.TASKCOUNTER","page":"References","title":"DataFlowTasks.TASKCOUNTER","text":"const TASKCOUNTER::Ref{Int}\n\nGlobal counter of created DataFlowTasks.\n\n\n\n\n\n","category":"constant"},{"location":"references/#DataFlowTasks.AccessMode","page":"References","title":"DataFlowTasks.AccessMode","text":"@enum AccessMode READ WRITE READWRITE\n\nDescribe how a DataFlowTask access its data.\n\n\n\n\n\n","category":"type"},{"location":"references/#DataFlowTasks.DAG","page":"References","title":"DataFlowTasks.DAG","text":"struct DAG{T}\n\nRepresentation of a directed acyclic graph containing nodes of type T. The list of nodes with edges coming into a node i can be retrieved using inneighbors(dag,i); similarly, the list of nodes with edges leaving from i can be retrieved using outneighbors(dag,i).\n\nDAG is a buffered structure with a buffer of size sz_max: calling addnode! on it will block if the DAG has more than sz_max elements.\n\n\n\n\n\n","category":"type"},{"location":"references/#DataFlowTasks.DAG-Union{Tuple{}, Tuple{Any}, Tuple{T}} where T","page":"References","title":"DataFlowTasks.DAG","text":"DAG{T}(sz)\n\nCreate a buffered DAG holding a maximum of s nodes of type T.\n\n\n\n\n\n","category":"method"},{"location":"references/#DataFlowTasks.DataFlowTask","page":"References","title":"DataFlowTasks.DataFlowTask","text":"DataFlowTask(func,data,mode)\n\nCreate a task-like object similar to Task(func) which accesses data with AccessMode mode.\n\nWhen a DataFlowTask is created, the elements in its data field will be checked against all other active DataFlowTask to determined if a dependency is present based on a data-flow analysis. The resulting Task will then wait on those dependencies.\n\nA DataFlowTask behaves much like a Julia Task: you can call wait(t), schedule(t) and fetch(t) on it.\n\nSee also: @dtask, @dspawn, @dasync.\n\n\n\n\n\n","category":"type"},{"location":"references/#DataFlowTasks.FinishedChannel","page":"References","title":"DataFlowTasks.FinishedChannel","text":"struct FinishedChannel{T} <: AbstractChannel{T}\n\nUsed to store tasks which have been completed, but not yet removed from the underlying DAG. Taking from an empty FinishedChannel will block.\n\n\n\n\n\n","category":"type"},{"location":"references/#DataFlowTasks.JuliaScheduler","page":"References","title":"DataFlowTasks.JuliaScheduler","text":"struct JuliaScheduler{T} <: TaskGraphScheduler{T}\n\nImplement a simple scheduling strategy which consists of delegating the DataFlowTasks to the native Julia scheduler for execution immediately after the data dependencies have been analyzed using its dag::DAG. This is the default scheduler used by DataFlowTasks.\n\nThe main advantage of this strategy is its simplicity and composability. The main disadvantage is that there is little control over how the underlying Tasks are executed by the Julia scheduler (e.g., no priorities can be passed).\n\nCalling JuliaScheduler(sz) creates a new scheduler with an empty DAG of maximum capacity sz.\n\n\n\n\n\n","category":"type"},{"location":"references/#DataFlowTasks.PriorityScheduler","page":"References","title":"DataFlowTasks.PriorityScheduler","text":"struct PriorityScheduler{T} <: TaskGraphScheduler{T}\n\nExecute a DAG by spawning workers that take elements from the runnable channel, execute them, and put them into a finished channel to be processed by a dag_worker.\n\n\n\n\n\n","category":"type"},{"location":"references/#DataFlowTasks.RunnableChannel","page":"References","title":"DataFlowTasks.RunnableChannel","text":"struct RunnableChannel <: AbstractChannel{DataFlowTask}\n\nUsed to store tasks which have been tagged as dependency-free, and thus can be executed. The underlying data is stored using a priority queue, with elements with a high priority being popped first.\n\nCalling take on an empty RunnableChannel will block.\n\n\n\n\n\n","category":"type"},{"location":"references/#DataFlowTasks.StaticScheduler","page":"References","title":"DataFlowTasks.StaticScheduler","text":"StaticScheduler{T} <: TaskGraphScheduler{T}\n\nLike the JuliaScheduler, but requires an explicit call to execute_dag(ex) to start running the nodes in its dag (and removing them as they are completed).\n\nUsing a StaticScheduler is useful if you wish examine the underling TaskGraph before it is executed.\n\n\n\n\n\n","category":"type"},{"location":"references/#DataFlowTasks.Stop","page":"References","title":"DataFlowTasks.Stop","text":"struct Stop\n\nSingleton type used to safely interrupt a task reading from an `AbstractChannel.\n\n\n\n\n\n","category":"type"},{"location":"references/#DataFlowTasks.TaskGraph","page":"References","title":"DataFlowTasks.TaskGraph","text":"const TaskGraph = DAG{DataFlowTask}\n\nA directed acyclic graph of DataFlowTasks.\n\n\n\n\n\n","category":"type"},{"location":"references/#DataFlowTasks.TaskGraphScheduler","page":"References","title":"DataFlowTasks.TaskGraphScheduler","text":"abstract type TaskGraphScheduler\n\nStructures implementing a strategy to evaluate a DAG.\n\nConcrete subtypes are expected to contain a dag::DAG field for storing the task graph, and a finished::AbstractChannel field to keep track of completed tasks. The interface requires the following methods:\n\n-spawn(t,sch) -schedule(t,sch)\n\nSee also: JuliaScheduler, PriorityScheduler, StaticScheduler\n\n\n\n\n\n","category":"type"},{"location":"references/#DataFlowTasks.access_mode-Tuple{DataFlowTasks.DataFlowTask}","page":"References","title":"DataFlowTasks.access_mode","text":"access_mode(t::DataFlowTask[,i])\n\nHow t accesses its data.\n\nSee: AccessMode\n\n\n\n\n\n","category":"method"},{"location":"references/#DataFlowTasks.addedge!-Union{Tuple{T}, Tuple{DataFlowTasks.DAG{T}, T, T}} where T","page":"References","title":"DataFlowTasks.addedge!","text":"addedge!(dag,i,j)\n\nAdd (directed) edge connecting node i to node j in the dag.\n\n\n\n\n\n","category":"method"},{"location":"references/#DataFlowTasks.addedge_transitive!-Tuple{Any, Any, Any}","page":"References","title":"DataFlowTasks.addedge_transitive!","text":"addedge_transitive!(dag,i,j)\n\nAdd edge connecting nodes i and j if there is no path connecting them already.\n\n\n\n\n\n","category":"method"},{"location":"references/#DataFlowTasks.addnode!-Union{Tuple{T}, Tuple{DataFlowTasks.DAG{T}, T}, Tuple{DataFlowTasks.DAG{T}, T, Any}} where T","page":"References","title":"DataFlowTasks.addnode!","text":"addnode!(dag,(k,v)::Pair[, check=false])\naddnode!(dag,k[, check=false])\n\nAdd a node to the dag. If passed only a key k, the value v is initialized as empty (no edges added). The check flag is used to indicate if a data flow analysis should be performed to update the dependencies of the newly inserted node.\n\n\n\n\n\n","category":"method"},{"location":"references/#DataFlowTasks.adjacency_matrix-Union{Tuple{DataFlowTasks.DAG{T}}, Tuple{T}} where T","page":"References","title":"DataFlowTasks.adjacency_matrix","text":"adjacency_matrix(dag)\n\nConstruct the adjacency matrix of dag.\n\n\n\n\n\n","category":"method"},{"location":"references/#DataFlowTasks.consume_runnable-Tuple{Any, Any, Any}","page":"References","title":"DataFlowTasks.consume_runnable","text":"consume_runnable(runnable,nt)\n\nSpawn nt = Threads.nthreads()-1 background workers that will consume tasks from runnable and execute them. The main thread (Threads.threadid()==1) is not used.\n\n\n\n\n\n","category":"method"},{"location":"references/#DataFlowTasks.data-Tuple{DataFlowTasks.DataFlowTask}","page":"References","title":"DataFlowTasks.data","text":"data(t::DataFlowTask[,i])\n\nData accessed by t.\n\n\n\n\n\n","category":"method"},{"location":"references/#DataFlowTasks.data_dependency-Tuple{DataFlowTasks.DataFlowTask, DataFlowTasks.DataFlowTask}","page":"References","title":"DataFlowTasks.data_dependency","text":"data_dependency(t1::DataFlowTask,t1::DataFlowTask)\n\nDetermines if there is a data dependency between t1 and t2 based on the data they read from and write to.\n\n\n\n\n\n","category":"method"},{"location":"references/#DataFlowTasks.enable_debug","page":"References","title":"DataFlowTasks.enable_debug","text":"enable_debug(mode = true)\n\nIf mode is true (the default), enable debug mode: errors inside tasks will be shown.\n\n\n\n\n\n","category":"function"},{"location":"references/#DataFlowTasks.execute_dag-Tuple{DataFlowTasks.StaticScheduler}","page":"References","title":"DataFlowTasks.execute_dag","text":"execute_dag(sch::StaticScheduler)\n\nExecute all the nodes in the task graph, removing them from the dag as they are completed. This function waits for the dag to be emptied before returning.\n\n\n\n\n\n","category":"method"},{"location":"references/#DataFlowTasks.finished_to_runnable-Tuple{Any, Any, Any}","page":"References","title":"DataFlowTasks.finished_to_runnable","text":"finished_to_runnable(dag,runnable,finished)\n\nWorker which takes nodes from finished, remove them from the dag, and put! new nodes in runnable if they become dependency-free.\n\n\n\n\n\n","category":"method"},{"location":"references/#DataFlowTasks.getscheduler-Tuple{}","page":"References","title":"DataFlowTasks.getscheduler","text":"getscheduler(sch)\n\nReturn the active scheduler.\n\n\n\n\n\n","category":"method"},{"location":"references/#DataFlowTasks.has_edge-Tuple{DataFlowTasks.DAG, Any, Any}","page":"References","title":"DataFlowTasks.has_edge","text":"has_edge(dag,i,j)\n\nCheck if there is an edge connecting i to j.\n\n\n\n\n\n","category":"method"},{"location":"references/#DataFlowTasks.inneighbors-Tuple{DataFlowTasks.DAG, Any}","page":"References","title":"DataFlowTasks.inneighbors","text":"inneighbors(dag,i)\n\nList of predecessors of i in dag.\n\n\n\n\n\n","category":"method"},{"location":"references/#DataFlowTasks.isconnected-Tuple{DataFlowTasks.DAG, Any, Any}","page":"References","title":"DataFlowTasks.isconnected","text":"isconnected(dag,i,j)\n\nCheck if there is path in dag connecting i to j.\n\n\n\n\n\n","category":"method"},{"location":"references/#DataFlowTasks.memory_overlap-Tuple{Any, Any}","page":"References","title":"DataFlowTasks.memory_overlap","text":"memory_overlap(di,dj)\n\nDetermine if data di and dj have overlapping memory in the sense that mutating di can change dj (or vice versa). This function is used to build the dependency graph between DataFlowTasks.\n\nA generic version is implemented returning true (but printing a warning). Users should overload this function for the specific data types used in the arguments to allow for appropriate inference of data dependencies.\n\n\n\n\n\n","category":"method"},{"location":"references/#DataFlowTasks.memory_overlap-Tuple{Array, Array}","page":"References","title":"DataFlowTasks.memory_overlap","text":"memory_overlap(di::Array,dj::Array)\nmemory_overlap(di::SubArray,dj::Array)\nmemory_overlap(di::Array,dj::SubArray)\n\nWhen both di and dj are of type Array, compare their addresses. If one is of type SubArray, compare the parent.\n\n\n\n\n\n","category":"method"},{"location":"references/#DataFlowTasks.memory_overlap-Tuple{SubArray, SubArray}","page":"References","title":"DataFlowTasks.memory_overlap","text":"memory_overlap(di::SubArray,dj::SubArray)\n\nFirst compare their parents. If they are the same, compare the indices in the case where the SubArrays have the  same dimension.\n\n\n\n\n\n","category":"method"},{"location":"references/#DataFlowTasks.num_edges-Tuple{DataFlowTasks.DAG}","page":"References","title":"DataFlowTasks.num_edges","text":"num_edges(dag::DAG)\n\nNumber of edges in the DAG.\n\n\n\n\n\n","category":"method"},{"location":"references/#DataFlowTasks.num_nodes-Tuple{DataFlowTasks.DAG}","page":"References","title":"DataFlowTasks.num_nodes","text":"num_nodes(dag::DAG)\n\nNumber of nodes in the DAG.\n\n\n\n\n\n","category":"method"},{"location":"references/#DataFlowTasks.outneighbors-Tuple{DataFlowTasks.DAG, Any}","page":"References","title":"DataFlowTasks.outneighbors","text":"outneighbors(dag,i)\n\nList of successors of j in dag.\n\n\n\n\n\n","category":"method"},{"location":"references/#DataFlowTasks.priority-Tuple{DataFlowTasks.DataFlowTask}","page":"References","title":"DataFlowTasks.priority","text":"priority(t::DataFlowTask)\n\nFunction called to determine the scheduled priority of t. The default imlementation simply retuns t.priority.\n\n\n\n\n\n","category":"method"},{"location":"references/#DataFlowTasks.remove_node!-Tuple{DataFlowTasks.DAG, Any}","page":"References","title":"DataFlowTasks.remove_node!","text":"remove_node!(dag::DAG,i)\n\nRemove node i and all of its edges from dag.\n\n\n\n\n\n","category":"method"},{"location":"references/#DataFlowTasks.setscheduler!-Tuple{Any}","page":"References","title":"DataFlowTasks.setscheduler!","text":"setscheduler!(r)\n\nSet the active scheduler to r.\n\n\n\n\n\n","category":"method"},{"location":"references/#DataFlowTasks.start_dag_worker","page":"References","title":"DataFlowTasks.start_dag_worker","text":"start_dag_worker(sch)\n\nStart a forever-running task associated with sch which takes nodes from finished and removes them from the dag. The task blocks if finished is empty.\n\n\n\n\n\n","category":"function"},{"location":"references/#DataFlowTasks.sync","page":"References","title":"DataFlowTasks.sync","text":"sync([sch::TaskGraphScheduler])\n\nWait for all nodes in sch to be finished before continuining. If called with no arguments, use  the current scheduler.\n\n\n\n\n\n","category":"function"},{"location":"references/#DataFlowTasks.update_edges!-Tuple{DataFlowTasks.DAG, Any}","page":"References","title":"DataFlowTasks.update_edges!","text":"update_edges!(dag::DAG,i)\n\nPerform the data-flow analysis to update the edges of node i. Both incoming and outgoing edges are updated.\n\n\n\n\n\n","category":"method"},{"location":"references/#DataFlowTasks.with_scheduler-Tuple{Any, Any}","page":"References","title":"DataFlowTasks.with_scheduler","text":"with_scheduler(f,sch)\n\nRun f, but push DataFlowTasks to the scheduler dag in sch instead of the default dag.\n\n\n\n\n\n","category":"method"},{"location":"references/#DataFlowTasks.@dasync","page":"References","title":"DataFlowTasks.@dasync","text":"macro dasync(expr,data,mode)\n\nLike @dspawn, but schedules the task to run on the current thread.\n\n\n\n\n\n","category":"macro"},{"location":"references/#DataFlowTasks.@dspawn","page":"References","title":"DataFlowTasks.@dspawn","text":"macro dspawn expr data mode\n\nCreate a DataFlowTask and schedule it to run on any available thread. The data and mode arguments are passed to the DataFlowTask constructor, and can be used to indicate how the code in expr accesses data. These fields are used to automatically infer task dependencies.\n\nExamples:\n\nusing DataFlowTasks\nusing DataFlowTasks: R,W,RW\n\nA = rand(5)\n\n# create a task which writes to A\nt1 = @dspawn begin\n    sleep(1)\n    fill!(A,0)\n    println(\"finished writing\")\nend (A,) (W,)\n\n# create a task which reads from A\nt2 = @dspawn begin\n    println(\"I automatically wait for `t1` to finish\")\n    sum(A)\nend (A,) (R,)\n\nfetch(t2) # 0\n\n# output\n\nfinished writing\nI automatically wait for `t1` to finish\n0.0\n\nNote that in the example above t2 waited for t1 because it read a data field that t1 accessed in a writtable manner.\n\n\n\n\n\n","category":"macro"},{"location":"references/#DataFlowTasks.@dtask","page":"References","title":"DataFlowTasks.@dtask","text":"macro dtask(expr,data,mode)\n\nCreate a DataFlowTask to execute expr, where mode::NTuple{N,AccessMode} species how data::Tuple{N,<:Any} is accessed in expr. Note that the task is not automatically scheduled for execution.\n\nSee also: @dspawn, @dasync\n\n\n\n\n\n","category":"macro"},{"location":"references/#DataFlowTasks.TiledFactorization","page":"References","title":"DataFlowTasks.TiledFactorization","text":"module TiledFactorization\n\nTiled algorithms for factoring dense matrices.\n\n\n\n\n\n","category":"module"},{"location":"references/#DataFlowTasks.TiledFactorization.PseudoTiledMatrix","page":"References","title":"DataFlowTasks.TiledFactorization.PseudoTiledMatrix","text":"PseudoTiledMatrix(data::Matrix,sz::Int)\n\nWrap a Matrix in a tiled structure of size sz, where getindex(A,i,j) returns a view of the (i,j) block (of size (sz × sz)). No copy of data is made, but the elements in a block are not continguos in memory. If sz is not a divisor of the matrix size, one last row/column block will be included of size given by the remainder fo the division.\n\n\n\n\n\n","category":"type"},{"location":"examples/#examples-section","page":"Examples","title":"Examples","text":"","category":"section"},{"location":"examples/","page":"Examples","title":"Examples","text":"TODO: ","category":"page"},{"location":"examples/","page":"Examples","title":"Examples","text":"add a description of the examples and more hardware info\nmention the effects of tilesize ahd capacity on the results of tiled factorization\ncompare 'fork-join' approach to HLU to dataflow approach","category":"page"},{"location":"examples/#tiledcholesky-section","page":"Examples","title":"Tiled Cholesky factorization","text":"","category":"section"},{"location":"examples/#Computer-1","page":"Examples","title":"Computer 1","text":"","category":"section"},{"location":"examples/","page":"Examples","title":"Examples","text":"(Image: Cholesky 8 cores)","category":"page"},{"location":"examples/#Computer-2","page":"Examples","title":"Computer 2","text":"","category":"section"},{"location":"examples/","page":"Examples","title":"Examples","text":"(Image: Cholesky 20 cores)","category":"page"},{"location":"examples/#tiledlu-section","page":"Examples","title":"Tiled LU factorization","text":"","category":"section"},{"location":"examples/","page":"Examples","title":"Examples","text":"tip: Tip\nSee this page for a discussion on thread-based parallelization of LU factorization.","category":"page"},{"location":"examples/#[Hierarchical-LU-factorization]","page":"Examples","title":"[Hierarchical LU factorization]","text":"","category":"section"},{"location":"","page":"Getting started","title":"Getting started","text":"CurrentModule = DataFlowTasks","category":"page"},{"location":"#DataFlowTasks","page":"Getting started","title":"DataFlowTasks","text":"","category":"section"},{"location":"","page":"Getting started","title":"Getting started","text":"Tasks which automatically respect data-flow dependencies","category":"page"},{"location":"#Basic-usage","page":"Getting started","title":"Basic usage","text":"","category":"section"},{"location":"","page":"Getting started","title":"Getting started","text":"This package defines a DataFlowTask type which behaves very much like a Julia Task, except that it allows the user to specify explicit data dependencies. This information is then be used to automatically infer task dependencies by constructing and analyzing a directed acyclic graph based on how tasks access the underlying data. The premise is that it is sometimes simpler to specify how tasks depend on data than to specify how tasks depend on each other.","category":"page"},{"location":"","page":"Getting started","title":"Getting started","text":"important: Similarities and differences with `Dagger.jl`\nTODO","category":"page"},{"location":"","page":"Getting started","title":"Getting started","text":"The use of a DataFlowTask is intended to be as similar to a native Task as possible. The API revolves around three macros:","category":"page"},{"location":"","page":"Getting started","title":"Getting started","text":"@dtask\n@dspawn\n@dasync","category":"page"},{"location":"","page":"Getting started","title":"Getting started","text":"They behave like their Base counterparts (@task, Threads.@spawn and @async), but two additional arguments specifying explicit data dependencies are required. The example below shows the most basic usage:","category":"page"},{"location":"","page":"Getting started","title":"Getting started","text":"using DataFlowTasks # hide\nusing DataFlowTasks: R,W,RW\n\nA = ones(5)\nB = ones(5)\nd = @dspawn begin\n    A .= A .+ B\nend (A,B) (RW,R)\n\nfetch(d)","category":"page"},{"location":"","page":"Getting started","title":"Getting started","text":"This creates (and schedules for execution) a DataFlowTask d which access A in READWRITE mode, and B in READ mode. The benefit of DataFlowTasks comes when you start to compose operations which may mutate the same data:","category":"page"},{"location":"","page":"Getting started","title":"Getting started","text":"using DataFlowTasks # hide\nusing DataFlowTasks: R,W,RW\n\nn = 100_000\nA = ones(n)\n\nd1 = @dspawn begin\n    # in-place work on A\n    for i in eachindex(A)\n        A[i] = log(A[i]) # A[i] = 0\n    end\nend (A,) (RW,)\n\nd2 = @dspawn begin\n    # reduce A\n    sum(A)\nend (A,) (R,)\n\nc = fetch(d2) # 0","category":"page"},{"location":"","page":"Getting started","title":"Getting started","text":"We now have two asynchronous tasks being created, both of which access the array A. Because d1 writes to A, and d2 reads from it, the outcome C is nondeterministic unless we specify an order of precedence. DataFlowTasks reinforces the sequential consistency criterion, which is to say that executing tasks in parallel must preserve, up to rounding errors, the result that would have been obtained if they were executed sequentially (i.e. d1 is executed before d2, d2 before d3, and so on). In this example, this means d2 will always wait on d1 because of an inferred data dependency. The outcome is thus always zero.","category":"page"},{"location":"","page":"Getting started","title":"Getting started","text":"note: Note\nIf you replace @dspawn by Threads.@spawn in the example above (and pick an n large enough) you will see that you no longer get 0 because d2 may access an element of A before it has been replaced by zero!","category":"page"},{"location":"","page":"Getting started","title":"Getting started","text":"No parallelism was allowed in the previous example due to a data conflict. To see that when parallelism is possible, spawning DataFlowTasks will exploit it, consider this one last example:","category":"page"},{"location":"","page":"Getting started","title":"Getting started","text":"using DataFlowTasks # hide\nusing DataFlowTasks: R,W,RW\n\nn = 100\nA = ones(n)\n\nd1 = @dspawn begin\n    # write to A\n    sleep(1)\n    fill!(A,0)\nend (A,) (W,)\n\nd2 = @dspawn begin\n    # some long computation \n    sleep(5)\n    # reduce A\n    sum(A)\nend (A,) (R,)\n\nd3 = @dspawn begin\n    # another reduction on A\n    sum(x->sin(x),A)\nend (A,) (R,)\n\nt = @elapsed c = fetch(d3)\n\nt,c ","category":"page"},{"location":"","page":"Getting started","title":"Getting started","text":"We see that the elapsed time to fetch the result from d3 is on the order of one second. This is expected since d3 needs to wait on d1 but can be executed concurrently with d2. The result is, as expected, 0.","category":"page"},{"location":"","page":"Getting started","title":"Getting started","text":"All examples this far have been simple enough that the dependencies between the tasks could have been inserted by hand. There are certain problems, however, where the constant reuse of memory (mostly for performance reasons) makes a data-flow approach to parallelism a rather natural way to implicitly describe task dependencies. This is the case, for instance, of tiled (also called blocked) matrix factorization algorithms, where task dependencies can become rather difficult to describe in an explicit manner. The tiled factorization section showcases some non-trivial problems for which DataFlowTasks may be useful.","category":"page"},{"location":"","page":"Getting started","title":"Getting started","text":"tip: Tip\nThe main goal of DataFlowTasks is to expose parallelism: two tasks ti and tj can be executed concurrently if one does not write to memory that the other reads. This data-dependency check is done dynamically, and therefore is not limited to tasks in the same lexical scope. Of course, there is an overhead associated with these checks, so whether performance gains can be obtained depend largely on how parallel the algorithm is, as well as how long each individual task takes (compared to the overhead).","category":"page"},{"location":"#Custom-types","page":"Getting started","title":"Custom types","text":"","category":"section"},{"location":"","page":"Getting started","title":"Getting started","text":"In order to infer dependencies between DataFlowTasks, we must be able to determine whether two objects A and B share a common memory space. That is to say, we must know if mutating A can affect B, or vice-versa. Obviously, without any further information on the types of A and B, this is an impossible question.","category":"page"},{"location":"","page":"Getting started","title":"Getting started","text":"To get around this challenge, you must import and extend the memory_overlap method to work on any pair of elements A and B that you wish to use. The examples in the previous section worked because these methods have been defined for some basic AbstractArrays:","category":"page"},{"location":"","page":"Getting started","title":"Getting started","text":"using DataFlowTasks: memory_overlap\n\nA = rand(10,10)\nB = view(A,1:10)\nC = view(A,11:20)\n\nmemory_overlap(A,B),memory_overlap(A,C),memory_overlap(B,C)","category":"page"},{"location":"","page":"Getting started","title":"Getting started","text":"By default, memory_overlap will return true and print a warning if it does not find a specialized method:","category":"page"},{"location":"","page":"Getting started","title":"Getting started","text":"using DataFlowTasks: memory_overlap\n\nstruct CirculantMatrix\n    data::Vector{Float64}\nend\n\nv = rand(10);\nM = CirculantMatrix(v);\n\nmemory_overlap(M,copy(v))","category":"page"},{"location":"","page":"Getting started","title":"Getting started","text":"Extending the memory_overlap will remove the warning, and produce a more meaningful result:","category":"page"},{"location":"","page":"Getting started","title":"Getting started","text":"import DataFlowTasks: memory_overlap\n\n# overload the method\nmemory_overlap(M::CirculantMatrix,v) = memory_overlap(M.data,v)\nmemory_overlap(v,M::CirculantMatrix) = memory_overlap(M,v)\n\nmemory_overlap(M,v), memory_overlap(M,copy(v))","category":"page"},{"location":"","page":"Getting started","title":"Getting started","text":"You can now spawn tasks with your custom type CirculantMatrix as a data dependency, and things should work as expected:","category":"page"},{"location":"","page":"Getting started","title":"Getting started","text":"using DataFlowTasks\nusing DataFlowTasks: R,W,RW\n\nv = rand(5);\nM1 = CirculantMatrix(v);\nM2 = CirculantMatrix(copy(v));\n\nBase.sum(M::CirculantMatrix) = length(M.data)*sum(M.data)\n\nd1 = @dspawn begin\n    sleep(0.5)\n    println(\"I write to v\")\n    fill!(v,0) \nend (v,) (W,);\n\nd2 = @dspawn begin\n    println(\"I wait for d1 to write\")\n    sum(M1)\nend (M1,) (R,);\n\nd3= @dspawn begin\n    println(\"I don't wait for d1 to write\")\n    sum(M2)\nend (M2,) (R,);\n\nfetch(d2)\n\nfetch(d3)","category":"page"},{"location":"#Scheduler","page":"Getting started","title":"Scheduler","text":"","category":"section"},{"location":"","page":"Getting started","title":"Getting started","text":"When loaded, the DataFlowTasks package will initialize an internal scheduler (of type JuliaScheduler), running on the background, to handle implicit dependencies of the spawned DataFlowTasks. In order to retrieve the current scheduler, you may use the getscheduler method:","category":"page"},{"location":"","page":"Getting started","title":"Getting started","text":"using DataFlowTasks # hide\nDataFlowTasks.sync() # hide\nsch = DataFlowTasks.getscheduler()","category":"page"},{"location":"","page":"Getting started","title":"Getting started","text":"The default scheduler can be changed through setscheduler!.","category":"page"},{"location":"","page":"Getting started","title":"Getting started","text":"There are two important things to know about the default JuliaScheduler type. First, it contains a buffered dag that can handle up to sz_max nodes: trying to spawn a task when the dag is full will block. This is done to keep the cost of analyzing the data dependencies under control, and it means that a full/static dag may in practice never be constructed. You can modify the buffer size as follows:","category":"page"},{"location":"","page":"Getting started","title":"Getting started","text":"resize!(sch.dag,50)","category":"page"},{"location":"","page":"Getting started","title":"Getting started","text":"Second, when the computation of a DataFlowTask ti is completed, it gets pushed into a finished channel, to be eventually processed and poped from the dag by the dag_worker. This is done to avoid concurrent access to the dag: only the dag_worker should modify it. If you want to stop nodes from being removed from the dag, you may stop the dag_worker using:","category":"page"},{"location":"","page":"Getting started","title":"Getting started","text":"DataFlowTasks.stop_dag_worker(sch)","category":"page"},{"location":"","page":"Getting started","title":"Getting started","text":"Finished nodes will now remain in the dag:","category":"page"},{"location":"","page":"Getting started","title":"Getting started","text":"using DataFlowTasks: R,W,RW, num_nodes\nA = ones(5)\n@dspawn begin \n    A .= 2 .* A\nend (A,) (RW,)\n@dspawn sum(A) (A,) (R,)\nsch","category":"page"},{"location":"","page":"Getting started","title":"Getting started","text":"Note that stopping the dag_worker means finished nodes are no longer removed from the dag; since the dag is a buffered structure, this may cause the execution to halt if the dag is at full capacity. You can then either resize! it, or simply star the worker (which will result in the processing of the finished channel):","category":"page"},{"location":"","page":"Getting started","title":"Getting started","text":"DataFlowTasks.start_dag_worker(sch)\nsch","category":"page"},{"location":"","page":"Getting started","title":"Getting started","text":"tip: Tip\nThere are situations where you may want to change the default scheduler temporarily to execute a block of code, and revert to the default scheduler after. This can be done using the with_scheduler method. ","category":"page"},{"location":"#Logging","page":"Getting started","title":"Logging","text":"","category":"section"},{"location":"","page":"Getting started","title":"Getting started","text":"TODO","category":"page"},{"location":"#Limitations","page":"Getting started","title":"Limitations","text":"","category":"section"},{"location":"","page":"Getting started","title":"Getting started","text":"Some current limitations are listed below:","category":"page"},{"location":"","page":"Getting started","title":"Getting started","text":"At present, errors are rather poorly handled. The only way to know if a task has failed is to manually inspect the dag\nThere is no way to specify priorities for a task.\nThe main thread executes tasks, and is responsible for adding/removing nodes from the dag. This may hinder parallelism if the main thread is given a long task since the processing of the dag will halt until the main thread becomes free again.\n...","category":"page"}]
}
