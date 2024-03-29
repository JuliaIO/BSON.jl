# BSON

[![CI](https://github.com/JuliaIO/BSON.jl/actions/workflows/ci.yml/badge.svg)](https://github.com/JuliaIO/BSON.jl/actions/workflows/ci.yml)

BSON.jl is a Julia package for working with the [Binary JSON](http://bsonspec.org/) serialisation format. It can be used as a general store for Julia data structures, with the following features:

* **Lightweight and ubiquitous**, with a simple JSON-like data model and clients in many languages.
* **Efficient** for binary data (eg. arrays of floats).
* **Flexible** enough to handle anything you throw at it – closures, custom types, circular data structures, etc.
* **Backwards compatible**, so that if data layout changes old files will still load.

```julia
julia> using BSON

julia> bson("test.bson", Dict(:a => [1+2im, 3+4im], :b => "Hello, World!"))

julia> BSON.load("test.bson")
Dict{Symbol,Any} with 2 entries:
  :a => Complex{Int64}[1+2im, 3+4im]
  :b => "Hello, World!"
```

(Note that the top-level object in BSON is always a `Dict{Symbol,Any}`).

> ⚠️ **Warning**: Loading BSON files is not safe from malicious or erroneously constructed data. Loading BSON files can cause arbitrary code to execute on your machine. Do not load files from unknown or untrusted sources.

There a few utility methods for working with BSON files.

```julia
julia> using BSON

julia> bson("test.bson", a = 1, b = 2)

julia> BSON.load("test.bson")
Dict{Symbol,Any} with 2 entries:
  :a => 1
  :b => 2

julia> using BSON: @save, @load

julia> a, b = 1, 2
(1, 2)

julia> @save "test.bson" a b # Same as above

julia> @load "test.bson" a b # Loads `a` and `b` back into the workspace
```

For external files you can use `BSON.parse` to load raw BSON data structures
without any Julia-specific interpretation. In basic cases, this will look that
same, but Julia-specific types will be stored in a more complex format.

```julia
julia> BSON.parse("test.bson")
Dict{Symbol,Any} with 2 entries:
  :a => 1
  :b => 2

julia> BSON.parse("test.bson")[:data]
Dict{Symbol,Any} with 4 entries:
  :tag  => "array"
  :type => Dict(:tag=>"datatype",:params=>Any[],:name=>["Core","Int64"])
  :size => [3]
  :data => UInt8[0x01, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x02, 0x00  …  ]
```

This is also how the data will appear to readers in other languages, should you
wish to move data outside of Julia.

## Notes

Below is some semi-official documentation on more advanced usage.

### Loading custom data types within modules

For packages that use BSON.jl to load data, just writing `BSON.load("mydata.bson")` will not work with custom data types. Here's a simple example of that for DataFrames.jl:
```julia
module A
  using DataFrames, BSON
  d = DataFrame(a = 1:10, b = 5:14)
  bson("data.bson", Dict(:d=>d))
  d2 = BSON.load("data.bson") # this will throw an error
end
```
In these cases, you can specify the namespace under which to resolve types like so:
```julia
d2 = BSON.load("data.bson", @__MODULE__)
```
This will use the current module's namespace when loading the data. You could also pass any module name as the second argument (though almost all cases will use `@__MODULE__`). By default, the namespace is `Main` (i.e. the REPL).
