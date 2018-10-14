# Methods

structdata(meth::Method) =
  [meth.module, meth.name, meth.file, meth.line, meth.sig, meth.sparam_syms,
   meth.ambig, meth.nargs, meth.isva, meth.nospecialize,
   Base.uncompressed_ast(meth, meth.source)]

initstruct(::Type{Method}) = ccall(:jl_new_method_uninit, Ref{Method}, (Any,), Main)

function newstruct!(meth::Method, mod, name, file, line, sig,
                    sparam_syms, ambig, nargs, isva, nospecialize, ast)
  meth.module = mod
  meth.name = name
  meth.file = file
  meth.line = line
  meth.sig = sig
  meth.sparam_syms = sparam_syms
  meth.ambig = ambig
  meth.nospecialize = nospecialize
  meth.nargs = nargs
  meth.isva = isva
  meth.source = ast
  meth.pure = ast.pure
  return meth
end

function structdata(t::TypeName)
  primary = Base.unwrap_unionall(t.wrapper)
  mt = !isdefined(t, :mt) ? nothing :
    [t.mt.name, collect(Base.MethodList(t.mt)), t.mt.max_args,
     isdefined(t.mt, :kwsorter) ? t.mt.kwsorter : nothing]
  [Base.string(VERSION), t.name, t.names, primary.super, primary.parameters,
   primary.types, isdefined(primary, :instance), primary.abstract,
   primary.mutable, primary.ninitialized, mt]
end

# Type Names

baremodule __deserialized_types__ end

function newstruct_raw(cache, ::Type{TypeName}, d)
  name = raise_recursive(d[:data][2], cache)
  name = isdefined(__deserialized_types__, name) ? gensym() : name
  tn = ccall(:jl_new_typename_in, Ref{Core.TypeName}, (Any, Any),
             name, __deserialized_types__)
  cache[d] = tn
  names, super, parameters, types, has_instance,
    abstr, mutabl, ninitialized = map(x -> raise_recursive(x, cache), d[:data][3:end-1])
  tn.names = names
  ndt = ccall(:jl_new_datatype, Any, (Any, Any, Any, Any, Any, Any, Cint, Cint, Cint),
              tn, tn.module, super, parameters, names, types,
              abstr, mutabl, ninitialized)
  ty = tn.wrapper = ndt.name.wrapper
  ccall(:jl_set_const, Cvoid, (Any, Any, Any), tn.module, tn.name, ty)
  if has_instance && !isdefined(ty, :instance)
    # use setfield! directly to avoid `fieldtype` lowering expecting to see a Singleton object already on ty
    Core.setfield!(ty, :instance, ccall(:jl_new_struct, Any, (Any, Any...), ty))
  end
  mt = raise_recursive(d[:data][end], cache)
  if mt != nothing
    mtname, defs, maxa, kwsorter = mt
    tn.mt = ccall(:jl_new_method_table, Any, (Any, Any), name, tn.module)
    tn.mt.name = mtname
    tn.mt.max_args = maxa
    for def in defs
      isdefined(def, :sig) || continue
      ccall(:jl_method_table_insert, Cvoid, (Any, Any, Ptr{Cvoid}), tn.mt, def, C_NULL)
    end
  end
  return tn
end

# Function Types

# Modelled on Base.Serialize
function isanon(t::DataType)
  tn = t.name
  if isdefined(tn, :mt)
    name = tn.mt.name
    mod = tn.module
    return t.super === Function &&
    unsafe_load(Base.unsafe_convert(Ptr{UInt8}, tn.name)) == UInt8('#') &&
    (!isdefined(mod, name) || t != typeof(getfield(mod, name)))
  end
  return false
end

# Called externally from lower(::DataType)
function lower_anon(T::DataType)
  BSONDict(:tag => "jl_anonymous",
           :typename => T.name,
           :params => [T.parameters...])
end

tags[:jl_anonymous] = function (d)
  constructtype(d[:typename].wrapper, d[:params])
end
