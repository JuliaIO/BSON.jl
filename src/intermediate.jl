abstract type Tagged <: AbstractDict{Symbol, Any} end

Base.haskey(::Tagged, k::Symbol) = k == :tag
Base.isempty(::Tagged) = false
Base.length(::Tagged) = 2

struct TaggedBackref <: Tagged
  ref::Int64
end

Base.show(io::IO, br::TaggedBackref) = print(io, "Ref(", br.ref, ")")

const TaggedParam = Union{Tagged, TypeVar, BSONDict, Type}

mutable struct TaggedType <: Tagged
  name::Vector{String}
  params::Vector{TaggedParam}
end

Base.getindex(tt::TaggedType, k::Symbol) = if k == :tag
  "datatype"
elseif k == :name
  tt.name
elseif k == :params
  tt.params
else
  error("Can't set $k")
end

function Base.setindex!(tt::TaggedType, v::TaggedType, s::Symbol)
  tt.params = v
end

Base.iterate(tt::TaggedType) = (:name => tt.name, 1)
Base.iterate(tt::TaggedType, state) = if state == 1
  (:params => tt.params, 2)
else
  nothing
end

function applychildren!(f::Function, tt::TaggedType)::TaggedType
  tt.params = f(tt.params)
  tt
end
applychildren!(f::Function, params::Vector{TaggedParam})::Vector{TaggedParam} =
  applyvec!(f, params)

raise_recursive(tt::TaggedType, cache::IdDict{Any, Any})::Type = get(cache, tt) do
  applychildren!(x -> raise_recursive(x, cache), tt)
  tags[:datatype](tt)
end

function raise_recursive(v::Vector{TaggedParam}, cache::IdDict{Any, Any})
  cache[v] = v
  applychildren!(x -> raise_recursive(x, cache), v)
end

mutable struct TaggedStruct <: Tagged
  ttype::Union{TaggedType, TaggedBackref, DataType, BSONDict}
  data::Union{Nothing, BSONArray}
end

Base.getindex(ts::TaggedStruct, k::Symbol) = if k == :tag
  "struct"
elseif k == :type
  ts.ttype
elseif k == :data && ts.data ≠ nothing
  ts.data
else
  error("Can't get $k")
end

function Base.setindex!(ts::TaggedStruct, v::DataType, s::Symbol)
  ts.ttype = v
end

Base.iterate(ts::TaggedStruct) = (:type => ts.ttype, 1)
Base.iterate(ts::TaggedStruct, state) = if state == 1 && ts.data ≠ nothing
  (:data => ts.data, 2)
else
  nothing
end

function applychildren!(f::Function, ts::TaggedStruct)::TaggedStruct
  ts.ttype = f(ts.ttype)
  if ts.data != nothing
    ts.data = f(ts.data::BSONArray)
  end
  ts
end

raise_recursive(ts::TaggedStruct, cache::IdDict{Any, Any}) = get(cache, ts) do
  T = raise_recursive(ts.ttype, cache)

  if ismutable(T)
    return newstruct_raw(cache, T, ts)
  end

  applychildren!(x -> raise_recursive(x, cache), ts)
  cache[ts] = if isprimitive(T)
    newprimitive(T, ts.data)
  else
    newstruct(T, ts.data...)
  end
end
