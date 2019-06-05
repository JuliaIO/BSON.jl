using BSON
using Test

roundtrip_equal(x) = BSON.roundtrip(x) == x

mutable struct Foo
  x
end

struct T{A}
  x::A
end

struct S end

@testset "BSON" begin

@testset "Primitive Types" begin
  @test roundtrip_equal(nothing)
  @test roundtrip_equal(1)
  @test roundtrip_equal(Dict(:a => 1,:b => 2))
  @test roundtrip_equal(UInt8[1,2,3])
  @test roundtrip_equal("b")
  @test roundtrip_equal([1,"b"])
  @test roundtrip_equal(Tuple)
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

end
