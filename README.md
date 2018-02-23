# BSON

[![Build Status](https://travis-ci.org/MikeInnes/BSON.jl.svg?branch=master)](https://travis-ci.org/MikeInnes/BSON.jl)

BSON.jl is a Julia package for working with the [Binary JSON](http://bsonspec.org/) serialisation format. It can be used as a general store for Julia data structures, with the following features:

* **Lightweight and ubiquitous**, with a simple JSON-like data model and clients in many languages.
* **Efficient** for binary data (eg. arrays of floats).
* **Flexible** enough to handle anything you throw at it – custom types, circular data structures, etc.
* **Backwards compatible**, so that if data layout changes old files will still load.

```julia
julia> using BSON

julia> bson("test.bson", Dict(:a => [1+2im, 3+4im], :b => "Hello, World!"))

julia> BSON.parse("test.bson")
Dict{Symbol,Any} with 2 entries:
  :a => Complex{Int64}[1+2im, 3+4im]
  :b => "Hello, World!"
```
