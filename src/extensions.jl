lower(x::Dict{Symbol}) = BSONDict(x)

# Basic Types

ismutable(::Type{Symbol}) = false
lower(x::Symbol) = BSONDict(:tag => "symbol", :name => String(x))

lower(x::Tuple) = BSONDict(:tag => "tuple", :data => Any[x...])

ismutable(::Type{SimpleVector}) = false
lower(x::SimpleVector) = BSONDict(:tag => "svec", :data => Any[x...])

# References

ref(path::Symbol...) = BSONDict(:tag => "ref", :path => Base.string.([path...]))

resolve(fs) = reduce((m, f) -> getfield(m, Symbol(f)), fs; init = Main)

function modpath(x::Module)
  y = parentmodule(x)
  x == y ? [nameof(x)] : [modpath(y)..., nameof(x)]
end

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

constructtype(T, Ts) = (length(Ts) == 0) ? T : T{Ts...}
constructtype(T::Type{Tuple}, Ts) = T{Ts...}

lower(v::UnionAll) =
  BSONDict(:tag => "unionall",
           :body => v.body,
           :var => v.var)

# Arrays

lower(x::Vector{Any}) = copy(x)
lower(x::Vector{UInt8}) = x

reinterpret_(::Type{T}, x) where T =
  T[reinterpret(T, x)...]

function lower(x::Array)
  ndims(x) == 1 && !isbitstype(eltype(x)) && return Any[x...]
  BSONDict(:tag => "array", :type => eltype(x), :size => Any[size(x)...],
           :data => isbitstype(eltype(x)) ? reinterpret_(UInt8, reshape(x, :)) : Any[x...])
end

# Structs

isprimitive(T) = fieldcount(T) == 0 && T.size > 0

structdata(x) = isprimitive(typeof(x)) ? reinterpret_(UInt8, [x]) :
    Any[getfield(x, f) for f in fieldnames(typeof(x))]

function lower(x)
  BSONDict(:tag => "struct", :type => typeof(x), :data => structdata(x))
end

initstruct(T) = ccall(:jl_new_struct_uninit, Any, (Any,), T)

function newstruct!(x, fs...)
  #@debug "newstruct!" typeof(x) fs
  for (i, f) = enumerate(fs)
    try
      f = convert(fieldtype(typeof(x),i), f)
    catch e
      #@debug "newstruct!" i typeof(x) fieldtype(typeof(x), i)
      rethrow(e)
    end
    ccall(:jl_set_nth_field, Nothing, (Any, Csize_t, Any), x, i-1, f)
  end
  return x
end

function newstruct(T::Type, xs...)
  if isbitstype(T)
    flds = Any[convert(fieldtype(T, i), x) for (i,x) in enumerate(xs)]
    return ccall(:jl_new_structv, Any, (Any,Ptr{Cvoid},UInt32), T, flds, length(flds))
  else
    # Manual inline of newstruct! to work around bug
    # https://github.com/MikeInnes/BSON.jl/issues/2#issuecomment-452204339
    x = initstruct(T)

    for (i, f) = enumerate(xs)
      f = convert(fieldtype(typeof(x),i), f)
      ccall(:jl_set_nth_field, Nothing, (Any, Csize_t, Any), x, i-1, f)
    end
    x

  end
end

function newstruct_raw(cache::IdDict{Any, Any}, T::Type, d::TaggedStruct)
  @assert isstructtype(T) "$T is not struct type"
  #@debug "newstruct_raw" T d

  x = cache[d] = initstruct(T)
  fs = (_raise_recursive(x, cache) for x in d.data)

  newstruct!(x, fs...)
end

newprimitive(T, data) = reinterpret_(T, data)[1]

iscyclic(T) = ismutable(T)

lower(v::Type{Union{}}) = BSONDict(:tag=>"jl_bottom_type")

# Base data structures

structdata(d::Dict) = Any[collect(keys(d)), collect(values(d))]

initstruct(D::Type{<:Dict}) = D()

function newstruct!(d::Dict, ks, vs)
  for (k, v) in zip(ks, vs)
    d[k] = v
  end
  return d
end
