jtype(tag::BSONType)::DataType =
  tag == null ? Nothing :
  tag == boolean ? Bool :
  tag == int32 ? Int32 :
  tag == int64 ? Int64 :
  tag == double ? Float64 :
  error("Unsupported tag $tag")

parse_cstr(io::IO) = readuntil(io, '\0')

function parse_tag(io::IO, tag::BSONType)
  if tag == null
    nothing
  elseif tag == document
    parse_doc(io)
  elseif tag == array
    parse_array(io)
  elseif tag == string
    len = read(io, Int32)-1
    s = String(read(io, len))
    eof = read(io, 1)
    s
  elseif tag == binary
    len = read(io, Int32)
    subtype = read(io, 1)
    read(io, len)
  else
    read(io, jtype(tag))
  end
end

function parse_array(io::IO)::BSONArray
  len = read(io, Int32)
  ps = BSONArray()

  while (tag = read(io, BSONType)) ≠ eof
    # Note that arrays are dicts with the index as the key
    while read(io, UInt8) != 0x00
      nothing
    end
    push!(ps, parse_tag(io::IO, tag))
  end

  ps
end

function parse_tagged_type(io::IO)::TaggedType
  len = read(io, Int32)
  name = nothing
  params = nothing

  for _ in 1:3
    tag = read(io, BSONType)
    @assert tag ≠ eof
    k = Symbol(parse_cstr(io))
    if k == :name
      @assert tag == string "tag = $tag ≠ string"
      name = parse_tag(io, tag)
    elseif k == :params
      @assert tag == array "tag = $tag ≠ array"
      params = parse_tag(io, tag)
    else
      @assert k == :tag "tag = $k ≠ :tag"
      ttag = parse_tag(io, tag)
      @assert ttag == "datatype" "ttag = $ttag ≠ 'datatype'"
    end
  end

  TaggedType(name, params)
end

function parse_doc(io::IO)::Union{BSONDict, TaggedStruct}
  len = read(io, Int32)

  # First try to parse this document as a TaggedStruct. Note that both nothing
  # and missing are valid data values.
  tdata = (false, nothing)
  ttype = (false, nothing)
  ttag = (false, nothing)
  other = (false, nothing)
  k = nothing

  for _ in 1:3
    if (tag = read(io, BSONType)) == eof
      break
    end
    k = Symbol(parse_cstr(io))

    if k == :data
      @assert tag == array "tag = $tag ≠ array"
      tdata = (true, parse_tag(io::IO, tag))
    elseif k == :type
      @assert tag == document
      ttype = (true, parse_tagged_type(io::IO))
    elseif k == :tag
      @assert tag == string
      ttag = (true, parse_tag(io::IO, tag))
    else
      other = (true, parse_tag(io::IO, tag))
      break
    end
  end

  if ttag[2] == "struct"
    @assert tdata[1]
    @assert ttype[1]
    return TaggedStruct(ttype[2], tdata[2])
  end

  # It doesn't look like a TaggedStruct, so just allocate a Dict
  dic = BSONDict()
  tdata[1] && (dic[:data] = tdata[2])
  ttype[1] && (dic[:type] = ttype[2])
  ttag[1]  && (dic[:tag] = ttag[2])
  other[1] && (dic[k] = other[2])

  while (tag = read(io, BSONType)) ≠ eof
    k = Symbol(parse_cstr(io))
    dic[k] = parse_tag(io::IO, tag)
  end

  dic
end

backrefs!(x, refs) = applychildren!(x -> backrefs!(x, refs), x)

backrefs!(dict::BSONDict, refs) =
  get(dict, :tag, "") == "backref" ? refs[dict[:ref]] :
  invoke(backrefs!, Tuple{Any,Any}, dict, refs)

function backrefs!(dict)
  haskey(dict, :_backrefs) || return dict
  refs = dict[:_backrefs]
  backrefs!(dict, refs)
  delete!(dict, :_backrefs)
  return dict
end

const tags = Dict{Symbol,Function}()

const raise = Dict{Symbol,Function}()

function _raise_recursive(d::AbstractDict, cache)
  if haskey(d, :tag) && haskey(tags, Symbol(d[:tag]))
    cache[d] = tags[Symbol(d[:tag])](applychildren!(x -> raise_recursive(x, cache), d))
  else
    cache[d] = d
    applychildren!(x -> raise_recursive(x, cache), d)
  end
end

function raise_recursive(d::AbstractDict, cache)
  haskey(cache, d) && return cache[d]
  haskey(d, :tag) && haskey(raise, Symbol(d[:tag])) && return raise[Symbol(d[:tag])](d, cache)
  _raise_recursive(d::AbstractDict, cache)
end

function raise_recursive(v::BSONArray, cache)
  cache[v] = v
  applychildren!(x -> raise_recursive(x, cache), v)
end

raise_recursive(x, cache) = x

raise_recursive(x) = raise_recursive(x, IdDict())

parse(io::IO) = backrefs!(parse_doc(io))
parse(path::String) = open(parse, path)

load(x) = raise_recursive(parse(x))

function roundtrip(x)
  buf = IOBuffer()
  bson(buf, Dict(:stuff => x))
  load(seek(buf, 0))[:stuff]
end
