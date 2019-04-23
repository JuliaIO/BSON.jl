abstract type Tagged <: AbstractDict{Symbol, Any} end
abstract type TaggedStructType <: Tagged end

Base.haskey(tt::T, k::Symbol) where {T <: Tagged} = k == :tag || k in fieldnames(T)
Base.isempty(::Tagged) = false
Base.length(::T) where {T <: Tagged} = length(fieldnames(T))
Base.getindex(tt::Tagged, k::Symbol) = getfield(tt, k)
Base.setindex!(tt::Tagged, v, k::Symbol) = setfield!(tt, k, v)
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
  data::Union{Nothing, BSONArray}
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

raise_recursive(tt::TaggedTuple, cache::IdDict{Any, Any})::Tuple = @memoise tt cache begin
  (raise_recursive(tt.data, cache)...,)
end
raise_recursive(tt::TaggedSvec, cache::IdDict{Any, Any})::SimpleVector = @memoise tt cache begin
  Core.svec(raise_recursive(tt.data, cache)...)
end
raise_recursive(v::Vector{TaggedParam}, cache::IdDict{Any, Any}) = @prememoise v cache begin
  applychildren!(x -> raise_recursive(x, cache), v)
end
raise_recursive(tt::TaggedType, cache::IdDict{Any, Any})::Type = @memoise tt cache begin
  constructtype(resolve(tt.name), raise_recursive(tt.params, cache))
end
raise_recursive(ts::TaggedStruct, cache::IdDict{Any, Any}) = @memoise ts cache begin
  T::Type = raise_recursive(ts.ttype, cache)

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
raise_recursive(ta::TaggedArray, cache::IdDict{Any, Any}) = @memoise ta cache begin
  T::DataType = raise_recursive(ta.ttype, cache)
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
raise_recursive(ts::TaggedAnonymous, cache::IdDict{Any, Any}) = @memoise ts cache begin
  tn = raise_recursive(ts.typename::TaggedStruct, cache)
  pr = raise_recursive(ts.params, cache)
  constructtype(tn.wrapper, pr)
end
raise_recursive(ts::TaggedRef, cache::IdDict{Any, Any}) = @memoise ts cache begin
  resolve(ts.path)
end
raise_recursive(tu::TaggedUnionall, cache::IdDict{Any, Any}) = @memoise tu cache begin
  UnionAll(raise_recursive(tu.var, cache),
           raise_recursive(tu.body, cache))
end
