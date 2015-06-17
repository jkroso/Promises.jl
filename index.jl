abstract Promise{T}

type Deferred{T} <: Promise{T}
  fn::Function
  state::Symbol
  value::T
  error::Exception
  Deferred(f::Function) = new(f, :pending)
end

Deferred{T}(f::Function, ::Type{T}=Any) = Deferred{T}(f)

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

##
# Create a Deferred from an Expr. If `body` is annotated
# with a `Type` then create a `Deferred{Type}`
#
macro defer(body)
  if isa(body, Expr) && body.head == symbol("::")
    :(Deferred(() -> $(esc(body.args[1])), $(esc(body.args[2]))))
  else
    :(Deferred(() -> $(esc(body))))
  end
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
