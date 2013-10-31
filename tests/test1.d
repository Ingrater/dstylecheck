module test1;

class notGood
{
	private:
		int _good;
		int _NotGood;
		
	public:
		int good2;
		int NogGood2;
		int _notGood3;
		
		void BadFunc();
		void goodFunc();
}

class Good
{
}

struct notGood2
{
}

struct Good2
{
	private:
		int _good;
		int _NotGood;
		
	public:
		int good2;
		int NogGood2;
		int _notGood3;
		
		void BadFunc();
		void goodFunc();
		
		enum TestEnum
		{
			goodValue,
			BadValue
		}
}

struct Good3(T, size_t size)
{
  enum badEnum : T
  {
    bad_Value
  }
}

enum TestEnum
{
	BadValue,
	BADVALUE2,
	goodValue,
	badValue3_,
	badValue4__,
    abstract_,
    alias_,
    align_,
    asm_,
    assert_,
    auto_,
    body_,
    bool_,
    break_,
    byte_,
    case_,
    cast_,
    catch_,
    cdouble_,
    cent_,
    cfloat_,
    char_,
    class_,
    const_,
    continue_,
    creal_,
    dchar_,
    debug_,
    default_,
    delegate_,
    delete_,
    deprecated_,
    do_,
    double_,
    else_,
    enum_,
    export_,
    extern_,
    false_,
    final_,
    finally_,
    float_,
    for_,
    foreach_,
    foreach_reverse_,
    function_,
    goto_,
    idouble_,
    if_,
    ifloat_,
    immutable_,
    import_,
    in_,
    inout_, 
    int_,
    interface_,
    invariant_, 
    ireal_,
    is_,
    lazy_,
    long_,
    macro_,
    mixin_,
    module_,
    new_,
    nothrow_,
    null_,
    out_,
    override_,
    package_,
    pragma_,
    private_,
    protected_,
    public_,
    pure_,
    real_,
    ref_,
    return_,
    scope_,
    shared_,
    short_,
    static_,
    struct_,
    super_,
    switch_,
    synchronized_,
    template_,
    this_,
    throw_,
    true_,
    try_,
    typedef_,
    typeid_,
    typeof_,
    ubyte_,
    ucent_,
    uint_,
    ulong_,
    union_,
    unittest_,
    ushort_,
    version_,
    void_,
    volatile_,
    wchar_,
    while_,
    with_,
}