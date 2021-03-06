@use "github.com/jkroso/Prospects.jl" need
using Distributed

"""
A Promise is a placeholder for a value which isn't yet known.
Though we may know what type it will be hence Promises take
the type of their eventual value as a parameter
"""
abstract type Promise{T} end

"A Promise can be in one of the following states"
@enum State pending needed evaled failed

Base.isready(p::Promise) = p.state > needed

"Deferred's enable lazy evaluation"
mutable struct Deferred{T} <: Promise{T}
  lock::ReentrantLock
  thunk::Function
  state::State
  value::Union{T,Exception}
  Deferred{T}(f::Function) where T = new(ReentrantLock(), f, pending)
  Deferred{T}(s::State, value) where T = new(ReentrantLock(), identity, s, value)
end

Base.convert(::Type{Promise}, value::T) where T = Deferred{T}(evaled, value)
# Prevent double wrapping
Base.convert(::Type{Promise}, value::Promise) = value

"Make the type parameter optional"
Deferred(f::Function) = Deferred{Any}(f)

"""
The first time a Deferred is needed it's thunk is called and the
result is stored. Whether it returns or throws. From then on it
will just replicate this result without calling the thunk
"""
function need(d::Deferred)
  lock(d.lock) do
    d.state ≡ evaled && return d.value
    d.state ≡ failed && throw(d.value)
    try
      d.value = d.thunk()
      d.state = evaled
      d.value
    catch e
      d.state = failed
      d.value = e
      throw(e)
    end
  end
end

"""
Create a Deferred from an Expr. If `body` is annotated with a
type `x` then create a `Deferred{x}`
"""
macro defer(body)
  if isa(body, Expr) && body.head ≡ :(::)
    :(Deferred{$(esc(body.args[2]))}(()-> $(esc(body.args[1]))))
  else
    :(Deferred{Any}(()-> $(esc(body))))
  end
end

"""
Results wrap Tasks with the API of a Promise
"""
mutable struct Result{T} <: Promise{T}
  cond::Task
  state::State
  value::T
  error::Exception
  Result{T}(c::Task) where T = new(c, pending)
end

"""
Run body in a seperate thread and return a `Result` which acts as a
placeholder for the result of the computation
"""
macro thread(body)
  if isa(body, Expr) && body.head ≡ :(::)
    body,T = body.args
  else
    T = Any
  end
  :(Result{$T}(@async $(esc(body))))
end

"""
A Future is like a Result except it's used in cases where it's not simply
wrapping a Task. This might be when wrapping an asynchronous C API or when
one task is responsible for several Promises
"""
mutable struct Future{T} <: Promise{T}
  state::State
  cond::Condition
  value::T
  error::Exception
  Future{T}() where T = new(pending, Condition())
end

Future() = Future{Any}()

"""
Fill in the `Future` with its final value. Any `Task`'s waiting
on this value will be able to continue
"""
function Base.put!(f::Future, value::Any)
  if f.state ≡ pending
    f.state = evaled
    f.value = value
  elseif f.state ≡ needed
    notify(f.cond, value)
  else
    error("Can't assign to a Promise which has been $(f.state)")
  end
end

"""
If you were unable to compute the value of the Future then you should `error` it
"""
function Base.error(f::Future, error::Exception)
  if f.state ≡ pending
    f.state = failed
    f.error = error
  elseif f.state ≡ needed
    notify(f.cond, error; error=true)
  else
    error("Can't error a Promise which has been $(f.state)")
  end
end

function need(f::Union{Future,Result})
  f.state ≡ evaled && return f.value
  f.state ≡ failed && throw(f.error)
  f.state ≡ needed && return _wait(f.cond)
  try
    f.state = needed
    f.value = _wait(f.cond)
    f.state = evaled
    f.value
  catch e
    f.state = failed
    f.error = unwrap(e)
    throw(f.error)
  end
end

unwrap(a) = a
unwrap(a::TaskFailedException) = a.task.result

_wait(t::Task) = fetch(t)
_wait(c::Condition) = wait(c)

Base.wait(p::Promise) = need(p)
