abstract type Tagged <: AbstractDict{Symbol, Any} end

Base.haskey(::Tagged, k::Symbol) = k == :tag

mutable struct TaggedType <: Tagged
  name::Vector{String}
  params::Vector{TaggedType}
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

mutable struct TaggedStruct <: Tagged
  ttype::Union{TaggedType, DataType}
  data::Vector{Union{Primitive, TaggedStruct}}
end

Base.getindex(ts::TaggedStruct, k::Symbol) = if k == :tag
  "struct"
elseif k == :type
  ts.ttype
elseif k == :data
  ts.data
else
  error("Can't set $k")
end

Base.setindex!(ts::TaggedStruct, ::Symbol, v::DataType) =
  ts.ttype = v
