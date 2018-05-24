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
Evaluates the expressions and returns a Function.
"""
function ops2fun(ops)
    if @capture(ops[1], x->g_(x, s_))
        ex = :(x-> $g(x, $s))
    elseif @capture(ops[1], x->g_.(x, s_))
        ex = :(x-> $(g).(x, $s))
    end
    for i = 2:length(ops)
        if @capture(ops[i], x->g_(x, s_))
            ex = :( x->$g($ex(x), $s) )
        elseif @capture(ops[i], x->g_.(x, s_))
            ex = :( x->$g.($ex(x), $s) )
        end
    end
    f = eval(ex)
end

"""
    operations::Vector{Expr} = findfield(data, field, maxdepth=8)
Recursively (depth first) searches through the composite Type `data` in search For `field`
Returns a vector of Function expressions that If followed, leads to the field.
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
    ops::Vector{Expr} = tobroadcast(operations::Vector{Expr})
Searches For `getindex` operations, removes them and broadcasts subsequent operations.
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
        Base.invokelatest(getter($(esc(data)), $(QuoteNode(field))), $(esc(data)))
    end
end

"""
    @deepf data.field
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


struct DeepGetter{F}
    f::F
    path::Vector{Symbol}
    operandtype::DataType
end # module

Base.show(io::IO, z::DeepGetter) = print(io, "Getter: ", path...)
function Base.show(io::IO, ::MIME"text/plain", g::DeepGetter)
    print(io, "DeepGetter($(g.path[end]))\nPath: ")
    for s in g.path
        print(io, s, " ")
    end
    print(io, "\nOperates on Type $(g.operandtype)\n")
end

(g::DeepGetter)(x) = g.f(x)

"""
    getter(data, field, maxdepth=8)
Function version of `@deepf`. Allows specification of maximum search depth. See also `denest`, `@deepf`.
"""
function getter(data, args...)
    # TODO: preevaluate expressions
    ops = findfield(data, args...)
    path = fieldsym.(ops)
    path = [s isa Symbol ? s : :broadcast for s ∈ path]
    ops_b = tobroadcast(ops)
    f = ops2fun(ops_b)
    DeepGetter(f, path, typeof(data))
end

function fieldsym(op)
    last = op.args[2].args[2].args[3]
    return last isa QuoteNode ? last.value : last
end

end
