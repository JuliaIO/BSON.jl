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

function parse_doc(io::IO)::BSONDict
  len = read(io, Int32)
  dic = BSONDict()

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
  bson(buf, Dict(:data => x))
  load(seek(buf, 0))[:data]
end
