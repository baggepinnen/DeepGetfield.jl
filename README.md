# FieldGetter

[![Build Status](https://travis-ci.org/baggepinnen/FieldGetter.jl.svg?branch=master)](https://travis-ci.org/baggepinnen/FieldGetter.jl)

[![Coverage Status](https://coveralls.io/repos/baggepinnen/FieldGetter.jl/badge.svg?branch=master&service=github)](https://coveralls.io/github/baggepinnen/FieldGetter.jl?branch=master)

[![codecov.io](http://codecov.io/github/baggepinnen/FieldGetter.jl/coverage.svg?branch=master)](http://codecov.io/github/baggepinnen/FieldGetter.jl?branch=master)


This package provides the function `f = getter(data::CompositeType, fieldname::Symbol)` which returns a function that acts as a deep version of getfield: `f(data) -> deep_getfield(data, fieldname)`.

`data` might be a complex composite type with fields which are themselves composite types or arrays. `getter` searches the structure `data` depth first for the first occurrence of a field with name `fieldname` and returns a function that gets that field. An illustration is provided below, where `a` is a complicated type, and the user wants a function that returns the field `zz` deep inside `a`.

## Motivation
I frequently run many experiments in parallel using `pmap` etc. and results may be a custom type stored in a custom type, tuple, array etc.. To analyze the results I need to access a particular field deep inside the result structure and figuring out how to find it is often a hassle. This package does the searching for you and returns a function which gets the requested field.

## Installation
`Pkg.clone("https://github.com/baggepinnen/FieldGetter.jl")`


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

julia> getterfun = getter(a, :yy) # This function acts as deep_getfield(a,:yy)

julia> getterfun(a) # Get field yy, equivalent to a.z.yy
2-element Array{C,1}:
 C(1)
 C(2)

julia> getterfun = getter(a, :zz) # Getter for field zz, equivalent to getfield.(a.z.yy, :zz)

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
get_zz = getter(a, :zz)
```

# Functions
- `getter(d::CompositeType, fieldname::Symbol, [max_depth = 5])::Function d-> $fieldname`
Searches through the structure `data` for a field with name `fieldname`. Arrays are broadcasted over, but the search only looks at the first element.
- `denest(x::Array{Array...})` flattens the structure of `x` from an array of arrays to a tensor. Can handle deep nestings.


# Limitations
- If several fields deep inside the structure have the same name, the first field found (depth first) is returned and others ignored.
- Arrays are looked through, but it is assumed that all elements in the array have the same field names. Only the first element is looked at during search.
- Tests are so far limited and bugs are expected.
