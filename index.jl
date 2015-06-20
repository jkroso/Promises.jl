abstract Promise{T}

type Deferred{T} <: Promise{T}
  fn::Function
  state::Symbol
  value::T
  error::Exception
  Deferred(f::Function) = new(f, :pending)
end

Deferred(f::Function) = Deferred{Any}(f)

##
# Evaluate the value
#
function need(x::Any) x end
function need(d::Deferred)
  d.state == :evaled && return d.value
  d.state == :failed && rethrow(d.error)
  try
    d.value = d.fn()
    d.state = :evaled
    d.value
  catch e
    d.state = :failed
    d.error = e
    rethrow(e)
  end
end

test("need") do
  array = Deferred(vcat)
  @test need(1) == 1
  @test need(array) == {}
  @test need(array) === need(array)
  @test isa(@catch(need(Deferred(error))), ErrorException)
  test("with types") do
    @test need(Deferred{Vector}(vcat)) == {}
    @test isa(@catch(need(Deferred{Vector}(string))), MethodError)
  end
end

##
# Create a Deferred from an Expr. If `body` is annotated
# with a `Type` then create a `Deferred{Type}`
#
macro defer(body)
  if isa(body, Expr) && body.head == symbol("::")
    :(Deferred{$(esc(body.args[2]))}(() -> $(esc(body.args[1]))))
  else
    :(Deferred{Any}(() -> $(esc(body))))
  end
end

test("@defer") do
  @test need(@defer 1) == 1
  @test isa(@catch(need(@defer error())), ErrorException)
  @test typeof(@defer 1) == Deferred{Any}
  @test typeof(@defer 1::Int) == Deferred{Int}
end

##
# Async Promises are capable of pausing the current_task
# thread while waiting for another thread to complete if
# it needs to
#
type Async{T} <: Promise{T}
  cond::Condition
  state::Symbol
  value::T
  error::Exception
  Async() = new(Condition(), :pending)
  Async(c::Condition) = new(c, :pending)
end

Async() = Async{Any}()

function need(promise::Async)
  promise.state == :evaled && return promise.value
  promise.state == :failed && rethrow(promise.error)
  promise.state == :needed && wait(promise.cond)
  try
    promise.state = :needed
    promise.value = wait(promise.cond)
    promise.state = :evaled
    promise.value
  catch e
    promise.state = :failed
    promise.error = e
    rethrow(e)
  end
end

##
# Give the Promise its value
#
function Base.write(promise::Async, value)
  if promise.state == :pending
    promise.state = :evaled
    promise.value = value
  end
  notify(promise.cond, value)
end

test("write") do
  promise = Async()
  task = @async need(promise)
  write(promise, 1)
  @test need(promise) == 1
  @test wait(task) == 1
end

##
# Put the Promise into a failed state
#
function Base.error(promise::Async, e::Exception)
  if promise.state == :pending
    promise.state = :failed
    promise.error = e
  end
  notify(promise.cond, e; error=true)
end

test("error") do
  promise = Async()
  task = @async need(promise)
  error(promise, ErrorException(""))
  @test isa(@catch(need(promise)), ErrorException)
  @test @catch(need(promise)) === @catch wait(task)
  @test task.result == promise.error
  @test task.state == :failed
end
