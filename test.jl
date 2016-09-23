@require "." @thread @defer need Deferred Result

testset("need") do
  array = Deferred(vcat)
  @test need(1) == 1
  @test need(array) == vcat()
  @test need(array) === need(array)
  @test isa(@catch(need(Deferred(error))), ErrorException)
  testset("with types") do
    @test need(Deferred{Vector}(vcat)) == vcat()
    @test isa(@catch(need(Deferred{Vector}(string))), MethodError)
  end
end

testset("@defer") do
  @test need(@defer 1) == 1
  @test isa(@catch(need(@defer error())), ErrorException)
  @test typeof(@defer 1) == Deferred{Any}
  @test typeof(@defer 1::Int) == Deferred{Int}
end

testset("@thread") do
  @test need(@thread 1) == 1
  @test isa(@catch(need(@thread error())), ErrorException)
  @test typeof(@thread 1) == Result{Any}
  @test typeof(@thread 1::Int) == Result{Int}
end