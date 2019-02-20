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

function _raise_recursive(d::AbstractDict, cache, init)
  if haskey(d, :tag) && haskey(tags, Symbol(d[:tag]))
    if Symbol(d[:tag]) in (:ref, :datatype)
      cache[d] = tags[Symbol(d[:tag])](applychildren!(x -> raise_recursive(x, cache, init), d), init)
    else
      cache[d] = tags[Symbol(d[:tag])](applychildren!(x -> raise_recursive(x, cache, init), d))
    end
  else
    cache[d] = d
    applychildren!(x -> raise_recursive(x, cache, init), d)
  end
end

function raise_recursive(d::AbstractDict, cache, init)
  haskey(cache, d) && return cache[d]
  haskey(d, :tag) && haskey(raise, Symbol(d[:tag])) && return raise[Symbol(d[:tag])](d, cache, init)
  _raise_recursive(d::AbstractDict, cache, init)
end

function raise_recursive(v::BSONArray, cache, init)
  cache[v] = v
  applychildren!(x -> raise_recursive(x, cache, init), v)
end

raise_recursive(x, cache, init) = x

raise_recursive(x, init) = raise_recursive(x, IdDict(), init)

parse(io::IO) = backrefs!(parse_doc(io))
parse(path::String) = open(parse, path)

load(x, init=Main) = raise_recursive(parse(x), init)

function roundtrip(x)
  buf = IOBuffer()
  bson(buf, Dict(:data => x))
  load(seek(buf, 0))[:data]
end
