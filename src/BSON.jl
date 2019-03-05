module BSON

using Core: SimpleVector, TypeName
export bson

using Core: SimpleVector, TypeName

struct BSONDict <: AbstractDict{Symbol,Any}
  d::Dict{Symbol,Any}
end
# implement some of the needed Dict methods
BSONDict(v) = BSONDict(Dict{Symbol,Any}(v))
BSONDict(v...) = BSONDict(Dict{Symbol,Any}(v...))
Base.length(bd::BSONDict) = length(bd.d)
Base.isempty(bd::BSONDict) = length(bd.d)==0
Base.setindex!(bd::BSONDict, v, k) = setindex!(bd.d, v, k)
Base.getindex(bd::BSONDict, k) = getindex(bd.d, k)
Base.iterate(bd::BSONDict) = iterate(bd.d)
Base.iterate(bd::BSONDict, i) = iterate(bd.d, i)
Base.get(bd::BSONDict, k, d) = get(bd.d, k, d)
Base.delete!(bd::BSONDict, k) = delete!(bd.d, k)

const BSONArray = Vector{Any}
const Primitive = Union{Nothing,Bool,Int32,Int64,Float64,String,Vector{UInt8},BSONDict,BSONArray}

@enum(BSONType::UInt8,
  eof, double, string, document, array, binary, undefined, objectid, boolean,
  datetime, null, regex, dbpointer, javascript, symbol, javascript_scoped,
  int32, timestamp, int64, decimal128, minkey=0xFF, maxkey=0x7F)

applychildren!(::Function, x) = x

function applychildren!(f::Function, x::BSONDict)::BSONDict
  for k in keys(x)
    x[k] = f(x[k])
  end
  return x
end

function applychildren!(f::Function, x::BSONArray)::BSONArray
  for i = 1:length(x)
    x[i] = f(x[i])
  end
  return x
end

include("write.jl")
include("read.jl")
include("extensions.jl")
include("anonymous.jl")

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
