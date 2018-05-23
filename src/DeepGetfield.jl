module DeepGetfield

export getter, denest, @deep, @deepf

using MacroTools

function _getter(data, field, maxdepth=8)
    operations = Expr[]
    _getter(data,field, maxdepth, operations)
end

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

function _getter(data, field, maxdepth, operations::Vector{Expr})
    if length(operations) > maxdepth
        return nothing
    end
    dt = typeof(follow(data, operations))
    if dt <: AbstractArray
        push!(operations, :(x-> getindex(x,1)))
        found = _getter(data,field, maxdepth, operations)
        found != nothing && (return operations)
    else
        names = fieldnames(dt)
        for name in names
            push!(operations, :(x-> getfield(x,$(QuoteNode(name)))))
            if name == field
                return operations
            end
            found = _getter(data,field, maxdepth, operations)
            found != nothing && (return operations)
            pop!(operations)
        end
    end
    return nothing
end

function _getter(operations)
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
            if f == :getindex
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

function op2fun(ops)
    f = eval(ops)
    x -> Base.invokelatest(f,x)
end

function getter(args...; denest=false)
    # TODO: preevaluate expressions
    ops = _getter(_getter(args...))
    ops = op2fun.(ops)
    if denest
        z->_denest(follow(z, ops))
    else
        z->follow(z, ops)
    end
end


function denest_rec(x)
    if x isa Array{<: Array}
        x = vcat(x...)
        return denest(x)
    end
    x
end

function denest(x)
    dims = calcdims(x)
    x = denest_rec(x)
    x = reshape(x, getindex.(dims, 1)...)
    x
end

calcdims(x) = calcdims(x[1],[length(x)])
calcdims(x, dims) = dims
calcdims(x::AbstractArray, dims) = calcdims(x[1], push!(dims, length(x)))


macro deep(ex)
    @capture(ex, data_.field_) || error("Expected an expression on the form data.field")
    quote
        getter($(esc(data)), $(QuoteNode(field)))($(esc(data)))
    end
end

macro deepf(ex)
    @capture(ex, data_.field_) || error("Expected an expression on the form data.field")
    quote
        getter($(esc(data)), $(QuoteNode(field)))
    end
end


end # module
