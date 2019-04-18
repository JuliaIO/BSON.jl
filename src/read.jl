jtype(tag::BSONType)::DataType =
  tag == null ? Nothing :
  tag == boolean ? Bool :
  tag == int32 ? Int32 :
  tag == int64 ? Int64 :
  tag == double ? Float64 :
  error("Unsupported tag $tag")

parse_cstr(io::IOT) where {IOT <: IO} =
  Base.readuntil_string(io, 0x0, false)

parse_cstr_unsafe(io::IO)::Vector{UInt8} = readuntil(io, 0x0, keep=false)

# Not really unsafe, but we do access internal fields directly. Avoids
# allocating a temporary string/vector.
function parse_cstr_unsafe(io::IOBuffer)::SubArray{UInt8, 1}
  st = io.ptr

  while read(io, UInt8) ≠ 0x0
  end

  view(io.data, st:(io.ptr - 2))
end

function parse_tag(io::IOT, tag::BSONType) where {IOT <: IO}
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

function parse_array(io::IOT)::BSONArray where {IOT <: IO}
  len = read(io, Int32)
  ps = BSONArray()

  while (tag = read(io, BSONType)) ≠ eof
    # Note that arrays are dicts with the index as the key
    while read(io, UInt8) != 0x00
      nothing
    end
    push!(ps, parse_tag(io::IOT, tag))
  end

  ps
end

const SEEN_REF = 1
const SEEN_DATA = 1 << 1
const SEEN_TYPE = 1 << 2
const SEEN_TYPENAME = 1 << 3
const SEEN_TAG = 1 << 4
const SEEN_NAME = 1 << 5
const SEEN_PARAMS = 1 << 6
const SEEN_PATH = 1 << 7
const SEEN_OTHER = 1 << 8
const SEEN_SIZE = 1 << 9
const SEEN_VAR = 1 << 10
const SEEN_BODY = 1 << 11

const SEEN_TAG_STRUCT = 1 << 12
const SEEN_TAG_BACKREF = 1 << 13
const SEEN_TAG_DATATYPE = 1 << 14
const SEEN_TAG_SYMBOL = 1 << 15
const SEEN_TAG_TUPLE = 1 << 16
const SEEN_TAG_SVEC = 1 << 17
const SEEN_TAG_UNION = 1 << 18
const SEEN_TAG_ANON = 1 << 19
const SEEN_TAG_REF = 1 << 20
const SEEN_TAG_ARRAY = 1 << 21
const SEEN_TAG_UNIONALL = 1 << 22

function classify_doc_tag(tag::AbstractVector{UInt8})::Union{Int64, String}
  if tag == b"backref"
    SEEN_TAG_BACKREF
  elseif tag == b"struct"
    SEEN_TAG_STRUCT
  elseif tag == b"datatype"
    SEEN_TAG_DATATYPE
  elseif tag == b"symbol"
    SEEN_TAG_SYMBOL
  elseif tag == b"tuple"
    SEEN_TAG_TUPLE
  elseif tag == b"svec"
    SEEN_TAG_SVEC
  elseif tag == b"jl_bottom_type"
    SEEN_TAG_UNION
  elseif tag == b"jl_anonymous"
    SEEN_TAG_ANON
  elseif tag == b"ref"
    SEEN_TAG_REF
  elseif tag == b"array"
    SEEN_TAG_ARRAY
  elseif tag == b"unionall"
    SEEN_TAG_UNIONALL
  else
    String(tag)
  end
end

function parse_doc_tag(io::IO)::Union{Int64, String}
  len = read(io, Int32) - 1
  tag = read(io, len)
  eof = read(io, 1)

  classify_doc_tag(tag)
end

function parse_doc_tag(io::IOBuffer)::Union{Int64, String}
  len = read(io, Int32) - 1
  spos = position(io)
  tag = parse_cstr_unsafe(io)

  if length(tag) == len
    classify_doc_tag(tag)
  else
    seek(io, spos)
    s = String(read(io, len))
    eof = read(io, 1)
    s
  end
end

