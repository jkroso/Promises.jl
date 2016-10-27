@require "github.com/jkroso/Prospects.jl" need

"""
A Promise is a placeholder for a value which isn't yet known.
Though we may know what type it will be hence Promises take
the type of their eventual value as a parameter
"""
abstract Promise{T}

"A Promise can be in one of the following states"
@enum State pending needed evaled failed

Base.isready(p::Promise) = p.state > needed

"Deferred's enable lazy evaluation"
type Deferred{T} <: Promise{T}
  thunk::Function
  state::State
  value::T
  error::Exception
  Deferred(f::Function) = new(f, pending)
end

"Make the type parameter optional"
Deferred(f::Function) = Deferred{Any}(f)

"""
The first time a Deferred is needed it's thunk is called and the
result is stored. Whether it returns or throws. From then on it
will just replicate this result without calling the thunk
"""
function need(d::Deferred)
  d.state ≡ evaled && return d.value
  d.state ≡ failed && rethrow(d.error)
  try
    d.value = d.thunk()
    d.state = evaled
    d.value
  catch e
    d.state = failed
    d.error = e
    rethrow(e)
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
type Result{T} <: Promise{T}
  cond::Task
  state::State
  value::T
  error::Exception
  Result(c::Task) = new(c, pending)
end

"""
Run body in a seperate thread and communicate the result with a Result
which is the only difference between this and @Base.async which returns
a Task
"""
macro thread(body)
  if isa(body, Expr) && body.head ≡ :(::)
    body,T = body.args
  else
    T = Any
  end
  :(Result{$T}(@schedule $(esc(body))))
end

"""
We use Futures when we don't have a value yet and aren't even sure
where its going to come from
"""
type Future{T} <: Promise{T}
  state::State
  cond::Condition
  value::T
  error::Exception
  Future() = new(pending, Condition())
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
  f.state ≡ failed && rethrow(f.error)
  f.state ≡ needed && return wait(f.cond)
  try
    f.state = needed
    f.value = wait(f.cond)
    f.state = evaled
    f.value
  catch e
    f.state = failed
    f.error = e
    rethrow(e)
  end
end

Base.wait(p::Promise) = need(p)
