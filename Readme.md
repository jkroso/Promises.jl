
# deferred

A lazy evaluation primitive for Julia

## Installation

With [packin](//github.com/jkroso/packin): `packin add jkroso/deferred`

## API

```julia
data = @defer get("json.io").data
# => Deferred{Any}
data = @defer get("json.io").data::String
# => Deferred{String}
need(data)
# => """{"some":"JSON data"}"""
```

### @defer(expr::Expr)

Will defer the execution of `expr` until it is needed. If you annotate `expr` with a Type then the Deferred will be of that Type.

### need(deferred::Deferred)

Evaluates the `expr` that was deferred and returns the result. If `expr` throws an error then so will `need(deferred)`. The result is also cached so if `deferred` is ever need again it will have exactly the same effect. Be that return a value or throw an error

### need(x::Any)

`need` defaults to the identity function so you can call it on anything
