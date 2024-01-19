using BSON
using Test

function roundtrip_equal(x)
  y = BSON.roundtrip(x)
  typeof(y) == typeof(x) && x == y
end

# avoid hitting bug where
# Dict{Symbol,T} -> Dict{Symbol,Any}
function roundtrip_equal(x::Dict{Symbol})
  y = BSON.roundtrip(x)
  y isa Dict{Symbol} && y == x
end

mutable struct Foo
  x
end

struct T{A}
  x::A
end

struct S end

struct Bar
  a
  Bar() = new()
end

mutable struct Baz
  x
  y
  z
  Baz() = new()
end

function is_field_equal(a, b, field::Symbol)
  !isdefined(a, field) && return !isdefined(b, field)
  !isdefined(b, field) && return false
  return getfield(a, field) == getfield(b, field)
end

function Base.:(==)(a::Baz, b::Baz)
  return is_field_equal(a, b, :x) &&
         is_field_equal(a, b, :y) &&
         is_field_equal(a, b, :z)
end

module A
  using DataFrames, BSON
  d = DataFrame(a = 1:10, b = rand(10))
  a = DataFrames.PooledArrays.PooledArray(["a" "b"; "c" "d"])
  bson("test_25_dataframe.bson", Dict(:d=>d))
  bson("test_26_module_in_module.bson", Dict(:a=>a))
end

struct NoInit
  x::Int

  NoInit() = new()
end

@testset "BSON" begin

if VERSION >= v"1.8"
  include("const_fields.jl")
end

@testset "Primitive Types" begin
  @test roundtrip_equal(nothing)
  @test roundtrip_equal(1)
  @test roundtrip_equal(Dict(:a => 1,:b => 2))
  @test roundtrip_equal(UInt8[1,2,3])
  @test roundtrip_equal("b")
  @test roundtrip_equal([1,"b"])
  @test roundtrip_equal(Tuple)
  @test roundtrip_equal(Tuple{Int, Float64})
  @test roundtrip_equal(Vararg{Any})
end

@testset "Undefined References" begin
  # from Issue #3
  d = Dict(:a => 1, :b => Dict(:c => 3, :d => Dict("e" => 5)))
  @test roundtrip_equal(d)

  # from Issue #43
  x = Array{String, 1}(undef, 5)
  x[1] = "a"
  x[4] = "d"
  @test_broken roundtrip_equal(Dict(:x => x))

  @test roundtrip_equal(Bar())

  o = Baz()
  o.y = 1
  @test roundtrip_equal(o)
end

@testset "Complex Types" begin
  @test roundtrip_equal(:foo)
  @test roundtrip_equal(Int64)
  @test roundtrip_equal(Complex{Float32})
  @test roundtrip_equal(Complex)
  @test roundtrip_equal(Array)
  @test roundtrip_equal([1,2,3])
  @test roundtrip_equal(rand(2,3))
  @test roundtrip_equal(Array{Real}(rand(2,3)))
  @test roundtrip_equal(1+2im)
  @test roundtrip_equal(Nothing[])
  @test roundtrip_equal(S[])
  @test roundtrip_equal(fill(nothing, (3,2)))
  @test roundtrip_equal(fill(S(), (1,3)))
  @test roundtrip_equal(Set([1,2,3]))
  @test roundtrip_equal(Dict("a"=>1))
  @test roundtrip_equal(T(()))
  @test roundtrip_equal(Dict(:a => 1,:b => [1, 2]))
  @test roundtrip_equal(Dict(:a => [1+2im, 3+4im], :b => "Hello, World!"))
end

@testset "Circular References" begin
  x = [1,2,3]
  (x1, x2) = BSON.roundtrip((x,x))
  @test x1 == x
  @test x1 === x2

  d = Dict{Symbol,Any}(:a=>1)
  d[:d] = d
  d = BSON.roundtrip(d)
  @test d[:a] == 1
  @test d[:d] === d

  x = Foo(1)
  x.x = x
  x = BSON.roundtrip(x)
  @test x.x === x
end

@testset "Undefined References" begin
  # from Issue #3
  d = Dict(:a => 1, :b => Dict(:c => 3, :d => Dict("e" => 5)))
  @test roundtrip_equal(d)

  # from Issue #43
  x = Array{String, 1}(undef, 5)
  x[1] = "a"
  x[4] = "d"
  @test_broken roundtrip_equal(Dict(:x => x))

  x = NoInit()
  @test roundtrip_equal(x)
end

@testset "Anonymous Functions" begin
  f = x -> x+1
  f2 = BSON.roundtrip(f)
  @test f2(5) == f(5)
  @test typeof(f2) !== typeof(f)

  chicken_tikka_masala(y) = x -> x+y
  f = chicken_tikka_masala(5)
  f2 = BSON.roundtrip(f)
  @test f2(6) == f(6)
  @test typeof(f2) !== typeof(f)
end

@testset "Int Literals in Type Params #41" begin
  @test BSON.constructtype(Array, (Any, Int32(1))) === Vector{Any}
  @test BSON.constructtype(Array, (Any, Int64(1))) === Vector{Any}

  @test BSON.load(joinpath(@__DIR__, "test_41_from_32bit.bson")) == Dict(:obj => Dict("name"=>[0x01, 0x02]))
  @test BSON.load(joinpath(@__DIR__, "test_41_from_64bit.bson")) == Dict(:obj => Dict("name"=>[0x01, 0x02]))
end

@testset "MultiDims Arrays saved on 64-bit" begin
  @test BSON.load(joinpath(@__DIR__, "test_MultiDimsArray_from_64bit.bson"))[:a] == ones(Float32, 2, 2)
end

@testset "Namespace other than Main #25" begin
  @test BSON.load("test_25_dataframe.bson", A)[:d] == A.d
  rm("test_25_dataframe.bson")
end

@testset "Module with module import" begin
  @test BSON.load(joinpath(@__DIR__, "test_26_module_in_module.bson"))[:a] == A.a
  rm("test_26_module_in_module.bson")
end

end
