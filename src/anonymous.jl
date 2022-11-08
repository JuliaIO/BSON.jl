# Methods

if VERSION < v"1.2-"
const syms_fieldname = :sparam_syms
else
const syms_fieldname = :slot_syms
end

if VERSION < v"1.2-"
const _uncompress = Base.uncompressed_ast
else
const _uncompress = Base._uncompressed_ast
end

if VERSION < v"1.6-"
structdata(meth::Method) =
  [meth.module, meth.name, meth.file, meth.line, meth.sig, getfield(meth, syms_fieldname),
   meth.ambig, meth.nargs, meth.isva, meth.nospecialize,
   _uncompress(meth, meth.source)]
else
structdata(meth::Method) =
  [meth.module, meth.name, meth.file, meth.line, meth.sig, getfield(meth, syms_fieldname),
   meth.nargs, meth.isva, meth.nospecialize, _uncompress(meth, meth.source)]
end

initstruct(::Type{Method}) = ccall(:jl_new_method_uninit, Ref{Method}, (Any,), Main)

if VERSION < v"1.6-"
function newstruct!(meth::Method, mod, name, file, line, sig,
                    syms, ambig, nargs, isva, nospecialize, ast)
  meth.module = mod
  meth.name = name
  meth.file = file
  meth.line = line
  meth.sig = sig
  setfield!(meth, syms_fieldname, syms)
  meth.ambig = ambig
  meth.nospecialize = nospecialize
  meth.nargs = nargs
  meth.isva = isva
  meth.source = ast
  meth.pure = ast.pure
  return meth
end
else
function newstruct!(meth::Method, mod, name, file, line, sig,
                    syms, nargs, isva, nospecialize, ast)
  meth.module = mod
  meth.name = name
  meth.file = file
  meth.line = line
  meth.sig = sig
  setfield!(meth, syms_fieldname, syms)
  meth.nospecialize = nospecialize
  meth.nargs = nargs
  meth.isva = isva
  meth.source = ast
  meth.pure = ast.pure
  return meth
end
end

# Type Names

if VERSION < v"1.7-"
function structdata(t::TypeName)
  primary = Base.unwrap_unionall(t.wrapper)
  mt = !isdefined(t, :mt) ? nothing :
    [t.mt.name, collect(Base.MethodList(t.mt)), t.mt.max_args,
     isdefined(t.mt, :kwsorter) ? t.mt.kwsorter : nothing]
  [Base.string(VERSION), t.name, t.names, primary.super, primary.parameters,
   primary.types, isdefined(primary, :instance), isabstracttype(primary),
   ismutabletype(primary), primary.ninitialized, mt]
end
else
# see https://github.com/JuliaLang/julia/pull/41018 for changes
function structdata(t::TypeName)
  primary = Base.unwrap_unionall(t.wrapper)
  mt = !isdefined(t, :mt) ? nothing :
    [t.mt.name, collect(Base.MethodList(t.mt)), t.mt.max_args,
      isdefined(t.mt, :kwsorter) ? t.mt.kwsorter : nothing]
  [Base.string(VERSION), t.name, t.names, primary.super, primary.parameters,
    primary.types, isdefined(primary, :instance), t.atomicfields, isabstracttype(primary),
    ismutable(primary), Core.Compiler.datatype_min_ninitialized(primary), mt]
end
end

if VERSION >= v"1.7-"
structdata(x::Core.TypeofVararg) =
  Any[getfield(x, f) for f in fieldnames(typeof(x)) if isdefined(x, f)]
end

baremodule __deserialized_types__ end

if VERSION < v"1.7-"
  function newstruct_raw(cache, ::Type{TypeName}, d, init)
    name = raise_recursive(d[:data][2], cache, init)
    name = isdefined(__deserialized_types__, name) ? gensym() : name
    tn = ccall(:jl_new_typename_in, Ref{Core.TypeName}, (Any, Any),
               name, __deserialized_types__)
    cache[d] = tn
    names, super, parameters, types, has_instance,
      abstr, mutabl, ninitialized = map(x -> raise_recursive(x, cache, init), d[:data][3:end-1])
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
    mt = raise_recursive(d[:data][end], cache, init)
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
else
  function newstruct_raw(cache, ::Type{TypeName}, d, init)
    name = raise_recursive(d[:data][2], cache, init)
    name = isdefined(__deserialized_types__, name) ? gensym() : name
    tn = ccall(:jl_new_typename_in, Ref{Core.TypeName}, (Any, Any),
               name, __deserialized_types__)
    cache[d] = tn
    names, super, parameters, types, has_instance, atomicfields,
      abstr, mutabl, ninitialized = map(x -> raise_recursive(x, cache, init), d[:data][3:end-1])
    ndt = ccall(:jl_new_datatype, Any, (Any, Any, Any, Any, Any, Any, Any, Cint, Cint, Cint),
                tn, tn.module, super, parameters, names, types, atomicfields,
                abstr, mutabl, ninitialized)
    # ty = tn.wrapper = ndt.name.wrapper
    ty = ndt.name.wrapper
    ccall(:jl_set_const, Cvoid, (Any, Any, Any), tn.module, tn.name, ty)
    if has_instance && !isdefined(ty, :instance)
      # use setfield! directly to avoid `fieldtype` lowering expecting to see a Singleton object already on ty
      Core.setfield!(ty, :instance, ccall(:jl_new_struct, Any, (Any, Any...), ty))
    end
    mt = raise_recursive(d[:data][end], cache, init)
    if mt != nothing
      mtname, defs, maxa, kwsorter = mt
      mt = ccall(:jl_new_method_table, Any, (Any, Any), name, tn.module)
      mt.name = mtname
      mt.max_args = maxa
      ccall(:jl_set_nth_field, Cvoid, (Any, Csize_t, Any), tn, Base.fieldindex(Core.TypeName, :mt)-1, mt)
      for def in defs
        isdefined(def, :sig) || continue
        ccall(:jl_method_table_insert, Cvoid, (Any, Any, Ptr{Cvoid}), mt, def, C_NULL)
      end
    end
    return tn
  end
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
