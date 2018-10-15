bson_type(::Nothing) = null
bson_type(::Bool) = boolean
bson_type(::Int32) = int32
bson_type(::Int64) = int64
bson_type(::Float64) = double
bson_type(::String) = string
bson_type(::Vector{UInt8}) = binary
bson_type(::BSONDict) = document
bson_type(::BSONArray) = array

bson_primitive(io::IO, ::Nothing) = return
bson_primitive(io::IO, x::Union{Bool,Int32,Int64,Float64}) = write(io, x)
bson_primitive(io::IO, x::Float64) = write(io, x)
bson_primitive(io::IO, x::Vector{UInt8}) = write(io, Int32(length(x)), 0x00, x)
bson_primitive(io::IO, x::String) = write(io, Int32(sizeof(x)+1), x, 0x00)

bson_key(io::IO, k) = write(io, Base.string(k), 0x00)

function bson_pair(io::IO, k, v)
  write(io, bson_type(v))
  bson_key(io, k)
  bson_primitive(io, v)
end

function bson_doc(io::IO, doc)
  buf = IOBuffer()
  for (k, v) in doc
    bson_pair(buf, k, v)
  end
  write(buf, eof)
  bytes = read(seek(buf,0))
  write(io, Int32(length(bytes)+4), bytes)
  return
end

bson_primitive(io::IO, doc::BSONDict) = bson_doc(io, doc)
bson_primitive(io::IO, x::BSONArray) =
  bson_doc(io, [Base.string(i-1) => v for (i, v) in enumerate(x)])

# Lowering

lower(x::Primitive) = x

import Base: RefValue

ismutable(T) = !isbitstype(T)
ismutable(::Type{String}) = false

typeof_(x) = typeof(x)
typeof_(T::DataType) = T

function _lower_recursive(x, cache, refs)
  _lower(x) = applychildren!(x -> _lower_recursive(x, cache, refs), lower(x)::Primitive)
  ismutable(typeof_(x)) || return RefValue{Any}(_lower(x))
  if haskey(cache, x)
    if !any(y -> x === y, refs)
      push!(refs, cache[x])
    end
    return cache[x]
  end
  cache[x] = RefValue{Any}(nothing)
  val = applychildren!(x -> _lower_recursive(x, cache, refs), lower(x)::Primitive)
  cache[x].x == nothing && (cache[x].x = val)
  return cache[x]
end

stripref(x::RefValue) = stripref(x.x)
stripref(x) = applychildren!(stripref, x)

function lower_recursive(y)
  cache = IdDict()
  backrefs = []
  x = _lower_recursive(y, cache, backrefs).x
  isempty(backrefs) || (x[:_backrefs] = Any[x.x for x in backrefs])
  foreach((ix) -> (ix[2].x = BSONDict(:tag=>"backref",:ref=>ix[1])), enumerate(backrefs))
  return stripref(x)
end

# Interface

bson(io::IO, doc::AbstractDict) = bson_primitive(io, lower_recursive(doc))

bson(path::String, doc::AbstractDict) = open(io -> bson(io, doc), path, "w")

bson(path::String; kws...) = bson(path, Dict(kws))
