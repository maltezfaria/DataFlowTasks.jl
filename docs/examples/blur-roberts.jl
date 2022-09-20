using DataFlowTasks
import DataFlowTasks as DFT
using GraphViz, GLMakie

tilerange(ti, ts) = (ti-1)*ts+1:ti*ts
function checkranges(ri, rj, n)
    first(ri) == 1 && (ri = ri[2:end])
    last(ri)  == n && (ri = ri[1:end-1])
    first(rj) == 1 && (rj = rj[2:end])
    last(rj)  == n && (rj = rj[1:end-1])
    ri,rj
end


# Update tile v₂, given by the ranges of indices (ri,rj), depending on v₁
function blur_tilestep!(v₂, v₁, ri, rj)
    for i ∈ ri, j ∈ rj
        v₂[i,j] = 1/9 * (
            v₁[i-1,j-1] + v₁[i,j-1] + v₁[i-1,j] +
            v₁[i+1,j+1] + v₁[i+1,j] + v₁[i,j+1] +
            v₁[i,j] + v₁[i+1,j-1] + v₁[i-1,j+1]
        )
    end
end
# Update tile v₂, given by the ranges of indices (ri,rj), depending on v₁
function robert_tilestep!(v₂, v₁, ri, rj)
    for i ∈ ri, j ∈ rj
        v₂[i,j] = v₁[i,j] - v₁[i-1,j+1] + v₁[i,j+1] - v₁[i-1,j]
    end
end


# Blur step for the whole matrix
function blurstep!(v₂, v₁, tn, ts)
    for ti ∈ 1:tn, tj ∈ 1:tn
        (ri,rj) = checkranges(tilerange.([ti tj], ts)..., tn*ts)
        @dspawn begin
            @R view(v₁, ri[1]-1, rj[1]-1:ri[end]+1)    # North
            @R view(v₁, ri[end]+1, rj[1]-1:ri[end]+1)  # South
            @R view(v₁, ri, rj[1]-1)                   # West
            @R view(v₁, ri, rj[end]+1)                 # East
            @R view(v₁, ri, rj)                        # Center
            @W view(v₂,ri,rj)
            blur_tilestep!(v₂, v₁, ri, rj)
        end label="blur ($ti,$tj)"
    end
end
# Robert step for the whole matrix
function robertstep!(v₂, v₁, tn, ts)
    for ti ∈ 1:tn, tj ∈ 1:tn
        (ri,rj) = checkranges(tilerange.([ti tj], ts)..., tn*ts)
        @dspawn begin
            @R view(v₁, ri[1]-1, rj[1]-1:ri[end]+1)    # North
            @R view(v₁, ri, rj[end]+1)                 # East
            @R view(v₁, ri, rj)                        # Center
            @W view(v₂, ri, rj)
            robert_tilestep!(v₂, v₁, ri, rj)
        end label="robert ($ti,$tj)"
    end
end


# Apply the Blur-Robert method to a matrix v₁
function blurrobert(v₁, ts)
    n = size(v₁)[1]
    n%ts != 0 && error("tilesize doesn't fit the size")
    tn = round(Int, n/ts)
    v₂ = similar(v₁)

    blurstep!(v₂, v₁, tn, ts)
    robertstep!(v₁, v₂, tn, ts)

    DFT.sync()
end


# Parameters
n = 4094
ts = 512

# Initialization matrix and halo
v = rand(n+2,n+2)
v[1,:] .= 0 ; v[n+2,:] .= 0  # Halo
v[:,1] .= 0 ; v[:,n+2] .= 0  #

# DataFlowTasks environnement
DFT.enable_log()

# Compilation
blurrobert(copy(v), ts)
DFT.resetlogger!()
GC.gc()

# Call
blurrobert(v, ts)

# Profile
DFT.plot_traces(categories=["blur", "robert"])
# DFT.plot_dag()
