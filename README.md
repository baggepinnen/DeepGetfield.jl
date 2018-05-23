# DeepGetfield

[![Build Status](https://travis-ci.org/baggepinnen/DeepGetfield.jl.svg?branch=master)](https://travis-ci.org/baggepinnen/DeepGetfield.jl)

[![Coverage Status](https://coveralls.io/repos/baggepinnen/DeepGetfield.jl/badge.svg?branch=master&service=github)](https://coveralls.io/github/baggepinnen/DeepGetfield.jl?branch=master)

[![codecov.io](http://codecov.io/github/baggepinnen/DeepGetfield.jl/coverage.svg?branch=master)](http://codecov.io/github/baggepinnen/DeepGetfield.jl?branch=master)


This package provides the macro `f = @deepf data.field` where `data::CompositeType, field::Symbol`. `f` is a function that acts as a deep version of getfield: `f(data) -> deep_getfield(data, fieldname)`.

`data` might be a complex composite type with fields which are themselves composite types or arrays. `@deepf` searches the structure `data` depth first for the first occurrence of a field with name `field` and returns a function that gets that field. An illustration is provided below, where `data` is a complicated type, and the user wants a function that returns the field `zz` deep inside `data`. If you want the data immediately instead of a getter function, use the macro `@deep data.field`.

## Motivation
I frequently run many experiments in parallel using `pmap` etc. and results may be a custom type stored in a custom type, tuple, array etc.. To analyze the results I need to access a particular field deep inside the result structure and figuring out how to find it is often a hassle. This package does the searching for you and returns a function which gets the requested field (or the field directly).

## Installation
`Pkg.clone("https://github.com/baggepinnen/DeepGetfield.jl")`


# Example
Define some types for testing
```julia
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

```

```julia
julia> a   = A(2, 1., B(10.,[C(1),C(2)])) # Create complex composite type

julia> dump(a) # Vizualize the structure and contents of a
A
  x: Int64 2
  y: Float64 1.0
  z: B
    xx: Float64 10.0
    yy: Array{C}((2,))
      1: C
        zz: Int64 1
      2: C
        zz: Int64 2

julia> getterfun = @deepf a.yy # This function acts as deep_getfield(a,:yy)

julia> getterfun(a) # Get field yy, equivalent to a.z.yy
2-element Array{C,1}:
 C(1)
 C(2)

julia>  @deep a.yy # Evaluate immediately without getting a function
2-element Array{C,1}:
 C(1)
 C(2)

julia> getterfun = @deepf a.zz # Getter for field zz, equivalent to getfield.(a.z.yy, :zz)

julia> getterfun(a) == [1,2] == getfield.(a.z.yy, :zz)
true
```

Notice how in the first case, we got a `Vector{C}` whereas in the second case we got a `Vector{Int}`.

If one were to manually write the function to extract field `zz` from `a`, it would look something like this
```julia
getfield.(a.z.yy, :zz)
```
With this package one can get the same function through
```julia
get_zz = @deepf a.zz
```

# Functions
- `@deepf data.field` Searches through the structure `data` and returns a function `data -> $field` where `field` is somewhere deep inside `data`.
Arrays are broadcasted over, but the search only looks at the first element.
- `@deep` Equivalent to `@deepf(data.field)(data)`, i.e., return the field immediately instead of a getter function.
- `getter(d::CompositeType, fieldname::Symbol, [max_depth = 8])::Function d-> $fieldname` Function interface to `@deepf`
- `denest(x::Array{Array...})` flattens the structure of `x` from an array of arrays to a tensor. Can handle deep nestings.

## Internals
```julia
ops   = _getter(a, :zz)  # Get a vector of operations
ops_b = _getter(ops)     # Modify operations to handle broadcasting over arrays
zz    = follow(a, ops_b) # Apply all the operations
```
`@deep` is essentially composed of the above three function calls.

With output:
```julia
julia> ops   = _getter(a, :zz)  # Get a vector of operations
4-element Array{Expr,1}:
 :(x -> getfield(x, :z))
 :(x -> getfield(x, :yy))
 :(x -> getindex(x, 1))
 :(x -> getfield(x, :zz))

julia> ops_b = _getter(ops)     # Modify operations to handle broadcasting over arrays
3-element Array{Expr,1}:
 :(x -> getfield(x, :z))
 :(x -> getfield(x, :yy))
 :(x -> getfield.(x, :zz))

julia> zz    = follow(a, ops_b) # Apply all the operations
2-element Array{Int64,1}:
 1
 2
```
# Limitations
- If several fields inside the structure have the same name, the first field found (depth first) is returned and others ignored.
- Arrays are looked through, but it is assumed that all elements in the array have the same field names. Only the first element is looked at during search. If the field is found inside an `{Array / Array{Arrays}}`, then the result will have that same structure. Use `denest` to flatten.
- Tests are so far limited and bugs are expected.
