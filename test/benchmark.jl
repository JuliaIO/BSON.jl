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

Foo() = Foo(rstr(5), rstr(7), rstr(17), rstr(11), rstr(13), [Bar() for _ in 1:2000])

foos = Dict(:Foo => Foo())
io = IOBuffer()

@info "Bench Save BSON"
@timev bson(io, foos)
seek(io, 0)

@info "Bench Parse BSON"
dict = @timev BSON.parse(io)

@info "Bench Raise BSON to Julia types"
@timev BSON.raise_recursive(dict)

@info "Profile Save BSON"
@profile bson(io, foos)
Profile.print(;noisefloor=2)
Profile.clear()
seek(io, 0)

@info "Profile Parse BSON"
dict = @profile BSON.parse(io)
Profile.print(;noisefloor=2)
Profile.clear()

@info "Profile Raise BSON to Julia types"
rfoos = @profile BSON.raise_recursive(dict)
Profile.print(;noisefloor=2)
Profile.clear()

# Sanity check the results
rfoos[:Foo]::Foo
rfoos[:Foo].projects[1]::Bar
rfoos[:Foo].projects[1].bazes[1]::Baz

end