function parse_doc(io::IOT) where {IOT <: IO}
  #@debug "parse_doc"
  len = read(io, Int32)

  seen::Int64 = 0
  see(it::Int64) = seen = seen | it
  saw(it::Int64)::Bool = seen & it != 0
  only_saw(it::Int64)::Bool = seen == it

  # First try to parse this document as a Tagged* intermediate type. Note that
  # both nothing and missing are valid data values.
  local tref, tdata, ttype, ttypename, ttag, tname, tparams, tpath, tsize, tvar, tbody
  local other
  local k::AbstractVector{UInt8}

  for _ in 1:5
    if (tag = read(io, BSONType)) == eof
      break
    end
    k = parse_cstr_unsafe(io)
    #@debug "Read key" String(k)

    if k == b"ref"
      see(SEEN_REF)
      tref = parse_tag(io, tag)
    elseif k == b"data"
      see(SEEN_DATA)
      tdata = parse_tag(io, tag)
      #@debug "Read" tdata
    elseif k == b"type"
      see(SEEN_TYPE)
      ttype = parse_tag(io, tag)
      #@debug "Read" ttype
    elseif k == b"typename"
      see(SEEN_TYPENAME)
      ttypename = parse_tag(io, tag)
      #@debug "Read" ttype
    elseif k == b"tag"
      see(SEEN_TAG)
      if tag == string
        if (dtag = parse_doc_tag(io)) isa Int64
          see(dtag)
        else
          ttag = dtag
          #@debug "Read" dtag
        end
      else
        ttag = parse_tag(io, tag)
        #@debug "Read" ttag
      end
    elseif k == b"name"
      see(SEEN_NAME)
      tname = parse_tag(io, tag)
      #@debug "Read" tname
    elseif k == b"params"
      see(SEEN_PARAMS)
      tparams = parse_tag(io, tag)
      #@debug "Read" tparams
    elseif k == b"path"
      see(SEEN_PATH)
      tpath = parse_tag(io, tag)
    elseif k == b"size"
      see(SEEN_SIZE)
      tsize = parse_tag(io, tag)
    elseif k == b"var"
      see(SEEN_VAR)
      tvar = parse_tag(io, tag)
    elseif k == b"body"
      see(SEEN_BODY)
      tbody = parse_tag(io, tag)
    else
      see(SEEN_OTHER)
      other = parse_tag(io, tag)
      #@debug "Read" other
      break
    end
  end

  if saw(SEEN_OTHER)
    nothing
  elseif only_saw(SEEN_TAG | SEEN_REF | SEEN_TAG_BACKREF)
    return TaggedBackref(tref)
  elseif only_saw(SEEN_TAG | SEEN_TYPE | SEEN_DATA | SEEN_TAG_STRUCT)
    return TaggedStruct(ttype, tdata)
  elseif only_saw(SEEN_TAG | SEEN_NAME | SEEN_PARAMS | SEEN_TAG_DATATYPE)
    return TaggedType(tname, tparams)
  elseif only_saw(SEEN_TAG | SEEN_NAME | SEEN_TAG_SYMBOL)
    return Symbol(tname)
  elseif only_saw(SEEN_TAG | SEEN_DATA | SEEN_TAG_TUPLE)
    return TaggedTuple(tdata)
  elseif only_saw(SEEN_TAG | SEEN_DATA | SEEN_TAG_SVEC)
    return TaggedSvec(tdata)
  elseif only_saw(SEEN_TAG | SEEN_TAG_UNION)
    return Union{}
  elseif only_saw(SEEN_TAG | SEEN_TYPENAME | SEEN_PARAMS | SEEN_TAG_ANON)
    return TaggedAnonymous(ttypename, tparams)
  elseif only_saw(SEEN_TAG | SEEN_PATH | SEEN_TAG_REF)
    return TaggedRef(tpath)
  elseif only_saw(SEEN_TAG | SEEN_TYPE | SEEN_SIZE | SEEN_DATA | SEEN_TAG_ARRAY)
    return TaggedArray(ttype, tsize, tdata)
  elseif only_saw(SEEN_TAG | SEEN_VAR | SEEN_BODY | SEEN_TAG_UNIONALL)
    return TaggedUnionall(tvar, tbody)
  end

  # It doesn't look like a Tagged*, so just allocate a Dict
  dic = BSONDict()
  saw(SEEN_REF) && (dic[:ref] = tref)
  saw(SEEN_DATA) && (dic[:data] = tdata)
  saw(SEEN_TYPE) && (dic[:type] = ttype)
  saw(SEEN_TYPENAME) && (dic[:typename] = ttypename)
  saw(SEEN_TAG)  && (dic[:tag] = ttag)
  saw(SEEN_NAME) && (dic[:name] = tname)
  saw(SEEN_PARAMS) && (dic[:params] = tparams)
  saw(SEEN_PATH) && (dic[:path] = tpath)
  saw(SEEN_SIZE) && (dic[:size] = tsize)
  saw(SEEN_VAR) && (dic[:var] = tvar)
  saw(SEEN_BODY) && (dic[:body] = tbody)
  saw(SEEN_OTHER) && (dic[Symbol(String(k))] = other)

  if tag == eof
    #@debug "Short" dic
    return dic
  end

  while (tag = read(io, BSONType)) ≠ eof
    local k = Symbol(parse_cstr(io))
    #@debug "Read key" k
    dic[k] = parse_tag(io::IOT, tag)
  end

  #@debug "Long" dic
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

raise_recursive(d::BSONDict, cache::IdDict{Any, Any}) = prememoise(d, cache) do d
  haskey(d, :tag) && error("Unknown tag: $(d[:tag])")
  applychildren!(x -> raise_recursive(x, cache), d)
end

raise_recursive(v::BSONArray, cache::IdDict{Any, Any}) = prememoise(v, cache) do u
  applyvec!(x -> raise_recursive(x, cache), u)
end

raise_recursive(x::Union{Primitive, Type{Union{}}, Symbol}, ::IdDict{Any, Any}) = x

parse(io::IOT) where {IOT <: IO} = backrefs!(parse_doc(io))
parse(path::String) = open(parse, path)

load(x) = raise_recursive(parse(x), IdDict{Any, Any}())

function roundtrip(x)
  buf = IOBuffer()
  bson(buf, Dict(:stuff => x))
  load(seek(buf, 0))[:stuff]
end

function halftrip(x)
  buf = IOBuffer()
  bson(buf, Dict(:stuff => x))
  parse_doc(seek(buf, 0))
end
