# modified from from RecursiveFactoriation
# https://github.com/YingboMa/RecursiveFactorization.jl (MIT License)
function schur_complement!(𝐂, 𝐀, 𝐁,::Val{THREAD}=Val(false)) where {THREAD}
    # mul!(𝐂,𝐀,𝐁,-1,1)
    if THREAD
        @tturbo warn_check_args=false for m ∈ 1:size(𝐀,1), n ∈ 1:size(𝐁,2)
            𝐂ₘₙ = zero(eltype(𝐂))
            for k ∈ 1:size(𝐀,2)
                𝐂ₘₙ -= 𝐀[m,k] * 𝐁[k,n]
            end
            𝐂[m,n] = 𝐂ₘₙ + 𝐂[m,n]
        end
    else
        @turbo warn_check_args=false for m ∈ 1:size(𝐀,1), n ∈ 1:size(𝐁,2)
            𝐂ₘₙ = zero(eltype(𝐂))
            for k ∈ 1:size(𝐀,2)
                𝐂ₘₙ -= 𝐀[m,k] * 𝐁[k,n]
            end
            𝐂[m,n] = 𝐂ₘₙ + 𝐂[m,n]
        end
    end
end
