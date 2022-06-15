
struct FirstType end
struct SecondType end

f(::Type{FirstType}) = 1+1
f(::Type{SecondType}) = 2+2


f(FirstType)


