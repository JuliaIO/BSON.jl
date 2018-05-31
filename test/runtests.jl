using BSON
using Base.Test

roundtrip_equal(x) = BSON.roundtrip(x) == x

mutable struct Foo
  x
end

@testset "BSON" begin

@testset "Primitive Types" begin
  @test roundtrip_equal(nothing)
  @test roundtrip_equal(1)
  @test roundtrip_equal(Dict(:a => 1,:b => 2))
  @test roundtrip_equal(UInt8[1,2,3])
  @test roundtrip_equal("b")
  @test roundtrip_equal([1,"b"])
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

@testset "Dicts with non-Symbol keys" begin
  d1 = Dict()
  roundtrip_equal(d1)

  d2 = Dict("a" => "b")
  roundtrip_equal(d2)

  d3 = Dict("a" => "b", "c" => "d")
  roundtrip_equal(d3)

  d4 = Dict("a" => "b", "c" => "d", "e" => "f")
  roundtrip_equal(d4)

  d5 = Dict("a" => "b", "c" => "d", "e" => 6)
  roundtrip_equal(d5)

  d6 = Dict("a" => "b", 3 => "d", "e" => "f")
  roundtrip_equal(d6)

  d7 = Dict("a" => "b", 3 => 4, "e" => "f")
  roundtrip_equal(d7)

  d8 = Dict("a" => :b)
  roundtrip_equal(d8)

  d9 = Dict("a" => 1)
  roundtrip_equal(d9)

  d10 = Dict(1 => "a")
  roundtrip_equal(d10)

  d11 = Dict(:a => :a)
  roundtrip_equal(d11)

  d12 = Dict(:a => "a")
  roundtrip_equal(d12)

  d13 = Dict(:a => 1)
  roundtrip_equal(d13)

  d14 = Dict("a" => :a)
  roundtrip_equal(d14)

  d15 = Dict("a" => "a")
  roundtrip_equal(d15)

  d16 = Dict("a" => 1)
  roundtrip_equal(d16)

  d17 = Dict(1 => :a)
  roundtrip_equal(d17)

  d18 = Dict(1 => "a")
  roundtrip_equal(d18)

  d19 = Dict(1 => 1)
  roundtrip_equal(d19)
end

end
