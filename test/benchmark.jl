module Benchmark

using Profile
using BSON

chars = [x for x in '0':'z']
strings = [String([rand(chars) for _ in 1:20]) for _ in 1:20]
rstr(n::Int)::String = rand(strings)[1:n]

struct Baz
  going::String
  deeper::String
end

Baz() = Baz(rstr(20), rstr(1))

struct Bar
  level::Int64
  bazes::Vector{Baz}
end

Bar() = Bar(rand(Int64), [Baz() for _ in 1:50])

struct Foo
  agile::String
  software::String
  management::String
  consultant::String
  training::String
  projects::Vector{Bar}
end

Foo() = [Foo(rstr(5), rstr(7), rstr(17), rstr(11), rstr(13),
             [Bar() for _ in 1:2000]) for _ in 1:3]

struct Result
  elapsed::Float64
  allocated::Int64
end

const history_file = "./benchmark-history.bson"
history = if isfile(history_file)
    BSON.load(history_file)::Dict{String, Result}
else
    Dict{String, Result}()
end

macro bench(msg, ex)
  sex = "$ex"
  quote
    GC.gc()
    @info $msg
    local val, t1, bytes, gctime, memallocs = @timed $(esc(ex))
    local mb = ceil(bytes / (1024 * 1024))
    if $sex in keys(history)
      local t0 = history[$sex].elapsed
      @info $sex elapsed=t1 speedup=t0/t1 allocatedMb=mb gctime
    else
      @info $sex elapsed=t1 allocatedMb=mb gctime
    end
    history[$sex] = Result(t1, bytes)
    val
  end
end

foos = Dict(:Foo => Foo(), :Foo2 => Foo(), :Foo3 => Foo())

@bench "Roundtrip from cold start (ignore)" BSON.roundtrip(foos)

io = IOBuffer()

@bench "Bench Save BSON" bson(io, foos)
seek(io, 0)

doc = @bench "Bench Parse BSON Document" BSON.parse_doc(io)
dref_doc = deepcopy(doc)
dref_doc = @bench "Bench deref" BSON.backrefs!(dref_doc)
rfoos = @bench "Bench Raise BSON to Julia types" BSON.raise_recursive(dref_doc)

bson(history_file, history)

if get(ENV, "JULIA_PROFILE", nothing) != nothing
  minc = parse(Int64, get(ENV, "JULIA_PROFILE_MIN", "0"))
  seek(io, 0)
  GC.gc()
  @info "Profile Save BSON"
  @profile bson(io, foos)
  Profile.print(;noisefloor=2, mincount=minc)
  Profile.clear()
  seek(io, 0)

  GC.gc()
  @info "Profile Parse BSON Document"
  dict = @profile BSON.parse_doc(io)
  Profile.print(;noisefloor=2, mincount=minc, C=true)
  Profile.clear()

  GC.gc()
  @info "Profile deref"
  dict = @profile BSON.backrefs!(dict)
  Profile.print(;noisefloor=2, mincount=minc, C=true)
  Profile.clear()
  
  GC.gc()
  @info "Profile Raise BSON to Julia types"
  rfoos = @profile BSON.raise_recursive(dict)
  Profile.print(;noisefloor=2, mincount=minc)
  Profile.clear()
end

# Sanity check the results
rfoos[:Foo][1]::Foo
rfoos[:Foo][1].projects[1]::Bar
rfoos[:Foo][1].projects[1].bazes[1]::Baz

end
