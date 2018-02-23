jtype(tag) =
  tag == null ? Void :
  tag == boolean ? Bool :
  tag == int32 ? Int32 :
  tag == int64 ? Int64 :
  tag == double ? Float64 :
  error("Unsupported tag $tag")

function parse_cstr(io::IO)
  buf = IOBuffer()
  while (ch = read(io, UInt8)) != 0x00
    write(buf, ch)
  end
  return String(read(seek(buf, 0)))
end

function parse_tag(io::IO, tag)
  if tag == null
    nothing
  elseif tag == document
    parse_doc(io)
  elseif tag == array
    Any[map(x->x[2], parse_pairs(io))...]
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

function parse_pairs(io::IO)
  len = read(io, Int32)
  ps = []
  while (tag = read(io, BSONType)) ≠ eof
    k = Symbol(parse_cstr(io))
    v = parse_tag(io::IO, tag)
    push!(ps, k => v)
  end
  return ps
end

parse_doc(io::IO) = BSONDict(parse_pairs(io))

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

function _raise_recursive(d::Associative, cache)
  if haskey(d, :tag) && haskey(tags, Symbol(d[:tag]))
    tags[Symbol(d[:tag])](applychildren!(x -> raise_recursive(x, cache), d))
  else
    cache[d] = d
    applychildren!(x -> raise_recursive(x, cache), d)
  end
end

function raise_recursive(d::Associative, cache)
  haskey(cache, d) && return cache[d]
  haskey(d, :tag) && haskey(raise, Symbol(d[:tag])) && return raise[Symbol(d[:tag])](d, cache)
  _raise_recursive(d::Associative, cache)
end

function raise_recursive(v::BSONArray, cache)
  cache[v] = v
  applychildren!(x -> raise_recursive(x, cache), v)
end

raise_recursive(x, cache) = x

raise_recursive(x) = raise_recursive(x, ObjectIdDict())

parse(io::IO) = raise_recursive(backrefs!(parse_doc(io)))
parse(path::String) = open(parse, path)

function roundtrip(x)
  buf = IOBuffer()
  bson(buf, Dict(:data => x))
  parse(seek(buf, 0))[:data]
end
