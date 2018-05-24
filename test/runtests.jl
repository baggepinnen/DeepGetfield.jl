using DeepGetfield, MacroTools
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

ops = findfield(a, :yy)
@test @capture(ops[1], x->getfield(x, arg_))
@test @capture(ops[2], x->getfield(x, arg_))

ops_b = DeepGetfield.tobroadcast(ops)
@test @capture(ops_b[1], x->getfield(x, arg_))
@test @capture(ops_b[2], x->getfield(x, arg_))

fun = getter(a, :yy)
@test fun(a) isa Vector{C}



ops = findfield(a, :zz)
@test @capture(ops[3], x->getindex(x, 1))
@test @capture(ops[4], x->getfield(x, arg_))

ops_b = DeepGetfield.tobroadcast(ops)
@test length(ops_b) == length(ops) - 1 == 3
@test @capture(ops_b[1], x->getfield(x, arg_))
@test @capture(ops_b[2], x->getfield(x, arg_))
@test @capture(ops_b[3], x->getfield.(x, arg_))

@test getter(a, :zz)(a) == [1,2] == a.z.yy |> x -> getfield.(x,:zz)

@deep(a.yy) == fun(a)
@deep(a.zz) == [1,2]



ops = [:(x-> getindex(x,1))]
b = [1,2]
@test DeepGetfield.follow(b,ops) == 1

f = eval(ops[1])
@test Base.invokelatest(f,b) == 1


x = [1, 2]
y = [x, x, x]
z = [y, y, y, y]

@test DeepGetfield.calcdims(x) == [length(x)]
@test DeepGetfield.calcdims(y) == [length(y), length(x)]
@test DeepGetfield.calcdims(z) == [length(z), length(y), length(x)]
@test denest(x) == x
@test denest(y) == [x x x]
@test denest(z) == cat(3, denest(y), denest(y), denest(y), denest(y))
