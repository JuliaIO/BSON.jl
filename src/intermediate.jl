"""Type class which represents a tagged dictionary

Tagged dictionaries are used to represent complex Julia types. Using a struct
instead of an actual Dictionary requires less memory allocation and allows us
to use multiple dispatch on the resulting tree structure.

It inherits abstract dict just for show."""
abstract type Tagged <: AbstractDict{Symbol, Any} end

"Type class for types which can occupuy the 'type' field in a struct"
abstract type TaggedStructType <: Tagged end

# Needed for show
Base.length(tt::T) where {T <: Tagged} = length(fieldnames(T))
Base.getindex(tt::Tagged, k::Symbol) = getfield(tt, k)
Base.iterate(tt::T) where {T <: Tagged} = let first = fieldnames(T)[1]
  (first => tt[first], 2)
end
Base.iterate(tt::T, state) where {T <: Tagged} = let names = fieldnames(T)
  if length(names) >= state
    next = names[state]
    (next => tt[next], state + 1)
  else
    nothing
  end
end

function applychildren!(f::Function, tt::T)::T where {T <: Tagged}
  for fn in fieldnames(T)
    setfield!(tt, fn, f(getfield(tt, fn)))
  end
  tt
end

struct TaggedBackref <: TaggedStructType
  ref::Int64
end

Base.show(io::IO, br::TaggedBackref) = print(io, "Ref(", br.ref, ")")

mutable struct TaggedTuple <: Tagged
  data::BSONArray
end

mutable struct TaggedSvec <: Tagged
  data::BSONArray
end

const TaggedParam = Union{Tagged, TypeVar, Type}

mutable struct TaggedType <: TaggedStructType
  name::Vector{String}
  params::Vector{TaggedParam}
end

mutable struct TaggedStruct <: TaggedStructType
  ttype::TaggedStructType
  data::BSONArray
end

mutable struct TaggedArray <: Tagged
  ttype::TaggedStructType
  size::BSONArray
  data::Union{Vector{UInt8}, BSONArray}
end

mutable struct TaggedAnonymous <: TaggedStructType
  typename::Union{TaggedStruct, TaggedBackref}
  params::Vector{TaggedParam}
end

struct TaggedRef <: Tagged
  path::Vector{String}
end

mutable struct TaggedUnionall <: Tagged
  var::Union{TaggedStruct, TaggedBackref, TaggedUnionall}
  body::Union{TaggedType, TaggedBackref, TaggedUnionall, TaggedAnonymous}
end

struct BackRefsWrapper
  root::Union{BSONDict, TaggedStruct}
  refs::BSONArray
end

function Base.show(io::IO, brw::BackRefsWrapper)
  summary(io, brw)
  print(io, ".root => ")
  show(io, MIME("text/plain"), brw.root)
  summary(io, brw)
  print(io, ".refs => ")
  show(io, MIME("text/plain"), brw.refs)
end

function applychildren!(f::Function, tt::Union{TaggedTuple, TaggedSvec})
  tt.data = f(tt.data)
  tt
end
applychildren!(f::Function, v::Vector{TaggedParam}) = applyvec!(f, v)
function applychildren!(f::Function, tt::TaggedType)::TaggedType
  tt.params = f(tt.params)
  tt
end
function applychildren!(f::Function, ts::TaggedStruct)::TaggedStruct
  ts.ttype = f(ts.ttype)
  if ts.data != nothing
    ts.data = f(ts.data::BSONArray)
  end
  ts
end
applychildren!(::Function, tr::TaggedRef) = tr

const PassthroughTypes = Union{Vector{UInt8}, Type{Union{}}, Symbol, String}
const RefVectorTypes = Union{Vector{TaggedParam}, BSONArray}

_raise_recursive(x::T, cache::IdDict{Any, Any}) where T = if isbitstype(T)
  x
elseif haskey(cache, x)
  cache[x]
else
  cache[x] = raise_recursive(x, cache)
end

raise_recursive(x, ::IdDict{Any, Any}) = x
function raise_recursive(d::BSONDict, cache::IdDict{Any, Any})::BSONDict
  cache[d] = d
  applychildren!(x -> _raise_recursive(x, cache), d)
end
function raise_recursive(v::T, cache::IdDict{Any, Any}) where {T <: RefVectorTypes}
  cache[v] = v
  applyvec!(x -> _raise_recursive(x, cache), v)
end
raise_recursive(tt::TaggedTuple, cache::IdDict{Any, Any})::Tuple =
  (raise_recursive(tt.data, cache)...,)
raise_recursive(tt::TaggedSvec, cache::IdDict{Any, Any})::SimpleVector =
  Core.svec(raise_recursive(tt.data, cache)...)
raise_recursive(tt::TaggedType, cache::IdDict{Any, Any})::Type =
  constructtype(resolve(tt.name), raise_recursive(tt.params, cache))
function raise_recursive(ts::TaggedStruct, cache::IdDict{Any, Any})
  T::Type = _raise_recursive(ts.ttype, cache)

  if ismutable(T)
    return newstruct_raw(cache, T, ts)
  end

  data = raise_recursive(ts.data, cache)
  if isprimitive(T)
    newprimitive(T, data)
  else
    newstruct(T, data...)
  end
end
function raise_recursive(ta::TaggedArray, cache::IdDict{Any, Any})
  T::DataType = _raise_recursive(ta.ttype, cache)
  size = raise_recursive(ta.size, cache)
  data() = raise_recursive(ta.data, cache)

  if isbitstype(T)
    if sizeof(T) == 0
      fill(T(), size...)
    else
      reshape(reinterpret_(T, data()), size...)
    end
  else
    Array{T}(reshape(data(), size...))
  end
end
function raise_recursive(ts::TaggedAnonymous, cache::IdDict{Any, Any})
  tn = _raise_recursive(ts.typename::TaggedStruct, cache)
  pr = _raise_recursive(ts.params, cache)
  constructtype(tn.wrapper, pr)
end
raise_recursive(ts::TaggedRef, cache::IdDict{Any, Any})::Module =
  resolve(ts.path)
raise_recursive(tu::TaggedUnionall, cache::IdDict{Any, Any})::UnionAll =
  UnionAll(_raise_recursive(tu.var, cache),
           _raise_recursive(tu.body, cache))
