lower(x::Dict{Symbol}) = BSONDict(x)
lower(x::BSONDict) = BSONDict(x)

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

function _find_module(x)
    for (k, v) in Base.loaded_modules
        k.name == x && return v
    end
    return nothing
end

function resolve(fs, init)
    ff = first(fs)
    m = _find_module(ff)
    if m !== nothing
        init = m
        fs = @view fs[2:end]
    end
    return reduce((m, f) -> getfield(m, Symbol(f)), fs; init = init)
end

tags[:ref] = (d, init) -> resolve(d[:path], init)

function modpath(x::Module)
  y = parentmodule(x)
  x == y ? [nameof(x)] : [modpath(y)..., nameof(x)]
end

ismutable(::Type{Module}) = false
lower(m::Module) = ref(modpath(m)...)

# Types

@static if VERSION < v"1.7.0-DEV"
  # Borrowed from julia base
  function ismutabletype(@nospecialize(t::Type))
      t = Base.unwrap_unionall(t)
      # TODO: what to do for `Union`?
      return isa(t, DataType) && t.mutable
  end
end


ismutable(::Type{<:Type}) = false

typepath(x::DataType) = [modpath(x.name.module)..., x.name.name]

function lower(v::DataType)
  isanon(v) && return lower_anon(v)
  BSONDict(:tag => "datatype",
           :name => Base.string.(typepath(v)),
           :params => [v.parameters...])
end

# For issue #41. Type-params are normally Int32, or Int64 depending on saving system Int
# We should convert them both to loading system Int
normalize_typeparams(x) = x
normalize_typeparams(x::Union{Int32,Int64}) = Int(x)

constructtype(T, Ts) = (length(Ts) == 0) ? T : T{map(normalize_typeparams, Ts)...}
constructtype(T::Type{Tuple}, Ts) = T{map(normalize_typeparams, Ts)...}

tags[:datatype] = (d, init) -> constructtype(resolve(d[:name], init), d[:params])

lower(v::UnionAll) =
  BSONDict(:tag => "unionall",
           :body => v.body,
           :var => v.var)

tags[:unionall] = d -> UnionAll(d[:var], d[:body])

# Arrays

lower(x::Vector{Any}) = copy(x)
lower(x::Vector{UInt8}) = x

reinterpret_(::Type{T}, x) where T =
    T[_x for _x in reinterpret(T, x)]

function lower(x::Array)
  ndims(x) == 1 && !isbitstype(eltype(x)) && return Any[x...]
  BSONDict(:tag => "array", :type => eltype(x), :size => Any[size(x)...],
           :data => isbitstype(eltype(x)) ? reinterpret_(UInt8, reshape(x, :)) : Any[x...])
end

tags[:array] = d ->
  isbitstype(d[:type]) ?
    sizeof(d[:type]) == 0 ?
      fill(d[:type](), d[:size]...) :
      reshape(reinterpret_(d[:type], d[:data]), map(normalize_typeparams, d[:size])...) :
    Array{d[:type]}(reshape(d[:data], d[:size]...))

# Structs

struct Undef end
function structdata(x)
  if isprimitivetype(typeof(x))
    return reinterpret_(UInt8, [x])
  elseif !ismutabletype(typeof(x))
    return Any[getfield(x,f) for f in fieldnames(typeof(x)) if isdefined(x, f)]
  else # mutable structs can have defined fields following undefined fields
    return Any[isdefined(x, f) ? getfield(x,f) : Undef() for f in fieldnames(typeof(x))]
  end
end

function lower(x)
  BSONDict(:tag => "struct", :type => typeof(x), :data => structdata(x))
end

initstruct(T) = ccall(:jl_new_struct_uninit, Any, (Any,), T)

function newstruct!(x, fs...)
  for (i, f) = enumerate(fs)
    isa(f, Undef) && continue
    f = convert(fieldtype(typeof(x),i), f)
    ccall(:jl_set_nth_field, Nothing, (Any, Csize_t, Any), x, i-1, f)
  end
  return x
end

if VERSION < v"1.7-"
function newstruct(T, xs...)
  if !ismutabletype(T)
    flds = Any[convert(fieldtype(T, i), x) for (i,x) in enumerate(xs)]
    return ccall(:jl_new_structv, Any, (Any,Ptr{Cvoid},UInt32), T, flds, length(flds))
  else
    # Manual inline of newstruct! to work around bug
    # https://github.com/MikeInnes/BSON.jl/issues/2#issuecomment-452204339
    x = initstruct(T)

    for (i, f) = enumerate(xs)
      isa(f, Undef) && continue
      f = convert(fieldtype(typeof(x),i), f)
      ccall(:jl_set_nth_field, Nothing, (Any, Csize_t, Any), x, i-1, f)
    end
    x

  end
end
else
function newstruct(T, xs...)
  if !ismutabletype(T)
    flds = Any[convert(fieldtype(T, i), x) for (i,x) in enumerate(xs)]
    return ccall(:jl_new_structv, Any, (Any,Ptr{Cvoid},UInt32), T, flds, length(flds))
  else
    # Manual inline of newstruct! to work around bug
    # https://github.com/MikeInnes/BSON.jl/issues/2#issuecomment-452204339
    x = initstruct(T)

    for (i, f) = enumerate(xs)
      isa(f, Undef) && continue
      f = convert(fieldtype(typeof(x),i), f)
      ccall(:jl_set_nth_field, Nothing, (Any, Csize_t, Any), x, i-1, f)
    end
    x

  end
end
end

function newstruct_raw(cache, T, d, init)
  x = cache[d] = initstruct(T)
  fs = map(x -> raise_recursive(x, cache, init), d[:data])
  return newstruct!(x, fs...)
end

newprimitive(T, data) = reinterpret_(T, data)[1]

tags[:struct] = d ->
  isprimitivetype(d[:type]) ?
    newprimitive(d[:type], d[:data]) :
    newstruct(d[:type], d[:data]...)

iscyclic(T) = ismutable(T)

raise[:struct] = function (d, cache, init)
  T = d[:type] = raise_recursive(d[:type], cache, init)
  iscyclic(T) || return _raise_recursive(d, cache, init)
  return newstruct_raw(cache, T, d, init)
end

lower(v::Type{Union{}}) = BSONDict(:tag=>"jl_bottom_type")
tags[:jl_bottom_type] = d -> Union{}

# Base data structures

structdata(d::Union{IdDict,Dict}) = Any[collect(keys(d)), collect(values(d))]

initstruct(D::Type{<:Union{IdDict,Dict}}) = D()

function newstruct!(d::Union{IdDict,Dict}, ks, vs)
  for (k, v) in zip(ks, vs)
    d[k] = v
  end
  return d
end
