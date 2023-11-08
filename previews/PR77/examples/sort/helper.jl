function display_split(v, i₁, i₂, j₁, j₂)
    I = last(i₂)
    M = maximum(v)
    pivot = v[last(i₁)]
    (left₁, left₂) = (i₁, i₂)
    (right₁, right₂) = (j₁ .+ I, j₂ .+ I)
    blocks = (left₁, left₂, right₁, right₂)
    colors = map(eachindex(v)) do i
        findfirst(∋(i), blocks)
    end

    center(r) = (r[1]+r[end]) / 2

    fig, ax, _ = barplot(v, color=colors, colormap=:Paired_4, colorrange=(1,4));

    vertical(x, h) = lines!(ax, [x, x], [-2, h], linestyle=:dash, color=:black)
    vertical(last(left₁)  + 0.5, pivot+10)
    vertical(last(right₁) + 0.5, pivot+10)
    vertical(last(left₂)  + 0.5, M+1)

    lines!(ax, [0, lastindex(v)+1], [pivot, pivot], linestyle=:dash, color=:black)

    text!(ax, (0, pivot), text="pivot", align=(:left, :bottom))
    text!(ax, (center(left₁),  -1), text="i₁ = $i₁", align=(:center, :top))
    text!(ax, (center(left₂),  -1), text="i₂ = $i₂", align=(:center, :top))
    text!(ax, (center(right₁), -1), text="j₁ = $j₁", align=(:center, :top))
    text!(ax, (center(right₂), -1), text="j₂ = $j₂", align=(:center, :top))
    text!(ax, (center(left₁  ∪ left₂),  M), text="left",  align=(:center, :top), fontsize=24)
    text!(ax, (center(right₁ ∪ right₂), M), text="right", align=(:center, :top), fontsize=24)
    fig
end
