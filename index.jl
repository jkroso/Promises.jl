##
# Deferred's are placeholders for a value which isn't
# yet known. Though we may know what type it will be
# hence Deferred takes the type of its eventual value
# as a parameter
#
# Julia's Tasks provide everything Deferreds provide though
# they also do a lot more which makes me feel uncomfortable
# about building abstractions on top of them which treat
# them as simple values
#
abstract Deferred{T}

##
# When you want to get the actual value of a deferred you
# just call `need` on it. It's safe to call `need` on all
# types so if in doubt...need it
#
function need(x::Any) x end

##
# Computation's are intended to enable lazy evaluation
#
type Computation{T} <: Deferred{T}
  thunk::Function
  state::Symbol
  value::T
  error::Exception
  Computation(f::Function) = new(f, :pending)
end

# Make the type parameter optional
Computation(f::Function) = Computation{Any}(f)

##
# The first time a Computation is needed it's thunk is called and the
# result is stored. Whether it return or throws. From then on it
# will just replicates this result without re-running the thunk
#
function need(d::Computation)
  d.state == :evaled && return d.value
  d.state == :failed && rethrow(d.error)
  try
    d.value = d.thunk()
    d.state = :evaled
    d.value
  catch e
    d.state = :failed
    d.error = e
    rethrow(e)
  end
end

test("need") do
  array = Computation(vcat)
  @test need(1) == 1
  @test need(array) == {}
  @test need(array) === need(array)
  @test isa(@catch(need(Computation(error))), ErrorException)
  test("with types") do
    @test need(Computation{Vector}(vcat)) == {}
    @test isa(@catch(need(Computation{Vector}(string))), MethodError)
  end
end

##
# Create a Deferred from an Expr. If `body` is annotated
# with a `Type` then create a `Deferred{Type}`
#
macro defer(body)
  if isa(body, Expr) && body.head == symbol("::")
    :(Computation{$(esc(body.args[2]))}(()-> $(esc(body.args[1]))))
  else
    :(Computation{Any}(()-> $(esc(body))))
  end
end

test("@defer") do
  @test need(@defer 1) == 1
  @test isa(@catch(need(@defer error())), ErrorException)
  @test typeof(@defer 1) == Computation{Any}
  @test typeof(@defer 1::Int) == Computation{Int}
end

##
# Values are intended to provide a way for asynchronous processes
# to communicate their result to other threads
#
type Value{T} <: Deferred{T}
  cond::Condition
  state::Symbol
  value::T
  error::Exception
  Value() = new(Condition(), :pending)
  Value(c::Condition) = new(c, :pending)
end

# Make the type optional
Value() = Value{Any}()

function need(v::Value)
  v.state == :evaled && return v.value
  v.state == :failed && rethrow(v.error)
  v.state == :needed && return wait(v.cond)
  try
    v.state = :needed
    v.value = wait(v.cond)
    v.state = :evaled
    v.value
  catch e
    v.state = :failed
    v.error = e
    rethrow(e)
  end
end

##
# Give the Promise its value
#
function Base.write(v::Value, value)
  if v.state == :pending
    v.state = :evaled
    v.value = value
  end
  notify(v.cond, value)
end

test("write") do
  result = Value()
  task = @async need(result)
  write(result, 1)
  @test need(result) == 1
  @test wait(task) == 1
end

##
# Put the Promise into a failed state
#
function Base.error(v::Value, e::Exception)
  if v.state == :pending
    v.state = :failed
    v.error = e
  end
  notify(v.cond, e; error=true)
end

test("error") do
  result = Value()
  task = @async need(result)
  error(result, ErrorException(""))
  @test isa(@catch(need(result)), ErrorException)
  @test @catch(need(result)) === @catch wait(task)
  @test task.result == result.error
  @test task.state == :failed
end
