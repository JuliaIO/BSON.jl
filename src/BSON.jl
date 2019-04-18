module BSON

using Core: SimpleVector, TypeName
export bson

using Core: SimpleVector, TypeName

const BSONDict = Dict{Symbol,Any}
const BSONArray = Vector{Any}
const Primitive = Union{Nothing,Bool,Int32,Int64,Float64,String,Vector{UInt8},BSONDict,BSONArray}

@enum(BSONType::UInt8,
  eof, double, string, document, array, binary, undefined, objectid, boolean,
  datetime, null, regex, dbpointer, javascript, symbol, javascript_scoped,
  int32, timestamp, int64, decimal128, minkey=0xFF, maxkey=0x7F)

function applydict!(f::Function, x::T)::T where {T <: AbstractDict}
  for k in keys(x)
    x[k] = f(x[k])
  end
  return x
end

function applyvec!(f::Function, x::Vector{T})::Vector{T} where {T}
  for i = 1:length(x)
    x[i] = f(x[i])
  end
  return x
end

applychildren!(::Function, x::Union{Primitive, Type{Union{}}, Symbol}) = x
applychildren!(f::Function, x::BSONDict)::BSONDict = applydict!(f, x)
applychildren!(f::Function, x::BSONArray)::BSONArray = applyvec!(f, x)

"Cache the result of a calculation for a given input"
memoise(func::Function, input, cache::IdDict{Any, Any}) = if haskey(cache, input)
  cache[input]
else
  cache[input] = func(input)
end

"""Cache the input parameter to calculation as its output

Assumes the object is changed inplace. Allows objects to reference themselves.
"""
prememoise(func::Function, input, cache::IdDict{Any, Any}) = if haskey(cache, input)
  cache[input]
else
  cache[input] = input
  func(input)
end

include("write.jl")
include("intermediate.jl")
include("read.jl")
include("extensions.jl")
include("anonymous.jl")
include("fileio_interface.jl")

using Base.Meta

macro save(file, ks...)
  ks = map(k -> k isa Symbol ? (k,k) :
                isexpr(k,:(=)) && k.args[1] isa Symbol ? (k.args[1],k.args[2]) :
                error("Unrecognised @save expression $k"), ks)
  :(bson($(esc(file)), Dict($([:($(Expr(:quote,s))=>$(esc(k))) for (s,k) in ks]...) )))
end

macro load(file, ks...)
  @assert all(k -> k isa Symbol, ks)
  ss = Expr.(:quote, ks)
  quote
    data = load($(esc(file)))
    ($(esc.(ks)...),) = ($([:(data[$k]) for k in ss]...),)
    nothing
  end
end

end # module
