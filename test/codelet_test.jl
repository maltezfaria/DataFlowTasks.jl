using SafeTestsets

@safetestset "Codelet" begin
    using LinearAlgebra
    using HScheduler
    R,W,RW  = HScheduler.READ, HScheduler.WRITE, HScheduler.READWRITE
    @testset "GenericCodelet" begin
        using HScheduler: getdata_read, getdata_write, cpu_func, execute
        m,n  = 100,100
        A    = rand(n,m)
        b    = 2
        codelet = GenericCodelet(cpu_func=LinearAlgebra.rmul!,data=[A,b],access_modes=[RW,R])
        @test getdata_read(codelet) == [A,b]
        @test getdata_write(codelet) == [A]
        @test cpu_func(codelet) == LinearAlgebra.rmul!
        tmp  = A*b
        @test A !== tmp
        execute(codelet)
        @test A == tmp
    end
    @testset "Codelet" begin
        using HScheduler: getdata_read, getdata_write, cpu_func, execute
        m,n  = 100,100
        A    = rand(n,m)
        b    = 2
        codelet = Codelet(cpu_func=rmul!,data=[A,2*b],access_modes=[RW,R])
        @test getdata_read(codelet) == [A,2*b]
        @test getdata_write(codelet) == [A]
        @test cpu_func(codelet) == LinearAlgebra.rmul!
        tmp  = A*2*b
        @test A !== tmp
        execute(codelet)
        @test A == tmp
    end
    @testset "Dependency" begin
        using HScheduler: getdata_read, getdata_write, cpu_func, execute, dependency_type
        m,n  = 100,100
        A    = rand(n,m)
        a    = -π
        b    = 2
        codelet1 = GenericCodelet(cpu_func=rmul!,data=[A,b],access_modes=[RW,R])
        codelet2 = Codelet(cpu_func=rmul!,data=[A,a],access_modes=[RW,R])
        codelet3 = Codelet(cpu_func=rmul!,data=[rand(m,n),a],access_modes=[RW,R])
        @test dependency_type(codelet1,codelet2) == HScheduler.Sequential
        @test dependency_type(codelet1,codelet3) == HScheduler.Independent
    end
    @testset "Taskification" begin
        using HScheduler: getdata_read, getdata_write, cpu_func, execute, dependency_type
        task     = Task(()->())
        codelet1 = Codelet(cpu_func=+,data=(1,1),access_modes=(R,R))
        sch      = Task(codelet1,[task])#task should block sch from running

    end
end
