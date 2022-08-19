# K-means clustering algorithm

using DataFlowTasks
using LinearAlgebra
using GraphViz, GLMakie

import DataFlowTasks as DFT

# Assign every point to a cluster
function assignement!(clusters, centroids, points, tn, ts)
    # For every tile index
    for ti ∈ 1:tn
        # First/Last element indices
        fi = (ti-1)*ts + 1  ;  li = ti*ts
        
        # To segment work in different tasks
        tiled_clusters = @view(clusters[fi:li])
        tiled_points   = @view(points[fi:li])
        @dspawn tile_assignement!(@RW(tiled_clusters), @R(tiled_points), @R(centroids)) label="tile assignement"
    end
end

# For each element of tile :
# - compute distance to all centroids
# - corresponding cluster element takes the closest centroid
function tile_assignement!(clusters, tile, centroids)
    # For every indices in tile, assign the closest cluster
    for i ∈ eachindex(tile)
        clusters[i] = closestcluster(i, centroids, tile)
    end
end

# Finds the closest centroid from coords
function closestcluster(i, centroids, tile)
    min = Inf
    cluster = 0
    for k ∈ eachindex(centroids)
        # Distance computation
        dx = tile[i][1] - centroids[k][1]
        dy = tile[i][2] - centroids[k][2]
        d = sqrt(dx^2 + dy^2)

        # Comparaison
        if d < min
            min = d
            cluster = k
        end
    end
    cluster
end

function barycenter(cluster_pts, cluster_idx)
    cx = 0  ;  cy = 0 
    for cluster_pt ∈ cluster_pts
        cluster_pt == false && continue
        cx += cluster_pt[1]
        cy += cluster_pt[2]
    end
    l = length(cluster_idx)
    cx/l,cy/l
end

# Update centroids
function centroidsupdate!(centroids, points, clusters)
    for k ∈ eachindex(centroids)
        # All indices corresponding to element in the cluster k
        k_cluster_idx = findall(c->c==k,clusters)

        # All points in cluster k
        k_cluster_pts = [i ∈ k_cluster_idx && points[i] for i ∈ eachindex(points)]

        # K centroid is the barycenter of all these points
        @dspawn begin
            @W centroids[k]
            centroids[k] = barycenter(k_cluster_pts, k_cluster_idx)
        end label="barycenter"
    end
end

function main()
    # Parameters
    n = 2048          # Nb of points
    K = 2           # Nb of clusters
    niter = 100     # Nb of iteration
    np = Threads.nthreads() # Number of threads
    points    = [(100*rand(), 100*rand()) for _ ∈ 1:n]
    # points = [(1, 1), (2,2), (3,3), (4,4), (100,100), (99,99), (98,98), (97,97)]  # To Test
    centroids = [(100*rand(), 100*rand()) for _ ∈ 1:K]
    clusters = zeros(n)
    ts = 512  # Tilesize
    tn = round(Int, n/ts)  # Number of tiles

    DFT.resetlogger!()
    for _ ∈ 1:niter
        assignement!(clusters, centroids, points, tn, ts)
        centroidsupdate!(centroids, points, clusters)
    end
    DFT.sync()

    DFT.plot(categories=["tile assignement", "barycenter"])
end
main()