using FieldGetter
@static if VERSION < v"0.7.0-DEV.2005"
    using Base.Test
else
    using Test
end

struct A
    x::Int
    y
    z
end

struct B
    xx
    yy
end

struct C
    zz
end

a = A(2, 1., B(10.,[C(1),C(2)]))
fun = getter(a, :yy)
@test fun(a) isa Vector{C}
@test getter(a, :zz)(a) == [1,2] == a.z.yy |> x -> getfield.(x,:zz)



ops = [:(x-> getindex(x,1))]
b = [1,2]
@test follow(b,ops) == 1

f = eval(ops[1])
@test Base.invokelatest(f,b) == 1
