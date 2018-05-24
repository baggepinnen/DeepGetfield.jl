module DeepGetfield

export getter, findfield, denest, @deep, @deepf

using MacroTools

"""
    follow(data, operations)
Executes the `operation`s on `data` to return the field the operations are pointing at.
"""
function follow(data,operations::Vector{Expr})
    isempty(operations) && (return data)
    f = eval(operations[1])
    return follow(Base.invokelatest(f,data), operations[2:end])
end

function follow(data,operations::Vector{<:Function})
    isempty(operations) && (return data)
    f = operations[1]
    return follow(f(data), operations[2:end])
end

"""
Evaluates the expression and returns a Function. Uses `invokelatest`.
"""
function op2fun(ops)
    f = eval(ops)
    x -> Base.invokelatest(f,x)
end

"""
    operations::Vector{Expr} = findfield(data, field, maxdepth=8)
Recursively (depth first) searches through the composite type `data` in search for `field`
Returns a vector of Function expressions that if followed, leads to the field.
The result should be postprocessed by `tobroadcast`.
"""
function findfield(data, field, maxdepth=8)
    operations = Expr[]
    findfield(data,field, maxdepth, operations)
end

function findfield(data, field, maxdepth, operations::Vector{Expr})
    if length(operations) > maxdepth
        return nothing
    end
    dt = typeof(follow(data, operations))
    if dt <: AbstractArray || dt <: Tuple
        push!(operations, :(x-> getindex(x,1)))
        found = findfield(data, field, maxdepth, operations)
        found != nothing && (return operations)
    else
        names = fieldnames(dt)
        for name in names
            push!(operations, :(x-> getfield(x,$(QuoteNode(name)))))
            if name == field
                return operations
            end
            found = findfield(data,field, maxdepth, operations)
            found != nothing && (return operations)
            pop!(operations)
        end
    end
    return nothing
end

"""
    ops::Vector{Expr} tobroadcast(operations::Vector{Expr})
Searches for `getindex` operations, removes them and broadcasts subsequent operations.
"""
function tobroadcast(operations)
    operations = copy(operations)
    broadcasts = 0
    i = 1
    while i <= length(operations)
        op = operations[i]
        match = @capture(op, x->f_(x,arg_))
        if match && f == :getindex
            broadcasts += 1
            deleteat!(operations, i)
            @capture(operations[i], x->f_(x, arg_))
            if f == :getindex # TODO: only handles two consequtive getindex
                broadcasts += 1
                deleteat!(operations, i)
                @capture(operations[i], x->f_(x, arg_))
                field = QuoteNode(arg.value)
                ex = :(y -> (x -> $(f).(x,$(field))).(y))
            else
                field = QuoteNode(arg.value)
                if broadcasts == 1
                    ex = :(x -> $(f).(x,$(field)))
                else
                    ex = :(x -> $(f).(x,$(field)))
                    for j = 2:broadcasts
                        ex = :(y -> ($(ex)).(y))
                    end
                end
            end
            operations[i] = ex
        elseif broadcasts >= 1 # getfield
            field = QuoteNode(arg.value)
            if broadcasts == 1
                ex = :(x -> $(f).(x,$(field)))
            else
                ex = :(x -> $(f).(x,$(field)))
                for j = 2:broadcasts
                    ex = :(y -> ($(ex)).(y))
                end
            end
            operations[i] = ex
        end
        i += 1
    end
    operations
end


"""
    getter(data, field, maxdepth=8; denest=false)
Function version of `@deepf`. Allows specification of maximum search depth and whether or not do `denest` the result. See also `denest`, `@deepf`.
"""
function getter(args...; denest=false)
    # TODO: preevaluate expressions
    ops = tobroadcast(findfield(args...))
    ops = op2fun.(ops)
    if denest
        z->_denest(follow(z, ops))
    else
        z->follow(z, ops)
    end
end

"""
    denest(x::Array{Array...})

Flattens the structure of x from an array of arrays to a tensor. Can handle deep nestings.
```julia
x = [1, 2]
y = [x, x, x]
z = [y, y, y, y]
denest(x) == x
denest(y) == [x x x]
denest(z) == cat(3, denest(y), denest(y), denest(y), denest(y))
```
"""
function denest(x)
    dims = calcdims(x)
    x = denest_rec(x)
    x = reshape(x, reverse(dims)...)
    x
end

function denest_rec(x)
    if x isa Array{<: Array}
        x = vcat(x...)
        return denest(x)
    end
    x
end

calcdims(x) = calcdims(x[1],[length(x)])
calcdims(x, dims) = dims
calcdims(x::AbstractArray, dims) = calcdims(x[1], push!(dims, length(x)))


"""
    @deep data.field
Deep getfield

Searches through the structure `data` and returns a `field` where `field` is somewhere deep inside `data`.
Arrays are broadcasted over, but the search only looks at the first element.
"""
macro deep(ex)
    @capture(ex, data_.field_) || error("Expected an expression on the form data.field")
    quote
        getter($(esc(data)), $(QuoteNode(field)))($(esc(data)))
    end
end

"""
    @deepf
Deep getfield

Searches through the structure `data` and returns a function `data -> field` where `field` is somewhere deep inside `data`.
Arrays are broadcasted over, but the search only looks at the first element.
"""
macro deepf(ex)
    @capture(ex, data_.field_) || error("Expected an expression on the form data.field")
    quote
        getter($(esc(data)), $(QuoteNode(field)))
    end
end


end # module
