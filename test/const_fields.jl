@testset "Immutable Fields" begin
  mutable struct ConstFields
    a::Int
    const b::Vector{Float64}
  end

  a = ConstFields(1, [1.])
  b = BSON.roundtrip(a)
  @test typeof(a) == typeof(b)
  map(fieldnames(ConstFields)) do f
    @test getproperty(a, f) == getproperty(b, f)
  end
end
