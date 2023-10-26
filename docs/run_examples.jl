using Test

@testset "Examples" verbose=true begin
    scripts = [(joinpath(@__DIR__, "src", "readme"), "README.jl")]

    examples_root = joinpath(@__DIR__, "src", "examples")
    for name in readdir(examples_root)
        dir = joinpath(examples_root, name)
        script = "$name.jl"
        ispath(joinpath(dir, script)) && push!(scripts, (dir, script))
    end

    for (dir, script) in scripts
        @testset "$script" begin
            @test begin
                cd(dir) do
                    include(joinpath(dir, script))
                    true
                end
            end
        end
    end
end
