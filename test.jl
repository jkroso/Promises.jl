@require "." Deferred need @defer

suite("non-deferred's") do
  @test need(1) == 1
end

suite("untyped") do
  one = Deferred(()->1)
  err = Deferred(()->error("expected error"))
  @test need(one) == 1
  @test need(one) == 1
  @test_throws ErrorException need(err)
  @test_throws ErrorException need(err)
end

suite("typed") do
  one = Deferred(()->1, Int)
  err = Deferred(()->"one", Int)
  @test isa(one.value, Int)
  @test isa(err.value, Int)
  @test need(one) == 1
  @test_throws MethodError need(err)
  @test_throws ErrorException need(Deferred(()->error("boom"), Int))
end

suite("macros") do
  @test need(@defer 1) == 1
  @test_throws ErrorException need(@defer error("boom"))
  @test isa((@defer 1::Int).value, Int)
  @test need(@defer 1::Int) == 1
  @test_throws MethodError need(@defer "one"::Int)
  @test_throws ErrorException need(@defer error("one")::Int)
end
