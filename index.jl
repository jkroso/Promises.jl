type Deferred{T}
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
    rethrow()
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
