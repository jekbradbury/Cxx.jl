import Base: dump
export @icxxdebug_str

dump(d::pcpp"clang::Decl") = ccall((:cdump,libcxxffi),Void,(Ptr{Void},),d)
dump(dc::pcpp"clang::DeclContext") = ccall((:dcdump,libcxxffi),Void,(Ptr{Void},),dc)
dump(d::pcpp"clang::NamedDecl") = ccall((:cdump,libcxxffi),Void,(Ptr{Void},),d)
dump(d::pcpp"clang::FunctionDecl") = ccall((:cdump,libcxxffi),Void,(Ptr{Void},),d)
dump(d::pcpp"clang::TemplateDecl") = ccall((:cdump,libcxxffi),Void,(Ptr{Void},),d)
dump(d::pcpp"clang::FunctionTemplateDecl") = ccall((:cdump,libcxxffi),Void,(Ptr{Void},),d)
dump(expr::pcpp"clang::Expr") = ccall((:exprdump,libcxxffi),Void,(Ptr{Void},),expr)
dump(t::pcpp"clang::Type") = ccall((:typedump,libcxxffi),Void,(Ptr{Void},),t)
dump(t::pcpp"llvm::Value") = ccall((:llvmdump,libcxxffi),Void,(Ptr{Void},),t)
dump(t::pcpp"llvm::Function") = ccall((:llvmdump,libcxxffi),Void,(Ptr{Void},),t)
dump(t::pcpp"llvm::Type") = ccall((:llvmtdump,libcxxffi),Void,(Ptr{Void},),t)
dump(t::QualType) = dump(canonicalType(extractTypePtr(t)))

parser(C) = pcpp"clang::Parser"(
    ccall((:clang_parser,libcxxffi),Ptr{Void},(Ptr{ClangCompiler},),&C))
compiler(C) = pcpp"clang::CompilerInstance"(
    ccall((:clang_compiler,libcxxffi),Ptr{Void},(Ptr{ClangCompiler},),&C))
shadow(C) = pcpp"llvm::Module"(
    ccall((:clang_shadow_module,libcxxffi),Ptr{Void},(Ptr{ClangCompiler},),&C)
    )
parser(C::CxxInstance) = parser(instance(C))
compiler(C::CxxInstance) = compiler(instance(C))
shadow(C::CxxInstance) = shadow(instance(C))

# Try to dump the generated Clang AST generated by Cxx.jl
@generated function dumpast_impl(CT, sourcebuf, args...)
    C = instance(CT)
    id = sourceid(sourcebuf)
    buf, filename, line, col = sourcebuffers[id]

    FD, llvmargs, argidxs = CreateFunctionWithBody(C,buf, args...;
        filename = filename, line = line, col = col)

    :( Cxx.dump($FD) )
end

macro icxxdebug_str(str,args...)
    compiler = :__current_compiler__
    startvarnum, sourcebuf, exprs, isexprs = process_body(compiler, str, false, args...)
    if isempty(args)
        args = (symbol(""),1,1)
    end
    push!(sourcebuffers,(takebuf_string(sourcebuf),args...))
    id = length(sourcebuffers)
    esc(build_icxx_expr(id, exprs, isexprs, Any[], compiler, dumpast_impl))
end

function collectSymbolsForExport(RD::pcpp"clang::CXXRecordDecl")
    f = Cxx.CreateFunctionWithPersonality(C, Cxx.julia_to_llvm(Void),[Cxx.julia_to_llvm(Ptr{Ptr{Void}})])
    builder = irbuilder(C)
    nummethods = icxx"""
    auto *CGM = $(Cxx.instance(Cxx.__default_compiler__).CGM);
    CGM->EmitTopLevelDecl($RD);
    llvm::SmallVector<llvm::Constant *, 0> addresses;
    unsigned i = 0;
    for (auto method : $RD->methods()) {
      clang::GlobalDecl GD(method);
      auto name = CGM->getMangledName(GD);
      auto llvmf = $(Cxx.instance(Cxx.__default_compiler__).shadow)->getFunction(name);
      llvm::IRBuilder *builder = $builder;
      builder->CreateStore(
        builder->CreateBitCast(llvmf,$(Cxx.julia_to_llvm(Ptr{Void}))),
        builder->CreateConstGEP2_32($(Cxx.julia_to_llvm(Ptr{Ptr{Void}})),
        $f->getArgumentList()[0], 0, i++));
      )
    }
    i
    """
    addresses = zeros(Ptr{Ptr{Void}},nummethods)
    eval(:(llvmcall($(f.ptr),Void,(Ptr{Ptr{Void}},),$(pointer(addresses)))))
    addresses
end
