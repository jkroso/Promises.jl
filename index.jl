export Deferred, need, @defer

type Deferred{T}
  fn::Function
  state::Int
  value::T
  error::Exception
  Deferred(f::Function) = new(f, 0)
end

Deferred{T}(f::Function, ::Type{T}=Any) = Deferred{T}(f)

##
# Evaluate the value
#
function need(x::Any) x end
function need(d::Deferred)
  d.state == 2 && return d.value
  d.state == 1 && rethrow(d.error)
  try
    d.value = d.fn()
    d.state = 2
    d.value
  catch e
    d.state = 1
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
