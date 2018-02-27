module BSON

export bson

const BSONDict = Dict{Symbol,Any}
const BSONArray = Vector{Any}
const Primitive = Union{Void,Bool,Int32,Int64,Float64,String,Vector{UInt8},BSONDict,BSONArray}

@enum(BSONType::UInt8,
  eof, double, string, document, array, binary, undefined, objectid, boolean,
  datetime, null, regex, dbpointer, javascript, symbol, javascript_scoped,
  int32, timestamp, int64, decimal128, minkey=0xFF, maxkey=0x7F)

applychildren!(f, x) = x

function applychildren!(f, x::BSONDict)
  for k in keys(x)
    x[k] = f(x[k])
  end
  return x
end

function applychildren!(f, x::BSONArray)
  for i = 1:length(x)
    x[i] = f(x[i])
  end
  return x
end

include("write.jl")
include("read.jl")
include("extensions.jl")
include("anonymous.jl")

end # module
