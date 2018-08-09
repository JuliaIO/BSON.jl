lower(x::Dict{Symbol}) = BSONDict(x)

# Basic Types

ismutable(::Type{Symbol}) = false
lower(x::Symbol) = BSONDict(:tag => "symbol", :name => String(x))
tags[:symbol] = d -> Symbol(d[:name])

lower(x::Tuple) = BSONDict(:tag => "tuple", :data => Any[x...])
tags[:tuple] = d -> (d[:data]...,)

ismutable(::Type{SimpleVector}) = false
lower(x::SimpleVector) = BSONDict(:tag => "svec", :data => Any[x...])
tags[:svec] = d -> Core.svec(d[:data]...)

# References

ref(path::Symbol...) = BSONDict(:tag => "ref", :path => Base.string.([path...]))

resolve(fs) = reduce((m, f) -> getfield(m, Symbol(f)), Main, fs)

tags[:ref] = d -> resolve(d[:path])

modpath(x::Module) = x == Main ? [] : [modpath(module_parent(x))..., module_name(x)]

ismutable(::Type{Module}) = false
lower(m::Module) = ref(modpath(m)...)

# Types

ismutable(::Type{<:Type}) = false

typepath(x::DataType) = [modpath(x.name.module)..., x.name.name]

function lower(v::DataType)
  isanon(v) && return lower_anon(v)
  BSONDict(:tag => "datatype",
           :name => Base.string.(typepath(v)),
           :params => [v.parameters...])
end

constructtype(T) = T
constructtype(T, Ts...) = T{Ts...}

tags[:datatype] = d -> constructtype(resolve(d[:name]), d[:params]...)

lower(v::UnionAll) =
  BSONDict(:tag => "unionall",
           :body => v.body,
           :var => v.var)

tags[:unionall] = d -> UnionAll(d[:var], d[:body])

# Arrays

lower(x::Vector{Any}) = copy(x)
lower(x::Vector{UInt8}) = x

function collect_any(xs)
  ys = Vector{Any}(length(xs))
  for i = 1:length(xs)
    isassigned(xs, i) && (ys[i] = xs[i])
  end
  return ys
end

function lower(x::Array)
  ndims(x) == 1 && !isbits(eltype(x)) && return collect_any(x)
  BSONDict(:tag => "array", :type => eltype(x), :size => Any[size(x)...],
           :data => isbits(eltype(x)) ? reinterpret(UInt8, reshape(x, :)) : collect_any(x))
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

initstruct(T) = ccall(:jl_new_struct_uninit, Any, (Any,), T)

function newstruct!(x, fs...)
  for (i, f) = enumerate(fs)
    f = convert(fieldtype(typeof(x),i), f)
    ccall(:jl_set_nth_field, Void, (Any, Csize_t, Any), x, i-1, f)
  end
  return x
end

function newstruct(T, xs...)
  if isbits(T)
    flds = Any[convert(fieldtype(T, i), x) for (i,x) in enumerate(xs)]
    return ccall(:jl_new_structv, Any, (Any,Ptr{Void},UInt32), T, flds, length(flds))
  else
    newstruct!(initstruct(T), xs...)
  end
end

function newstruct_raw(cache, T, d)
  x = cache[d] = initstruct(T)
  fs = map(x -> raise_recursive(x, cache), d[:data])
  return newstruct!(x, fs...)
end

newprimitive(T, data) = reinterpret(T, data)[1]

tags[:struct] = d ->
  isprimitive(d[:type]) ?
    newprimitive(d[:type], d[:data]) :
    newstruct(d[:type], d[:data]...)

iscyclic(T) = ismutable(T)

raise[:struct] = function (d, cache)
  T = d[:type] = raise_recursive(d[:type], cache)
  iscyclic(T) || return _raise_recursive(d, cache)
  return newstruct_raw(cache, T, d)
end

lower(v::Type{Union{}}) = BSONDict(:tag=>"jl_bottom_type")
tags[:jl_bottom_type] = d -> Union{}

# Base data structures

structdata(d::Dict) = Any[collect(keys(d)), collect(values(d))]

initstruct(D::Type{<:Dict}) = D()

function newstruct!(d::Dict, ks, vs)
  for (k, v) in zip(ks, vs)
    d[k] = v
  end
  return d
end
