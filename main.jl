"""
A Promise is a placeholder for a value which isn't yet known.
Though we may know what type it will be hence Promises take
the type of their eventual value as a parameter
"""
abstract Promise{T}

"""
A Promise can be in one of the following states
"""
@enum State pending needed evaled failed

"""
When you want to get the actual value of a Promise you just call `need`
on it. It's safe to call `need` on all types so if in doubt...need it
"""
function need(x::Any) x end

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
result is stored. Whether it return or throws. From then on it
will just replicate this result without re-running the thunk
"""
function need(d::Deferred)
  d.state === evaled && return d.value
  d.state === failed && rethrow(d.error)
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
  if isa(body, Expr) && body.head == :(::)
    :(Deferred{$(esc(body.args[2]))}(()-> $(esc(body.args[1]))))
  else
    :(Deferred{Any}(()-> $(esc(body))))
  end
end

"""
Results are intended to provide a way for asynchronous processes
to communicate their result to the thread that spawned them
"""
type Result{T} <: Promise{T}
  cond::Task
  state::State
  value::T
  error::Exception
  Result(c::Task) = new(c, pending)
end

"""
Await the result if its pending. Otherwise reproduce its value or exception
"""
function need(r::Result)
  r.state === evaled && return r.value
  r.state === failed && rethrow(r.error)
  r.state === needed && return wait(r.cond)
  try
    r.state = needed
    r.value = wait(r.cond)
    r.state = evaled
    r.value
  catch e
    r.state = failed
    r.error = e
    rethrow(e)
  end
end

"""
Run body in a seperate thread and communicate the result with a Result
which is the only difference between this and @Base.async which returns
a Task
"""
macro thread(body)
  if isa(body, Expr) && body.head == :(::)
    body,T = body.args
  else
    T = Any
  end
  :(Result{$T}(@schedule $(esc(body))))
end
