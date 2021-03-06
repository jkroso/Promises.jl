@use "github.com/jkroso/Rutherford.jl/test.jl" testset @test @catch
@use "." @thread @defer need Deferred Result Future Promise

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

@test convert(Promise, 1)|>need == 1

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

testset("Future") do
  f = Future()
  put!(f, 1)
  @test isa(@catch(put!(f, 2)), ErrorException)
  @test need(f) ≡ 1
  f = Future()
  e = ErrorException("boom")
  error(f, e)
  @test isa(@catch(put!(f, e)), ErrorException)
  @test @catch(need(f)) ≡ e
end
