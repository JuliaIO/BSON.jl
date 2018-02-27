lower(x::Associative{Symbol}) = BSONDict(x)
lower(x::SimpleVector) = collect(x)

# Basic Types

ismutable(::Type{Symbol}) = false
lower(x::Symbol) = BSONDict(:tag => "symbol", :name => String(x))
tags[:symbol] = d -> Symbol(d[:name])

lower(x::Tuple) = BSONDict(:tag => "tuple", :data => Any[x...])
tags[:tuple] = d -> (d[:data]...,)

# References

ref(path::Symbol...) = BSONDict(:tag => "ref", :path => Base.string.([path...]))

resolve(fs) = reduce((m, f) -> getfield(m, Symbol(f)), Main, fs)

tags[:ref] = d -> resolve(d[:path])

modpath(x::Module) = x == Main ? [] : [modpath(module_parent(x))..., module_name(x)]

lower(m::Module) = ref(modpath(m)...)

# Types

typepath(x::DataType) = [modpath(x.name.module)..., x.name.name]

lower(v::DataType) =
  BSONDict(:tag => "datatype",
           :name => Base.string.(typepath(v)),
           :params => v.parameters)

constructtype(T) = T
constructtype(T::UnionAll, Ts...) = T{Ts...}

tags[:datatype] = d -> constructtype(resolve(d[:name]), d[:params]...)

# Arrays

lower(x::Vector{Any}) = copy(x)
lower(x::Vector{UInt8}) = x

function lower(x::Array)
  ndims(x) == 1 && !isbits(eltype(x)) && return Any[x...]
  BSONDict(:tag => "array", :type => eltype(x), :size => Any[size(x)...],
           :data => isbits(eltype(x)) ? reinterpret(UInt8, reshape(x, :)) : Any[x...])
end

tags[:array] = d ->
  isbits(d[:type]) ?
    reshape(reinterpret(d[:type], d[:data]), d[:size]...) :
    Array{d[:type]}(reshape(d[:data], d[:size]...))

# Structs

isprimitive(T) = nfields(T) == 0 && T.size > 0

structdata(x) = isprimitive(typeof(x)) ? reinterpret(UInt8, [x]) : Any[getfield(x, f) for f in fieldnames(x)]

function lower(x)
  BSONDict(:tag => "struct", :type => typeof(x), :data => structdata(x))
end

function newstruct(T, xs...)
  if isbits(T)
    flds = Any[convert(fieldtype(T, i), x) for (i,x) in enumerate(xs)]
    return ccall(:jl_new_structv, Any, (Any,Ptr{Void},UInt32), T, flds, length(flds))
  else
    x = ccall(:jl_new_struct_uninit, Any, (Any,), T)
    for (i, f) = enumerate(xs)
      f = convert(fieldtype(T,i), f)
      ccall(:jl_set_nth_field, Void, (Any, Csize_t, Any), x, i-1, f)
    end
    return x
  end
end

function newstruct!(x, fs...)
  for (i, f) = enumerate(fs)
    ccall(:jl_set_nth_field, Void, (Any, Csize_t, Any), x, i-1, f)
  end
  return x
end

newprimitive(T, data) = reinterpret(T, data)[1]

tags[:struct] = d ->
  isprimitive(d[:type]) ?
    newprimitive(d[:type], d[:data]) :
    newstruct(d[:type], d[:data]...)

function newstruct_mutable(T, d, cache)
  x = cache[d] = ccall(:jl_new_struct_uninit, Any, (Any,), T)
  fs = map(x -> raise_recursive(x, cache), d[:data])
  return newstruct!(x, fs...)
end

iscyclic(T) = ismutable(T)

raise[:struct] = function (d, cache)
  T = d[:type] = raise_recursive(d[:type], cache)
  iscyclic(T) || return _raise_recursive(d, cache)
  return newstruct_mutable(T, d, cache)
end
