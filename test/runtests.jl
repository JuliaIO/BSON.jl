using BSON
using Base.Test

cd(@__DIR__)

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
  @test roundtrip_equal(Int64)
  @test roundtrip_equal(Complex{Float32})
  @test roundtrip_equal([1,2,3])
  @test roundtrip_equal(rand(2,3))
  @test roundtrip_equal(Array{Real}(rand(2,3)))
  @test roundtrip_equal(1+2im)
end

@testset "Circular References" begin
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

end
