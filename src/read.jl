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

const SEEN_REF = 1
const SEEN_DATA = 2
const SEEN_TYPE = 4
const SEEN_TAG = 8
const SEEN_NAME = 16
const SEEN_PARAMS = 32
const SEEN_OTHER = 64

function parse_doc(io::IO)::Union{BSONDict, Tagged}
  len = read(io, Int32)

  seen_state::Int64 = 0
  see(it::Int64) = seen_state = seen_state | it
  saw(it::Int64)::Bool = seen_state & it > 0

  # First try to parse this document as a TaggedStruct. Note that both nothing
  # and missing are valid data values.
  local tref, tdata, ttype, ttag, tname, tparams, other, k

  for _ in 1:4
    if (tag = read(io, BSONType)) == eof
      break
    end
    k = parse_cstr(io)
    @debug "Read key" k

    if k == "ref"
      see(SEEN_REF)
      tref = parse_tag(io, tag)
    elseif k == "data"
      see(SEEN_DATA)
      tdata = parse_tag(io, tag)
      @debug "Read" tdata
    elseif k == "type"
      see(SEEN_TYPE)
      ttype = parse_tag(io, tag)
      @debug "Read" ttype
    elseif k == "tag"
      see(SEEN_TAG)
      ttag = parse_tag(io, tag)
      @debug "Read" ttag
    elseif k == "name"
      see(SEEN_NAME)
      tname = parse_tag(io, tag)
      @debug "Read" tname
    elseif k == "params"
      see(SEEN_PARAMS)
      tparams = parse_tag(io, tag)
      @debug "Read" tparams
    else
      see(SEEN_OTHER)
      other = parse_tag(io, tag)
      @debug "Read" other
      break
    end
  end

  if saw(SEEN_OTHER)
    nothing
  elseif saw(SEEN_TAG | SEEN_REF) && ttag == "backref"
    return TaggedBackref(tref)
  elseif saw(SEEN_TAG | SEEN_TYPE | SEEN_DATA) && ttag == "struct"
    return TaggedStruct(ttype, tdata)
  elseif saw(SEEN_TAG | SEEN_NAME | SEEN_PARAMS) && ttag == "datatype"
    return TaggedType(tname, tparams)
  end

  # It doesn't look like a Tagged*, so just allocate a Dict
  dic = BSONDict()
  saw(SEEN_REF) && (dic[:ref] = tref)
  saw(SEEN_DATA) && (dic[:data] = tdata)
  saw(SEEN_TYPE) && (dic[:type] = ttype)
  saw(SEEN_TAG)  && (dic[:tag] = ttag)
  saw(SEEN_NAME) && (dic[:name] = tname)
  saw(SEEN_PARAMS) && (dic[:params] = tparams)
  saw(SEEN_OTHER) && (dic[Symbol(k)] = other)

  if tag == eof
    @debug "Short" dic
    return dic
  end

  while (tag = read(io, BSONType)) ≠ eof
    local k = Symbol(parse_cstr(io))
    @debug "Read key" k
    dic[k] = parse_tag(io::IO, tag)
  end

  @debug "Long" dic
  dic
end

backrefs!(x, refs) = applychildren!(x -> backrefs!(x, refs), x)

backrefs!(dict::BSONDict, refs) =
  get(dict, :tag, "") == "backref" ? refs[dict[:ref]] :
  invoke(backrefs!, Tuple{Any,Any}, dict, refs)

backrefs!(bref::TaggedBackref, refs) = refs[bref.ref]

function backrefs!(dict)
  haskey(dict, :_backrefs) || return dict
  refs = dict[:_backrefs]
  backrefs!(dict, refs)
  delete!(dict, :_backrefs)
  return dict
end

const tags = Dict{Symbol,Function}()

const raise = Dict{Symbol,Function}()

function _raise_recursive(d::BSONDict, cache::IdDict{Any, Any})
  if haskey(d, :tag) && haskey(tags, Symbol(d[:tag]))
    cache[d] = tags[Symbol(d[:tag])](applychildren!(x -> raise_recursive(x, cache), d))
  else
    cache[d] = d
    applychildren!(x -> raise_recursive(x, cache), d)
  end
end

function raise_recursive(d::BSONDict, cache::IdDict{Any, Any})
  haskey(cache, d) && return cache[d]
  haskey(d, :tag) && haskey(raise, Symbol(d[:tag])) && return raise[Symbol(d[:tag])](d, cache)
  _raise_recursive(d::AbstractDict, cache)
end

function raise_recursive(v::BSONArray, cache::IdDict{Any, Any})
  cache[v] = v
  applychildren!(x -> raise_recursive(x, cache), v)
end

raise_recursive(x, ::IdDict{Any, Any}) = x

raise_recursive(x) = raise_recursive(x, IdDict{Any, Any}())

parse(io::IO) = backrefs!(parse_doc(io))
parse(path::String) = open(parse, path)

load(x) = raise_recursive(parse(x))

function roundtrip(x)
  buf = IOBuffer()
  bson(buf, Dict(:stuff => x))
  load(seek(buf, 0))[:stuff]
end
