###########################################################################
# Module for ABI Compliance Checker with regression test suite
#
# Copyright (C) 2009-2011 Institute for System Programming, RAS
# Copyright (C) 2011-2012 Nokia Corporation and/or its subsidiary(-ies)
# Copyright (C) 2011-2012 ROSA Laboratory
# Copyright (C) 2012-2016 Andrey Ponomarenko's ABI Laboratory
#
# Written by Andrey Ponomarenko
#
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License or the GNU Lesser
# General Public License as published by the Free Software Foundation.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# and the GNU Lesser General Public License along with this program.
# If not, see <http://www.gnu.org/licenses/>.
###########################################################################
use strict;

my ($TestDump, $Debug, $Quiet, $ExtendedCheck, $LogMode, $ReportFormat,
$DumpFormat, $LIB_EXT, $GCC_PATH, $SortDump, $CheckHeadersOnly,
$OldStyle, $TestABIDumper);
my $OSgroup = get_OSgroup();

sub testTool($$$$$$$$$$$)
{
    ($TestDump, $Debug, $Quiet, $ExtendedCheck, $LogMode, $ReportFormat,
    $DumpFormat, $LIB_EXT, $GCC_PATH, $SortDump, $CheckHeadersOnly,
    $OldStyle, $TestABIDumper) = @_;
    
    testC();
    testCpp();
}

sub testCpp()
{
    printMsg("INFO", "verifying detectable C++ library changes");
    my ($HEADER1, $SOURCE1, $HEADER2, $SOURCE2) = ();
    my $DECL_SPEC = ($OSgroup eq "windows")?"__declspec( dllexport )":"";
    my $EXTERN = ($OSgroup eq "windows")?"extern ":""; # add "extern" for CL compiler
    
    # Class outside namespace
    $HEADER1 .= "
        class $DECL_SPEC OutsideNS {
        public:
            int someMethod();
            int field;
        };";
    $SOURCE1 .= "
        int OutsideNS::someMethod() { return 0; }";
    
    $HEADER2 .= "
        class $DECL_SPEC OutsideNS {
        public:
            int someMethod();
            int field;
            int field2;
        };";
    $SOURCE2 .= "
        int OutsideNS::someMethod() { return 0; }";
    
    # Begin namespace
    $HEADER1 .= "namespace TestNS {\n";
    $HEADER2 .= "namespace TestNS {\n";
    $SOURCE1 .= "namespace TestNS {\n";
    $SOURCE2 .= "namespace TestNS {\n";
    
    # Changed template internals
    # $HEADER1 .= "
    #     template <typename T, int _P>
    #     class $DECL_SPEC ChangedTemplate {
    #     public:
    #         T value;
    #         T*const field;
    #         T array[_P];
    #         typedef int My;
    #         My var;
    #     };
    #     ChangedTemplate<int, 1>* changedTemplate();";
    # $SOURCE1 .= "
    #     ChangedTemplate<int, 1>* changedTemplate() { return new ChangedTemplate<int, 1>(); }";
    # 
    # $HEADER2 .= "
    #     template <typename T, int _P>
    #     class $DECL_SPEC ChangedTemplate {
    #     public:
    #         double value;
    #         T* field;
    #         double array[_P];
    #         typedef int My;
    #         My var;
    #     };
    #     ChangedTemplate<int, 1>* changedTemplate();";
    # $SOURCE2 .= "
    #     ChangedTemplate<int, 1>* changedTemplate() { return new ChangedTemplate<int, 1>(); }";
    
    # Removed inline method
    $HEADER1 .= "
        class $DECL_SPEC RemovedInlineMethod {
        public:
            int someMethod();
            inline int removedMethod() { return 0; };
            int field;
        };";
    $SOURCE1 .= "
        int RemovedInlineMethod::someMethod() { return removedMethod(); }";
    
    $HEADER2 .= "
        class $DECL_SPEC RemovedInlineMethod {
        public:
            int someMethod();
            int field;
        };";
    $SOURCE2 .= "
        int RemovedInlineMethod::someMethod() { return 0; }";
    
    # Pure_Virtual_Replacement
    $HEADER1 .= "
        class $DECL_SPEC PureVirtualReplacement {
        public:
            virtual int methodOld(int param) = 0;
            int otherMethod();
        };
        
        class $DECL_SPEC PureVirtualReplacement_Derived: public PureVirtualReplacement {
        public:
            int methodOld(int param);
        };";
    $SOURCE1 .= "
        int PureVirtualReplacement::otherMethod() { return 0; }
        int PureVirtualReplacement_Derived::methodOld(int param) { return 0; }";
    
    $HEADER2 .= "
        class $DECL_SPEC PureVirtualReplacement {
        public:
            virtual int methodNew(int param) = 0;
            int otherMethod();
        };
        
        class $DECL_SPEC PureVirtualReplacement_Derived: public PureVirtualReplacement {
        public:
            int methodNew(int param);
        };";
    $SOURCE2 .= "
        int PureVirtualReplacement::otherMethod() { return 0; }
        int PureVirtualReplacement_Derived::methodNew(int param) { return 0; }";
    
    # Virtual_Replacement
    $HEADER1 .= "
        class $DECL_SPEC VirtualReplacement {
        public:
            virtual int methodOld(int param);
        };";
    $SOURCE1 .= "
        int VirtualReplacement::methodOld(int param) { return 0; }";
    
    $HEADER2 .= "
        class $DECL_SPEC VirtualReplacement {
        public:
            virtual int methodNew(int param);
        };";
    $SOURCE2 .= "
        int VirtualReplacement::methodNew(int param) { return 0; }";
    
    # Removed_Symbol (renamed, source-compatible)
    $HEADER1 .= "
        int $DECL_SPEC renamedFunc(int param);";
    $SOURCE1 .= "
        int renamedFunc(int param) { return 0; }";
    
    $HEADER2 .= "
        int $DECL_SPEC renamedFunc_NewName(int param);
        #define renamedFunc renamedFunc_NewName";
    $SOURCE2 .= "
        int renamedFunc_NewName(int param) { return 0; }";
    
    # Removed_Symbol
    $HEADER1 .= "
        int $DECL_SPEC functionBecameInline(int param);";
    $SOURCE1 .= "
        int functionBecameInline(int param) { return 0; }";
    
    $HEADER2 .= "
        inline int functionBecameInline(int param) { return 0; }";
    
    # Removed_Symbol (safe)
    $HEADER1 .= "
        inline int removedInlineFunction(int param) { return 0; }";
    
    # Became Non-Opaque
    $HEADER1 .= "
        struct OpaqueStruct;
        int paramBecameNonOpaque(OpaqueStruct* p);";
    $SOURCE1 .= "
        int paramBecameNonOpaque(OpaqueStruct* p) { return 0; }";
    
    $HEADER2 .= "
        struct OpaqueStruct
        {
            int i;
            short j;
            OpaqueStruct();
        };
        int paramBecameNonOpaque(OpaqueStruct* p);";
    $SOURCE2 .= "
        int paramBecameNonOpaque(OpaqueStruct* p) { return 0; }";
    
    # Field_Became_Const
    # Typedef
    $HEADER1 .= "
        typedef int*const CONST_INT_PTR;
        class $DECL_SPEC FieldBecameConstTypedef {
        public:
            int* f;
            int*const f2;
            int method(CONST_INT_PTR p);
        };";
    $SOURCE1 .= "
        int FieldBecameConstTypedef::method(CONST_INT_PTR p) { return 0; }";
    
    $HEADER2 .= "
        typedef int*const CONST_INT_PTR;
        class $DECL_SPEC FieldBecameConstTypedef {
        public:
            CONST_INT_PTR f;
            int*const f2;
            int method(CONST_INT_PTR p);
        };";
    $SOURCE2 .= "
        int FieldBecameConstTypedef::method(CONST_INT_PTR p) { return 0; }";
    
    # Field_Removed_Const
    $HEADER1 .= "
        class $DECL_SPEC FieldRemovedConst {
        public:
            int*const*const f;
            int method();
        };";
    $SOURCE1 .= "
        int FieldRemovedConst::method() { return 0; }";
    
    $HEADER2 .= "
        class $DECL_SPEC FieldRemovedConst {
        public:
            int**const f;
            int method();
        };";
    $SOURCE2 .= "
        int FieldRemovedConst::method() { return 0; }";
    
    # Field_Became_Const
    $HEADER1 .= "
        class $DECL_SPEC FieldBecameConst {
        public:
            int* f;
            int method();
        };";
    $SOURCE1 .= "
        int FieldBecameConst::method() { return 0; }";
    
    $HEADER2 .= "
        class $DECL_SPEC FieldBecameConst {
        public:
            int*const f;
            int method();
        };";
    $SOURCE2 .= "
        int FieldBecameConst::method() { return 0; }";
    
    # Field_Became_Private
    $HEADER1 .= "
        class $DECL_SPEC FieldBecamePrivate {
        public:
            int* f;
            int method();
        };";
    $SOURCE1 .= "
        int FieldBecamePrivate::method() { return 0; }";
    
    $HEADER2 .= "
        class $DECL_SPEC FieldBecamePrivate {
        private:
            int* f;
        public:
            int method();
        };";
    $SOURCE2 .= "
        int FieldBecamePrivate::method() { return 0; }";
    
    # Field_Became_Protected
    $HEADER1 .= "
        class $DECL_SPEC FieldBecameProtected {
        public:
            int* f;
            int method();
        };";
    $SOURCE1 .= "
        int FieldBecameProtected::method() { return 0; }";
    
    $HEADER2 .= "
        class $DECL_SPEC FieldBecameProtected {
        protected:
            int* f;
        public:
            int method();
        };";
    $SOURCE2 .= "
        int FieldBecameProtected::method() { return 0; }";
    
    # Global_Data_Became_Private
    $HEADER1 .= "
        class $DECL_SPEC GlobalDataBecamePrivate {
        public:
            static int data;
            
        };";
    $SOURCE1 .= "
        int GlobalDataBecamePrivate::data = 10;";
    
    $HEADER2 .= "
        class $DECL_SPEC GlobalDataBecamePrivate {
        private:
            static int data;
            
        };";
    $SOURCE2 .= "
        int GlobalDataBecamePrivate::data = 10;";
    
    # Method_Became_Private
    $HEADER1 .= "
        class $DECL_SPEC MethodBecamePrivate {
        public:
            int method();
        };";
    $SOURCE1 .= "
        int MethodBecamePrivate::method() { return 0; }";
    
    $HEADER2 .= "
        class $DECL_SPEC MethodBecamePrivate {
        private:
            int method();
        };";
    $SOURCE2 .= "
        int MethodBecamePrivate::method() { return 0; }";

    # Method_Became_Protected
    $HEADER1 .= "
        class $DECL_SPEC MethodBecameProtected {
        public:
            int method();
        };";
    $SOURCE1 .= "
        int MethodBecameProtected::method() { return 0; }";
    
    $HEADER2 .= "
        class $DECL_SPEC MethodBecameProtected {
        protected:
            int method();
        };";
    $SOURCE2 .= "
        int MethodBecameProtected::method() { return 0; }";

    # Method_Became_Public
    $HEADER1 .= "
        class $DECL_SPEC MethodBecamePublic {
        protected:
            int method();
        };";
    $SOURCE1 .= "
        int MethodBecamePublic::method() { return 0; }";
    
    $HEADER2 .= "
        class $DECL_SPEC MethodBecamePublic {
        public:
            int method();
        };";
    $SOURCE2 .= "
        int MethodBecamePublic::method() { return 0; }";
    
    # Removed_Const_Overload
    $HEADER1 .= "
        class $DECL_SPEC RemovedConstOverload {
        public:
            int removed();
            int removed() const;
        };";
    $SOURCE1 .= "
        int RemovedConstOverload::removed() { return 0; }
        int RemovedConstOverload::removed() const { return 0; }";
    
    $HEADER2 .= "
        class $DECL_SPEC RemovedConstOverload {
        public:
            int removed();
        };";
    $SOURCE2 .= "
        int RemovedConstOverload::removed() { return 0; }";
    
    # Inline method
    $HEADER1 .= "
        class $DECL_SPEC InlineMethod {
        public:
            inline int foo() { return 0; }
        };";
    
    $HEADER2 .= "
        class $DECL_SPEC InlineMethod {
        public:
            inline long foo() { return 0; }
        };";
    
    # Global_Data_Became_Non_Const
    $HEADER1 .= "
        $EXTERN $DECL_SPEC const int globalDataBecameNonConst = 10;";
    
    $HEADER2 .= "
        extern $DECL_SPEC int globalDataBecameNonConst;";
    $SOURCE2 .= "
        int globalDataBecameNonConst = 15;";

    # Global_Data_Became_Non_Const
    # Class Member
    $HEADER1 .= "
        class $DECL_SPEC GlobalDataBecameNonConst {
        public:
            static const int data;
        };";
    $SOURCE1 .= "
        const int GlobalDataBecameNonConst::data = 10;";
    
    $HEADER2 .= "
        class $DECL_SPEC GlobalDataBecameNonConst {
        public:
            static int data;
        };";
    $SOURCE2 .= "
        int GlobalDataBecameNonConst::data = 10;";

    # Global_Data_Became_Const
    $HEADER1 .= "
        extern $DECL_SPEC int globalDataBecameConst;";
    $SOURCE1 .= "
        int globalDataBecameConst = 10;";
    
    $HEADER2 .= "
        $EXTERN $DECL_SPEC const int globalDataBecameConst = 15;";

    # Global_Data_Became_Const
    # Class Member
    $HEADER1 .= "
        class $DECL_SPEC GlobalDataBecameConst {
        public:
            static int Data;
        };";
    $SOURCE1 .= "
        int GlobalDataBecameConst::Data = 10;";
    
    $HEADER2 .= "
        class $DECL_SPEC GlobalDataBecameConst {
        public:
            static const int Data = 15;
        };";

    # Global_Data_Value_Changed
    $HEADER1 .= "
        class $DECL_SPEC GlobalDataValue {
        public:
            static const int Integer = 10;
            static const char Char = \'o\';
        };";
    
    $HEADER2 .= "
        class $DECL_SPEC GlobalDataValue {
        public:
            static const int Integer = 15;
            static const char Char = \'N\';
        };";
    
    # Global_Data_Value_Changed
    # Integer
    $HEADER1 .= "
        $EXTERN $DECL_SPEC const int globalDataValue_Integer = 10;";
    
    $HEADER2 .= "
        $EXTERN $DECL_SPEC const int globalDataValue_Integer = 15;";

    # Global_Data_Value_Changed
    # Character
    $HEADER1 .= "
        $EXTERN $DECL_SPEC const char globalDataValue_Char = \'o\';";
    
    $HEADER2 .= "
        $EXTERN $DECL_SPEC const char globalDataValue_Char = \'N\';";
    
    # Parameter_Became_Restrict
    $HEADER1 .= "
        class $DECL_SPEC ParameterBecameRestrict {
        public:
            int method(int* param);
        };";
    $SOURCE1 .= "
        int ParameterBecameRestrict::method(int* param) { return 0; }";
    
    $HEADER2 .= "
        class $DECL_SPEC ParameterBecameRestrict {
        public:
            int method(int* __restrict param);
        };";
    $SOURCE2 .= "
        int ParameterBecameRestrict::method(int* __restrict param) { return 0; }";

    # Parameter_Became_Non_Restrict
    $HEADER1 .= "
        class $DECL_SPEC ParameterBecameNonRestrict {
        public:
            int method(int* __restrict param);
        };";
    $SOURCE1 .= "
        int ParameterBecameNonRestrict::method(int* __restrict param) { return 0; }";
    
    $HEADER2 .= "
        class $DECL_SPEC ParameterBecameNonRestrict {
        public:
            int method(int* param);
        };";
    $SOURCE2 .= "
        int ParameterBecameNonRestrict::method(int* param) { return 0; }";
    
    # Field_Became_Volatile
    $HEADER1 .= "
        class $DECL_SPEC FieldBecameVolatile {
        public:
            int method(int param);
            int f;
        };";
    $SOURCE1 .= "
        int FieldBecameVolatile::method(int param) { return param; }";
    
    $HEADER2 .= "
        class $DECL_SPEC FieldBecameVolatile {
        public:
            int method(int param);
            volatile int f;
        };";
    $SOURCE2 .= "
        int FieldBecameVolatile::method(int param) { return param; }";

    # Field_Became_Non_Volatile
    $HEADER1 .= "
        class $DECL_SPEC FieldBecameNonVolatile {
        public:
            int method(int param);
            volatile int f;
        };";
    $SOURCE1 .= "
        int FieldBecameNonVolatile::method(int param) { return param; }";
    
    $HEADER2 .= "
        class $DECL_SPEC FieldBecameNonVolatile {
        public:
            int method(int param);
            int f;
        };";
    $SOURCE2 .= "
        int FieldBecameNonVolatile::method(int param) { return param; }";

    # Field_Became_Mutable
    $HEADER1 .= "
        class $DECL_SPEC FieldBecameMutable {
        public:
            int method(int param);
            int f;
        };";
    $SOURCE1 .= "
        int FieldBecameMutable::method(int param) { return param; }";
    
    $HEADER2 .= "
        class $DECL_SPEC FieldBecameMutable {
        public:
            int method(int param);
            mutable int f;
        };";
    $SOURCE2 .= "
        int FieldBecameMutable::method(int param) { return param; }";

    # Field_Became_Non_Mutable
    $HEADER1 .= "
        class $DECL_SPEC FieldBecameNonMutable {
        public:
            int method(int param);
            mutable int f;
        };";
    $SOURCE1 .= "
        int FieldBecameNonMutable::method(int param) { return param; }";
    
    $HEADER2 .= "
        class $DECL_SPEC FieldBecameNonMutable {
        public:
            int method(int param);
            int f;
        };";
    $SOURCE2 .= "
        int FieldBecameNonMutable::method(int param) { return param; }";
    
    # Method_Became_Const
    # Method_Became_Volatile
    $HEADER1 .= "
        class $DECL_SPEC MethodBecameConstVolatile {
        public:
            int method(int param);
        };";
    $SOURCE1 .= "
        int MethodBecameConstVolatile::method(int param) { return param; }";
    
    $HEADER2 .= "
        class $DECL_SPEC MethodBecameConstVolatile {
        public:
            int method(int param) volatile const;
        };";
    $SOURCE2 .= "
        int MethodBecameConstVolatile::method(int param) volatile const { return param; }";
    
    # Method_Became_Const
    $HEADER1 .= "
        class $DECL_SPEC MethodBecameConst {
        public:
            int method(int param);
        };";
    $SOURCE1 .= "
        int MethodBecameConst::method(int param) { return param; }";
    
    $HEADER2 .= "
        class $DECL_SPEC MethodBecameConst {
        public:
            int method(int param) const;
        };";
    $SOURCE2 .= "
        int MethodBecameConst::method(int param) const { return param; }";

    # Method_Became_Non_Const
    $HEADER1 .= "
        class $DECL_SPEC MethodBecameNonConst {
        public:
            int method(int param) const;
        };";
    $SOURCE1 .= "
        int MethodBecameNonConst::method(int param) const { return param; }";
    
    $HEADER2 .= "
        class $DECL_SPEC MethodBecameNonConst {
        public:
            int method(int param);
        };";
    $SOURCE2 .= "
        int MethodBecameNonConst::method(int param) { return param; }";
    
    # Method_Became_Volatile
    $HEADER1 .= "
        class $DECL_SPEC MethodBecameVolatile {
        public:
            int method(int param);
        };";
    $SOURCE1 .= "
        int MethodBecameVolatile::method(int param) { return param; }";
    
    $HEADER2 .= "
        class $DECL_SPEC MethodBecameVolatile {
        public:
            int method(int param) volatile;
        };";
    $SOURCE2 .= "
        int MethodBecameVolatile::method(int param) volatile { return param; }";
    
    # Virtual_Method_Position
    # Multiple bases
    $HEADER1 .= "
        class $DECL_SPEC PrimaryBase
        {
        public:
            virtual ~PrimaryBase();
            virtual void foo();
        };
        class $DECL_SPEC SecondaryBase
        {
        public:
            virtual ~SecondaryBase();
            virtual void bar();
        };
        class UnsafeVirtualOverride: public PrimaryBase, public SecondaryBase
        {
        public:
            UnsafeVirtualOverride();
            ~UnsafeVirtualOverride();
            void foo();
        };";
    $SOURCE1 .= "
        PrimaryBase::~PrimaryBase() { }
        void PrimaryBase::foo() { }
        
        SecondaryBase::~SecondaryBase() { }
        void SecondaryBase::bar() { }
        
        UnsafeVirtualOverride::UnsafeVirtualOverride() { }
        UnsafeVirtualOverride::~UnsafeVirtualOverride() { }
        void UnsafeVirtualOverride::foo() { }";
    
    $HEADER2 .= "
        class $DECL_SPEC PrimaryBase
        {
        public:
            virtual ~PrimaryBase();
            virtual void foo();
        };
        class $DECL_SPEC SecondaryBase
        {
        public:
            virtual ~SecondaryBase();
            virtual void bar();
        };
        class UnsafeVirtualOverride: public PrimaryBase, public SecondaryBase
        {
        public:
            UnsafeVirtualOverride();
            ~UnsafeVirtualOverride();
            void foo();
            void bar();
        };";
    $SOURCE2 .= "
        PrimaryBase::~PrimaryBase() { }
        void PrimaryBase::foo() { }
        
        SecondaryBase::~SecondaryBase() { }
        void SecondaryBase::bar() { }
        
        UnsafeVirtualOverride::UnsafeVirtualOverride() { }
        UnsafeVirtualOverride::~UnsafeVirtualOverride() { }
        void UnsafeVirtualOverride::foo() { }
        void UnsafeVirtualOverride::bar() { }";
    
    # Removed_Interface (inline virtual d-tor)
    $HEADER1 .= "
        template <typename T>
        class $DECL_SPEC BaseTemplate {
        public:
            BaseTemplate() { }
            virtual int method(int param) { return param; };
            virtual ~BaseTemplate() { };
        };
        class $DECL_SPEC RemovedVirtualDestructor: public BaseTemplate<int> {
        public:
            RemovedVirtualDestructor() { };
            virtual int method2(int param);
        };";
    $SOURCE1 .= "
        int RemovedVirtualDestructor::method2(int param) { return param; }";
    
    $HEADER2 .= "
        template <typename T>
        class $DECL_SPEC BaseTemplate {
        public:
            BaseTemplate() { }
            virtual int method(int param) { return param; };
            //virtual ~BaseTemplate() { };
        };
        class $DECL_SPEC RemovedVirtualDestructor: public BaseTemplate<int> {
        public:
            RemovedVirtualDestructor() { };
            virtual int method2(int param);
        };";
    $SOURCE2 .= "
        int RemovedVirtualDestructor::method2(int param) { return param; }";
    
    # Added_Virtual_Method_At_End
    $HEADER1 .= "
        class $DECL_SPEC DefaultConstructor {
        public:
            DefaultConstructor() { }
            virtual int method(int param);
        };";
    $SOURCE1 .= "
        int DefaultConstructor::method(int param) { return param; }";
    
    $HEADER2 .= "
        class $DECL_SPEC DefaultConstructor {
        public:
            DefaultConstructor() { }
            virtual int method(int param);
            virtual int addedMethod(int param);
        };";
    $SOURCE2 .= "
        int DefaultConstructor::method(int param) { return addedMethod(param); }
        int DefaultConstructor::addedMethod(int param) { return param; }";
    
    # Added_Enum_Member
    $HEADER1 .= "
        enum AddedEnumMember {
            OldMember
        };
        $DECL_SPEC int addedEnumMember(enum AddedEnumMember param);";
    $SOURCE1 .= "
        int addedEnumMember(enum AddedEnumMember param) { return 0; }";
    
    $HEADER2 .= "
        enum AddedEnumMember {
            OldMember,
            NewMember
        };
        $DECL_SPEC int addedEnumMember(enum AddedEnumMember param);";
    $SOURCE2 .= "
        int addedEnumMember(enum AddedEnumMember param) { return 0; }";
    
    # Parameter_Type_Format (Safe)
    $HEADER1 .= "
        struct DType
        {
            int i;
            double j;
        };
        $DECL_SPEC int parameterTypeFormat_Safe(struct DType param);";
    $SOURCE1 .= "
        int parameterTypeFormat_Safe(struct DType param) { return 0; }";
    
    $HEADER2 .= "
        class DType
        {
            int i;
            double j;
        };
        $DECL_SPEC int parameterTypeFormat_Safe(class DType param);";
    $SOURCE2 .= "
        int parameterTypeFormat_Safe(class DType param) { return 0; }";
    
    # Type_Became_Opaque (Struct)
    $HEADER1 .= "
        struct StructBecameOpaque
        {
            int i, j;
        };
        $DECL_SPEC int structBecameOpaque(struct StructBecameOpaque* param);";
    $SOURCE1 .= "
        int structBecameOpaque(struct StructBecameOpaque* param) { return 0; }";
    
    $HEADER2 .= "
        struct StructBecameOpaque;
        $DECL_SPEC int structBecameOpaque(struct StructBecameOpaque* param);";
    $SOURCE2 .= "
        int structBecameOpaque(struct StructBecameOpaque* param) { return 0; }";
    
    # Type_Became_Opaque (Union)
    $HEADER1 .= "
        union UnionBecameOpaque
        {
            int i, j;
        };
        $DECL_SPEC int unionBecameOpaque(union UnionBecameOpaque* param);";
    $SOURCE1 .= "
        int unionBecameOpaque(union UnionBecameOpaque* param) { return 0; }";
    
    $HEADER2 .= "
        union UnionBecameOpaque;
        $DECL_SPEC int unionBecameOpaque(union UnionBecameOpaque* param);";
    $SOURCE2 .= "
        int unionBecameOpaque(union UnionBecameOpaque* param) { return 0; }";
    
    # Field_Type_Format
    $HEADER1 .= "
        struct DType1
        {
            int i;
            double j[7];
        };
        struct FieldTypeFormat
        {
            int i;
            struct DType1 j;
        };
        $DECL_SPEC int fieldTypeFormat(struct FieldTypeFormat param);";
    $SOURCE1 .= "
        int fieldTypeFormat(struct FieldTypeFormat param) { return 0; }";
    
    $HEADER2 .= "
        struct DType2
        {
            double i[7];
            int j;
        };
        struct FieldTypeFormat
        {
            int i;
            struct DType2 j;
        };
        $DECL_SPEC int fieldTypeFormat(struct FieldTypeFormat param);";
    $SOURCE2 .= "
        int fieldTypeFormat(struct FieldTypeFormat param) { return 0; }";
    
    # Field_Type_Format (func ptr)
    $HEADER1 .= "
        typedef void (*FuncPtr_Old) (int a);
        struct FieldTypeFormat_FuncPtr
        {
            int i;
            FuncPtr_Old j;
        };
        $DECL_SPEC int fieldTypeFormat_FuncPtr(struct FieldTypeFormat_FuncPtr param);";
    $SOURCE1 .= "
        int fieldTypeFormat_FuncPtr(struct FieldTypeFormat_FuncPtr param) { return 0; }";
    
    $HEADER2 .= "
        typedef void (*FuncPtr_New) (int a, int b);
        struct FieldTypeFormat_FuncPtr
        {
            int i;
            FuncPtr_New j;
        };
        $DECL_SPEC int fieldTypeFormat_FuncPtr(struct FieldTypeFormat_FuncPtr param);";
    $SOURCE2 .= "
        int fieldTypeFormat_FuncPtr(struct FieldTypeFormat_FuncPtr param) { return 0; }";
    
    # Removed_Virtual_Method (inline)
    $HEADER1 .= "
        class $DECL_SPEC RemovedInlineVirtualFunction {
        public:
            RemovedInlineVirtualFunction();
            virtual int removedMethod(int param) { return 0; }
            virtual int method(int param);
        };";
    $SOURCE1 .= "
        int RemovedInlineVirtualFunction::method(int param) { return param; }
        RemovedInlineVirtualFunction::RemovedInlineVirtualFunction() { }";
    
    $HEADER2 .= "
        class $DECL_SPEC RemovedInlineVirtualFunction {
        public:
            RemovedInlineVirtualFunction();
            virtual int method(int param);
        };";
    $SOURCE2 .= "
        int RemovedInlineVirtualFunction::method(int param) { return param; }
        RemovedInlineVirtualFunction::RemovedInlineVirtualFunction() { }";
    
    # MethodPtr
    $HEADER1 .= "
        class TestMethodPtr {
            public:
                typedef void (TestMethodPtr::*Method)(int*);
                Method _method;
                TestMethodPtr();
                void method();
        };";
    $SOURCE1 .= "
        TestMethodPtr::TestMethodPtr() { }
        void TestMethodPtr::method() { }";
    
    $HEADER2 .= "
        class TestMethodPtr {
            public:
                typedef void (TestMethodPtr::*Method)(int*, void*);
                Method _method;
                TestMethodPtr();
                void method();
        };";
    $SOURCE2 .= "
        TestMethodPtr::TestMethodPtr() { }
        void TestMethodPtr::method() { }";
    
    # FieldPtr
    $HEADER1 .= "
        class TestFieldPtr {
            public:
                typedef void* (TestFieldPtr::*Field);
                Field _field;
                TestFieldPtr();
                void method(void*);
        };";
    $SOURCE1 .= "
        TestFieldPtr::TestFieldPtr(){ }
        void TestFieldPtr::method(void*) { }";
    
    $HEADER2 .= "
        class TestFieldPtr {
            public:
                typedef int (TestFieldPtr::*Field);
                Field _field;
                TestFieldPtr();
                void method(void*);
        };";
    $SOURCE2 .= "
        TestFieldPtr::TestFieldPtr(){ }
        void TestFieldPtr::method(void*) { }";

    # Removed_Symbol (Template Specializations)
    $HEADER1 .= "
        template <unsigned int _TP, typename AAA>
        class Template {
            public:
                char const *field;
        };
        template <unsigned int _TP, typename AAA>
        class TestRemovedTemplate {
            public:
                char const *field;
                void method(int);
        };
        template <>
        class TestRemovedTemplate<7, char> {
            public:
                char const *field;
                void method(int);
        };";
    $SOURCE1 .= "
        void TestRemovedTemplate<7, char>::method(int){ }";

    # Removed_Symbol (Template Specializations)
    $HEADER1 .= "
        template <typename TName>
        int removedTemplateSpec(TName);

        template <> int removedTemplateSpec<char>(char);";
    $SOURCE1 .= "
        template <> int removedTemplateSpec<char>(char){return 0;}";
    
    # Removed_Field (Ref)
    $HEADER1 .= "
        struct TestRefChange {
            int a, b, c;
        };
        $DECL_SPEC int paramRefChange(const TestRefChange & p1, int p2);";
    $SOURCE1 .= "
        int paramRefChange(const TestRefChange & p1, int p2) { return p2; }";
    
    $HEADER2 .= "
        struct TestRefChange {
            int a, b;
        };
        $DECL_SPEC int paramRefChange(const TestRefChange & p1, int p2);";
    $SOURCE2 .= "
        int paramRefChange(const TestRefChange & p1, int p2) { return p2; }";
    
    # Removed_Parameter
    $HEADER1 .= "
        $DECL_SPEC int removedParameter(int param, int removed_param);";
    $SOURCE1 .= "
        int removedParameter(int param, int removed_param) { return 0; }";
    
    $HEADER2 .= "
        $DECL_SPEC int removedParameter(int param);";
    $SOURCE2 .= "
        int removedParameter(int param) { return 0; }";
    
    # Added_Parameter
    $HEADER1 .= "
        $DECL_SPEC int addedParameter(int param);";
    $SOURCE1 .= "
        int addedParameter(int param) { return 0; }";
    
    $HEADER2 .= "
        $DECL_SPEC int addedParameter(int param, int added_param);";
    $SOURCE2 .= "
        int addedParameter(int param, int added_param) { return 0; }";
    
    # Added
    $HEADER2 .= "
        typedef int (*FUNCPTR_TYPE)(int a, int b);
        $DECL_SPEC int addedFunc(FUNCPTR_TYPE*const** f);";
    $SOURCE2 .= "
        int addedFunc(FUNCPTR_TYPE*const** f) { return 0; }";
    
    # Added (3)
    $HEADER2 .= "
        struct DStruct
        {
            int i, j, k;
        };
        int addedFunc3(struct DStruct* p);";
    $SOURCE2 .= "
        int addedFunc3(struct DStruct* p) { return 0; }";
    
    # Added_Virtual_Method
    $HEADER1 .= "
        class $DECL_SPEC AddedVirtualMethod {
        public:
            virtual int method(int param);
        };";
    $SOURCE1 .= "
        int AddedVirtualMethod::method(int param) { return param; }";
    
    $HEADER2 .= "
        class $DECL_SPEC AddedVirtualMethod {
        public:
            virtual int addedMethod(int param);
            virtual int method(int param);
        };";
    $SOURCE2 .= "
        int AddedVirtualMethod::addedMethod(int param) {
            return param;
        }
        int AddedVirtualMethod::method(int param) { return param; }";

    # Added_Virtual_Method (added "virtual" attribute)
    $HEADER1 .= "
        class $DECL_SPEC BecameVirtualMethod {
        public:
            int becameVirtual(int param);
            virtual int method(int param);
        };";
    $SOURCE1 .= "
        int BecameVirtualMethod::becameVirtual(int param) { return param; }
        int BecameVirtualMethod::method(int param) { return param; }";
    
    $HEADER2 .= "
        class $DECL_SPEC BecameVirtualMethod {
        public:
            virtual int becameVirtual(int param);
            virtual int method(int param);
        };";
    $SOURCE2 .= "
        int BecameVirtualMethod::becameVirtual(int param) { return param; }
        int BecameVirtualMethod::method(int param) { return param; }";

    # Added_Pure_Virtual_Method
    $HEADER1 .= "
        class $DECL_SPEC AddedPureVirtualMethod {
        public:
            virtual int method(int param);
            int otherMethod(int param);
        };";
    $SOURCE1 .= "
        int AddedPureVirtualMethod::method(int param) { return param; }
        int AddedPureVirtualMethod::otherMethod(int param) { return param; }";
    
    $HEADER2 .= "
        class $DECL_SPEC AddedPureVirtualMethod {
        public:
            virtual int addedMethod(int param)=0;
            virtual int method(int param);
            int otherMethod(int param);
        };";
    $SOURCE2 .= "
        int AddedPureVirtualMethod::method(int param) { return param; }
        int AddedPureVirtualMethod::otherMethod(int param) { return param; }";

    # Added_Virtual_Method_At_End (Safe)
    $HEADER1 .= "
        class $DECL_SPEC AddedVirtualMethodAtEnd {
        public:
            AddedVirtualMethodAtEnd();
            int method1(int param);
            virtual int method2(int param);
        };";
    $SOURCE1 .= "
        AddedVirtualMethodAtEnd::AddedVirtualMethodAtEnd() { }
        int AddedVirtualMethodAtEnd::method1(int param) { return param; }
        int AddedVirtualMethodAtEnd::method2(int param) { return param; }";
    
    $HEADER2 .= "
        class $DECL_SPEC AddedVirtualMethodAtEnd {
        public:
            AddedVirtualMethodAtEnd();
            int method1(int param);
            virtual int method2(int param);
            virtual int addedMethod(int param);
        };";
    $SOURCE2 .= "
        AddedVirtualMethodAtEnd::AddedVirtualMethodAtEnd() { }
        int AddedVirtualMethodAtEnd::method1(int param) { return param; }
        int AddedVirtualMethodAtEnd::method2(int param) { return param; }
        int AddedVirtualMethodAtEnd::addedMethod(int param) { return param; }";

    # Added_Virtual_Method_At_End (With Default Constructor)
    $HEADER1 .= "
        class $DECL_SPEC AddedVirtualMethodAtEnd_DefaultConstructor {
        public:
            int method1(int param);
            virtual int method2(int param);
        };";
    $SOURCE1 .= "
        int AddedVirtualMethodAtEnd_DefaultConstructor::method1(int param) { return param; }
        int AddedVirtualMethodAtEnd_DefaultConstructor::method2(int param) { return param; }";
    
    $HEADER2 .= "
        class $DECL_SPEC AddedVirtualMethodAtEnd_DefaultConstructor {
        public:
            int method1(int param);
            virtual int method2(int param);
            virtual int addedMethod(int param);
        };";
    $SOURCE2 .= "
        int AddedVirtualMethodAtEnd_DefaultConstructor::method1(int param) { return param; }
        int AddedVirtualMethodAtEnd_DefaultConstructor::method2(int param) { return param; }
        int AddedVirtualMethodAtEnd_DefaultConstructor::addedMethod(int param) { return param; }";
    
    # Added_First_Virtual_Method
    $HEADER1 .= "
        class $DECL_SPEC AddedFirstVirtualMethod {
        public:
            int method(int param);
        };";
    $SOURCE1 .= "
        int AddedFirstVirtualMethod::method(int param) { return param; }";
    
    $HEADER2 .= "
        class $DECL_SPEC AddedFirstVirtualMethod {
        public:
            int method(int param);
            virtual int addedMethod(int param);
        };";
    $SOURCE2 .= "
        int AddedFirstVirtualMethod::method(int param) { return param; }
        int AddedFirstVirtualMethod::addedMethod(int param) { return param; }";
    
    # Removed_Virtual_Method
    $HEADER1 .= "
        class $DECL_SPEC RemovedVirtualFunction {
        public:
            int a, b, c;
            virtual int removedMethod(int param);
            virtual int vMethod(int param);
    };";
    $SOURCE1 .= "
        int RemovedVirtualFunction::removedMethod(int param) { return param; }
        int RemovedVirtualFunction::vMethod(int param) { return param; }";
    
    $HEADER2 .= "
        class $DECL_SPEC RemovedVirtualFunction {
        public:
            int a, b, c;
            int removedMethod(int param);
            virtual int vMethod(int param);
    };";
    $SOURCE2 .= "
        int RemovedVirtualFunction::removedMethod(int param) { return param; }
        int RemovedVirtualFunction::vMethod(int param) { return param; }";

    # Removed_Virtual_Method (Pure, From the End)
    $HEADER1 .= "
        class $DECL_SPEC RemovedPureVirtualMethodFromEnd {
        public:
            virtual int method(int param);
            virtual int removedMethod(int param)=0;
        };";
    $SOURCE1 .= "
        int RemovedPureVirtualMethodFromEnd::method(int param) { return param; }
        int RemovedPureVirtualMethodFromEnd::removedMethod(int param) { return param; }";
    
    $HEADER2 .= "
        class $DECL_SPEC RemovedPureVirtualMethodFromEnd
        {
        public:
            virtual int method(int param);
            int removedMethod(int param);
        };";
    $SOURCE2 .= "
        int RemovedPureVirtualMethodFromEnd::method(int param) { return param; }
        int RemovedPureVirtualMethodFromEnd::removedMethod(int param) { return param; }";

    # Removed_Symbol (Pure with Implementation)
    $HEADER1 .= "
        class $DECL_SPEC RemovedPureSymbol {
        public:
            virtual int method(int param);
            virtual int removedMethod(int param)=0;
        };";
    $SOURCE1 .= "
        int RemovedPureSymbol::method(int param) { return param; }
        int RemovedPureSymbol::removedMethod(int param) { return param; }";
    
    $HEADER2 .= "
        class $DECL_SPEC RemovedPureSymbol
        {
        public:
            virtual int method(int param);
        };";
    $SOURCE2 .= "
        int RemovedPureSymbol::method(int param) { return param; }";

    # Removed_Virtual_Method (From the End)
    $HEADER1 .= "
        class $DECL_SPEC RemovedVirtualMethodFromEnd {
        public:
            virtual int method(int param);
            virtual int removedMethod(int param);
        };";
    $SOURCE1 .= "
        int RemovedVirtualMethodFromEnd::method(int param) { return param; }
        int RemovedVirtualMethodFromEnd::removedMethod(int param) { return param; }";
    
    $HEADER2 .= "
        class $DECL_SPEC RemovedVirtualMethodFromEnd
        {
        public:
            virtual int method(int param);
            int removedMethod(int param);
        };";
    $SOURCE2 .= "
        int RemovedVirtualMethodFromEnd::method(int param) { return param; }
        int RemovedVirtualMethodFromEnd::removedMethod(int param) { return param; }";

    # Removed_Last_Virtual_Method
    $HEADER1 .= "
        class $DECL_SPEC RemovedLastVirtualMethod
        {
        public:
            int method(int param);
            virtual int removedMethod(int param);
        };";
    $SOURCE1 .= "
        int RemovedLastVirtualMethod::method(int param) { return param; }";
    $SOURCE1 .= "
        int RemovedLastVirtualMethod::removedMethod(int param) { return param; }";
    
    $HEADER2 .= "
        class $DECL_SPEC RemovedLastVirtualMethod
        {
        public:
            int method(int param);
            int removedMethod(int param);
        };";
    $SOURCE2 .= "
        int RemovedLastVirtualMethod::method(int param) { return param; }";
    $SOURCE2 .= "
        int RemovedLastVirtualMethod::removedMethod(int param) { return param; }";
    
    # Virtual_Table_Size
    $HEADER1 .= "
        class $DECL_SPEC VirtualTableSize
        {
        public:
            virtual int method1(int param);
            virtual int method2(int param);
        };
        class $DECL_SPEC VirtualTableSize_SubClass: public VirtualTableSize
        {
        public:
            virtual int method3(int param);
            virtual int method4(int param);
        };";
    $SOURCE1 .= "
        int VirtualTableSize::method1(int param) { return param; }
        int VirtualTableSize::method2(int param) { return param; }
        int VirtualTableSize_SubClass::method3(int param) { return param; }
        int VirtualTableSize_SubClass::method4(int param) { return param; }";
    
    $HEADER2 .= "
        class $DECL_SPEC VirtualTableSize
        {
        public:
            virtual int method1(int param);
            virtual int method2(int param);
            virtual int addedMethod(int param);
        };
        class $DECL_SPEC VirtualTableSize_SubClass: public VirtualTableSize
        {
        public:
            virtual int method3(int param);
            virtual int method4(int param);
        };";
    $SOURCE2 .= "
        int VirtualTableSize::method1(int param) { return param; }
        int VirtualTableSize::method2(int param) { return param; }
        int VirtualTableSize::addedMethod(int param) { return param; }
        int VirtualTableSize_SubClass::method3(int param) { return param; }
        int VirtualTableSize_SubClass::method4(int param) { return param; }";
    
    # Virtual_Method_Position
    $HEADER1 .= "
        class $DECL_SPEC VirtualMethodPosition
        {
        public:
            virtual int method1(int param);
            virtual int method2(int param);
        };";
    $SOURCE1 .= "
        int VirtualMethodPosition::method1(int param) { return param; }";
    $SOURCE1 .= "
        int VirtualMethodPosition::method2(int param) { return param; }";
    
    $HEADER2 .= "
        class $DECL_SPEC VirtualMethodPosition
        {
        public:
            virtual int method2(int param);
            virtual int method1(int param);
        };";
    $SOURCE2 .= "
        int VirtualMethodPosition::method1(int param) { return param; }";
    $SOURCE2 .= "
        int VirtualMethodPosition::method2(int param) { return param; }";

    # Pure_Virtual_Method_Position
    $HEADER1 .= "
        class $DECL_SPEC PureVirtualFunctionPosition {
        public:
            virtual int method1(int param)=0;
            virtual int method2(int param)=0;
            int method3(int param);
        };";
    $SOURCE1 .= "
        int PureVirtualFunctionPosition::method3(int param) { return method1(7)+method2(7); }";
    
    $HEADER2 .= "
        class $DECL_SPEC PureVirtualFunctionPosition {
        public:
            virtual int method2(int param)=0;
            virtual int method1(int param)=0;
            int method3(int param);
        };";
    $SOURCE2 .= "
        int PureVirtualFunctionPosition::method3(int param) { return method1(7)+method2(7); }";

    # Virtual_Method_Position
    $HEADER1 .= "
        class $DECL_SPEC VirtualFunctionPosition {
        public:
            virtual int method1(int param);
            virtual int method2(int param);
        };";
    $SOURCE1 .= "
        int VirtualFunctionPosition::method1(int param) { return 1; }
        int VirtualFunctionPosition::method2(int param) { return 2; }";
    
    $HEADER2 .= "
        class $DECL_SPEC VirtualFunctionPosition {
        public:
            virtual int method2(int param);
            virtual int method1(int param);
        };";
    $SOURCE2 .= "
        int VirtualFunctionPosition::method1(int param) { return 1; }
        int VirtualFunctionPosition::method2(int param) { return 2; }";
    
    # Virtual_Method_Position (safe)
    $HEADER1 .= "
        class $DECL_SPEC VirtualFunctionPositionSafe_Base {
        public:
            virtual int method1(int param);
            virtual int method2(int param);
        };
        class $DECL_SPEC VirtualFunctionPositionSafe: public VirtualFunctionPositionSafe_Base {
        public:
            virtual int method1(int param);
            virtual int method2(int param);
        };";
    $SOURCE1 .= "
        int VirtualFunctionPositionSafe_Base::method1(int param) { return param; }
        int VirtualFunctionPositionSafe_Base::method2(int param) { return param; }
        int VirtualFunctionPositionSafe::method1(int param) { return param; }
        int VirtualFunctionPositionSafe::method2(int param) { return param; }";
    
    $HEADER2 .= "
        class $DECL_SPEC VirtualFunctionPositionSafe_Base {
        public:
            virtual int method1(int param);
            virtual int method2(int param);
        };
        class $DECL_SPEC VirtualFunctionPositionSafe: public VirtualFunctionPositionSafe_Base {
        public:
            virtual int method2(int param);
            virtual int method1(int param);
        };";
    $SOURCE2 .= "
        int VirtualFunctionPositionSafe_Base::method1(int param) { return param; }
        int VirtualFunctionPositionSafe_Base::method2(int param) { return param; }
        int VirtualFunctionPositionSafe::method1(int param) { return param; }
        int VirtualFunctionPositionSafe::method2(int param) { return param; }";
    
    # Overridden_Virtual_Method
    $HEADER1 .= "
        class $DECL_SPEC OverriddenVirtualMethod_Base {
        public:
            virtual int method1(int param);
            virtual int method2(int param);
        };
        class $DECL_SPEC OverriddenVirtualMethod: public OverriddenVirtualMethod_Base {
        public:
            OverriddenVirtualMethod();
            virtual int method3(int param);
        };";
    $SOURCE1 .= "
        int OverriddenVirtualMethod_Base::method1(int param) { return param; }
        int OverriddenVirtualMethod_Base::method2(int param) { return param; }
        OverriddenVirtualMethod::OverriddenVirtualMethod() {}
        int OverriddenVirtualMethod::method3(int param) { return param; }";
    
    $HEADER2 .= "
        class $DECL_SPEC OverriddenVirtualMethod_Base {
        public:
            virtual int method1(int param);
            virtual int method2(int param);
        };
        class $DECL_SPEC OverriddenVirtualMethod:public OverriddenVirtualMethod_Base {
            OverriddenVirtualMethod();
            virtual int method2(int param);
            virtual int method3(int param);
        };";
    $SOURCE2 .= "
        int OverriddenVirtualMethod_Base::method1(int param) { return param; }
        int OverriddenVirtualMethod_Base::method2(int param) { return param; }
        OverriddenVirtualMethod::OverriddenVirtualMethod() {}
        int OverriddenVirtualMethod::method2(int param) { return param; }
        int OverriddenVirtualMethod::method3(int param) { return param; }";

    # Overridden_Virtual_Method_B (+ removed)
    $HEADER1 .= "
        
    class $DECL_SPEC OverriddenVirtualMethodB: public OverriddenVirtualMethod_Base {
        public:
            OverriddenVirtualMethodB();
            virtual int method2(int param);
            virtual int method3(int param);
    };";
    $SOURCE1 .= "
        OverriddenVirtualMethodB::OverriddenVirtualMethodB() {}
        int OverriddenVirtualMethodB::method2(int param) { return param; }
        int OverriddenVirtualMethodB::method3(int param) { return param; }";
    
    $HEADER2 .= "
        
    class $DECL_SPEC OverriddenVirtualMethodB:public OverriddenVirtualMethod_Base {
        public:
            OverriddenVirtualMethodB();
            virtual int method3(int param);
    };";
    $SOURCE2 .= "
        OverriddenVirtualMethodB::OverriddenVirtualMethodB() {}
        int OverriddenVirtualMethodB::method3(int param) { return param; }";
    
    # Size
    $HEADER1 .= "
        struct $DECL_SPEC TypeSize
        {
        public:
            TypeSize method(TypeSize param);
            int i[5];
            long j;
            double k;
            TypeSize* p;
        };";
    $SOURCE1 .= "
        TypeSize TypeSize::method(TypeSize param) { return param; }";
    
    $HEADER2 .= "
        struct $DECL_SPEC TypeSize
        {
        public:
            TypeSize method(TypeSize param);
            int i[15];
            long j;
            double k;
            TypeSize* p;
            int added_member;
        };";
    $SOURCE2 .= "
        TypeSize TypeSize::method(TypeSize param) { return param; }";

    # Size_Of_Allocable_Class_Increased
    $HEADER1 .= "
        class $DECL_SPEC AllocableClassSize
        {
        public:
            AllocableClassSize();
            int method();
            double p[5];
        };";
    $SOURCE1 .= "
        AllocableClassSize::AllocableClassSize() { }";
    $SOURCE1 .= "
        int AllocableClassSize::method() { return 0; }";
    
    $HEADER2 .= "
        struct $DECL_SPEC AllocableClassSize
        {
        public:
            AllocableClassSize();
            int method();
            double p[15];
        };";
    $SOURCE2 .= "
        AllocableClassSize::AllocableClassSize() { }";
    $SOURCE2 .= "
        int AllocableClassSize::method() { return 0; }";
    
    # Size_Of_Allocable_Class_Decreased (decreased size, has derived class, has public members)
    $HEADER1 .= "
        class $DECL_SPEC DecreasedClassSize
        {
        public:
            DecreasedClassSize();
            int method();
            double p[15];
        };";
    $SOURCE1 .= "
        DecreasedClassSize::DecreasedClassSize() { }";
    $SOURCE1 .= "
        int DecreasedClassSize::method() { return 0; }";
    $HEADER1 .= "
        class $DECL_SPEC DecreasedClassSize_SubClass: public DecreasedClassSize
        {
        public:
            DecreasedClassSize_SubClass();
            int method();
            int f;
        };";
    $SOURCE1 .= "
        DecreasedClassSize_SubClass::DecreasedClassSize_SubClass() { f=7; }";
    $SOURCE1 .= "
        int DecreasedClassSize_SubClass::method() { return f; }";
    
    $HEADER2 .= "
        struct $DECL_SPEC DecreasedClassSize
        {
        public:
            DecreasedClassSize();
            int method();
            double p[5];
        };";
    $SOURCE2 .= "
        DecreasedClassSize::DecreasedClassSize() { }";
    $SOURCE2 .= "
        int DecreasedClassSize::method() { return 0; }";
    $HEADER2 .= "
        class $DECL_SPEC DecreasedClassSize_SubClass: public DecreasedClassSize
        {
        public:
            DecreasedClassSize_SubClass();
            int method();
            int f;
        };";
    $SOURCE2 .= "
        DecreasedClassSize_SubClass::DecreasedClassSize_SubClass() { f=7; }";
    $SOURCE2 .= "
        int DecreasedClassSize_SubClass::method() { return f; }";

    # Size_Of_Copying_Class
    $HEADER1 .= "
        class $DECL_SPEC CopyingClassSize
        {
        public:
            int method();
            int p[5];
        };";
    $SOURCE1 .= "
        int CopyingClassSize::method() { return p[4]; }";
    
    $HEADER2 .= "
        struct $DECL_SPEC CopyingClassSize
        {
        public:
            int method();
            int p[15];
        };";
    $SOURCE2 .= "
        int CopyingClassSize::method() { return p[10]; }";

    # Base_Class_Became_Virtually_Inherited
    $HEADER1 .= "
        class $DECL_SPEC BecameVirtualBase
        {
        public:
            BecameVirtualBase();
            int method();
            double p[5];
        };";
    $SOURCE1 .= "
        BecameVirtualBase::BecameVirtualBase() { }";
    $SOURCE1 .= "
        int BecameVirtualBase::method() { return 0; }";
    $HEADER1 .= "
        class $DECL_SPEC AddedVirtualBase1:public BecameVirtualBase
        {
        public:
            AddedVirtualBase1();
            int method();
        };";
    $SOURCE1 .= "
        AddedVirtualBase1::AddedVirtualBase1() { }";
    $SOURCE1 .= "
        int AddedVirtualBase1::method() { return 0; }";
    $HEADER1 .= "
        class $DECL_SPEC AddedVirtualBase2: public BecameVirtualBase
        {
        public:
            AddedVirtualBase2();
            int method();
        };";
    $SOURCE1 .= "
        AddedVirtualBase2::AddedVirtualBase2() { }";
    $SOURCE1 .= "
        int AddedVirtualBase2::method() { return 0; }";
    $HEADER1 .= "
        class $DECL_SPEC BaseClassBecameVirtuallyInherited:public AddedVirtualBase1, public AddedVirtualBase2
        {
        public:
            BaseClassBecameVirtuallyInherited();
        };";
    $SOURCE1 .= "
        BaseClassBecameVirtuallyInherited::BaseClassBecameVirtuallyInherited() { }";
    
    $HEADER2 .= "
        class $DECL_SPEC BecameVirtualBase
        {
        public:
            BecameVirtualBase();
            int method();
            double p[5];
        };";
    $SOURCE2 .= "
        BecameVirtualBase::BecameVirtualBase() { }";
    $SOURCE2 .= "
        int BecameVirtualBase::method() { return 0; }";
    $HEADER2 .= "
        class $DECL_SPEC AddedVirtualBase1:public virtual BecameVirtualBase
        {
        public:
            AddedVirtualBase1();
            int method();
        };";
    $SOURCE2 .= "
        AddedVirtualBase1::AddedVirtualBase1() { }";
    $SOURCE2 .= "
        int AddedVirtualBase1::method() { return 0; }";
    $HEADER2 .= "
        class $DECL_SPEC AddedVirtualBase2: public virtual BecameVirtualBase
        {
        public:
            AddedVirtualBase2();
            int method();
        };";
    $SOURCE2 .= "
        AddedVirtualBase2::AddedVirtualBase2() { }";
    $SOURCE2 .= "
        int AddedVirtualBase2::method() { return 0; }";
    $HEADER2 .= "
        class $DECL_SPEC BaseClassBecameVirtuallyInherited:public AddedVirtualBase1, public AddedVirtualBase2
        {
        public:
            BaseClassBecameVirtuallyInherited();
        };";
    $SOURCE2 .= "
        BaseClassBecameVirtuallyInherited::BaseClassBecameVirtuallyInherited() { }";

    # Added_Base_Class, Removed_Base_Class
    $HEADER1 .= "
        class $DECL_SPEC BaseClass
        {
        public:
            BaseClass();
            int method();
            double p[5];
        };
        class $DECL_SPEC RemovedBaseClass
        {
        public:
            RemovedBaseClass();
            int method();
        };
        class $DECL_SPEC ChangedBaseClass:public BaseClass, public RemovedBaseClass
        {
        public:
            ChangedBaseClass();
        };";
    $SOURCE1 .= "
        BaseClass::BaseClass() { }
        int BaseClass::method() { return 0; }
        RemovedBaseClass::RemovedBaseClass() { }
        int RemovedBaseClass::method() { return 0; }
        ChangedBaseClass::ChangedBaseClass() { }";
    
    $HEADER2 .= "
        class $DECL_SPEC BaseClass
        {
        public:
            BaseClass();
            int method();
            double p[5];
        };
        class $DECL_SPEC AddedBaseClass
        {
        public:
            AddedBaseClass();
            int method();
        };
        class $DECL_SPEC ChangedBaseClass:public BaseClass, public AddedBaseClass
        {
        public:
            ChangedBaseClass();
        };";
    $SOURCE2 .= "
        BaseClass::BaseClass() { }
        int BaseClass::method() { return 0; }
        AddedBaseClass::AddedBaseClass() { }
        int AddedBaseClass::method() { return 0; }
        ChangedBaseClass::ChangedBaseClass() { }";

    # Added_Base_Class_And_Shift, Removed_Base_Class_And_Shift
    $HEADER1 .= "
        struct $DECL_SPEC BaseClass2
        {
            BaseClass2();
            int method();
            double p[15];
        };
        class $DECL_SPEC ChangedBaseClassAndSize:public BaseClass
        {
        public:
            ChangedBaseClassAndSize();
        };";
    $SOURCE1 .= "
        BaseClass2::BaseClass2() { }
        int BaseClass2::method() { return 0; }
        ChangedBaseClassAndSize::ChangedBaseClassAndSize() { }";
    
    $HEADER2 .= "
        struct $DECL_SPEC BaseClass2
        {
            BaseClass2();
            int method();
            double p[15];
        };
        class $DECL_SPEC ChangedBaseClassAndSize:public BaseClass2
        {
        public:
            ChangedBaseClassAndSize();
        };";
    $SOURCE2 .= "
        BaseClass2::BaseClass2() { }
        int BaseClass2::method() { return 0; }
        ChangedBaseClassAndSize::ChangedBaseClassAndSize() { }";
    
    # Added_Field_And_Size
    $HEADER1 .= "
        struct $DECL_SPEC AddedFieldAndSize
        {
            int method(AddedFieldAndSize param);
            double i, j, k;
            AddedFieldAndSize* p;
        };";
    $SOURCE1 .= "
        int AddedFieldAndSize::method(AddedFieldAndSize param) { return 0; }";
    
    $HEADER2 .= "
        struct $DECL_SPEC AddedFieldAndSize
        {
            int method(AddedFieldAndSize param);
            double i, j, k;
            AddedFieldAndSize* p;
            int added_member1;
            long long added_member2;
        };";
    $SOURCE2 .= "
        int AddedFieldAndSize::method(AddedFieldAndSize param) { return 0; }";
    
    # Added_Field
    $HEADER1 .= "
        class $DECL_SPEC ObjectAddedMember
        {
        public:
            int method(int param);
            double i, j, k;
            AddedFieldAndSize* p;
        };";
    $SOURCE1 .= "
        int ObjectAddedMember::method(int param) { return param; }";
    
    $HEADER2 .= "
        class $DECL_SPEC ObjectAddedMember
        {
        public:
            int method(int param);
            double i, j, k;
            AddedFieldAndSize* p;
            int added_member1;
            long long added_member2;
        };";
    $SOURCE2 .= "
        int ObjectAddedMember::method(int param) { return param; }";
    
    # Added_Field (safe)
    $HEADER1 .= "
        struct $DECL_SPEC AddedBitfield
        {
            int method(AddedBitfield param);
            double i, j, k;
            int b1 : 32;
            int b2 : 31;
            AddedBitfield* p;
        };";
    $SOURCE1 .= "
        int AddedBitfield::method(AddedBitfield param) { return 0; }";
    
    $HEADER2 .= "
        struct $DECL_SPEC AddedBitfield
        {
            int method(AddedBitfield param);
            double i, j, k;
            int b1 : 32;
            int b2 : 31;
            int added_bitfield : 1;
            int added_bitfield2 : 1;
            AddedBitfield* p;
        };";
    $SOURCE2 .= "
        int AddedBitfield::method(AddedBitfield param) { return 0; }";
    
    # Bit_Field_Size
    $HEADER1 .= "
        struct $DECL_SPEC BitfieldSize
        {
            int method(BitfieldSize param);
            short changed_bitfield : 1;
        };";
    $SOURCE1 .= "
        int BitfieldSize::method(BitfieldSize param) { return 0; }";
    
    $HEADER2 .= "
        struct $DECL_SPEC BitfieldSize
        {
            int method(BitfieldSize param);
            short changed_bitfield : 7;
        };";
    $SOURCE2 .= "
        int BitfieldSize::method(BitfieldSize param) { return 0; }";
    
    # Removed_Field
    $HEADER1 .= "
        struct $DECL_SPEC RemovedBitfield
        {
            int method(RemovedBitfield param);
            double i, j, k;
            int b1 : 32;
            int b2 : 31;
            int removed_bitfield : 1;
            RemovedBitfield* p;
        };";
    $SOURCE1 .= "
        int RemovedBitfield::method(RemovedBitfield param) { return 0; }";
    
    $HEADER2 .= "
        struct $DECL_SPEC RemovedBitfield
        {
            int method(RemovedBitfield param);
            double i, j, k;
            int b1 : 32;
            int b2 : 31;
            RemovedBitfield* p;
        };";
    $SOURCE2 .= "
        int RemovedBitfield::method(RemovedBitfield param) { return 0; }";
        
    # Removed_Middle_Field
    $HEADER1 .= "
        struct $DECL_SPEC RemovedMiddleBitfield
        {
            int method(RemovedMiddleBitfield param);
            double i, j, k;
            int b1 : 32;
            int removed_middle_bitfield : 1;
            int b2 : 31;
            RemovedMiddleBitfield* p;
        };";
    $SOURCE1 .= "
        int RemovedMiddleBitfield::method(RemovedMiddleBitfield param) { return 0; }";
    
    $HEADER2 .= "
        struct $DECL_SPEC RemovedMiddleBitfield
        {
            int method(RemovedMiddleBitfield param);
            double i, j, k;
            int b1 : 32;
            int b2 : 31;
            RemovedMiddleBitfield* p;
        };";
    $SOURCE2 .= "
        int RemovedMiddleBitfield::method(RemovedMiddleBitfield param) { return 0; }";
    
    # Added_Middle_Field_And_Size
    $HEADER1 .= "
        struct $DECL_SPEC AddedMiddleFieldAndSize
        {
            int method(AddedMiddleFieldAndSize param);
            int i;
            long j;
            double k;
            AddedMiddleFieldAndSize* p;
        };";
    $SOURCE1 .= "
        int AddedMiddleFieldAndSize::method(AddedMiddleFieldAndSize param) { return 0; }";
    
    $HEADER2 .= "
        struct $DECL_SPEC AddedMiddleFieldAndSize
        {
            int method(AddedMiddleFieldAndSize param);
            int i;
            int added_middle_member;
            long j;
            double k;
            AddedMiddleFieldAndSize* p;
        };";
    $SOURCE2 .= "
        int AddedMiddleFieldAndSize::method(AddedMiddleFieldAndSize param) { return 0; }";
        
    # Added_Field (padding)
    $HEADER1 .= "
        struct $DECL_SPEC AddedMiddlePaddedField
        {
            int method(int param);
            short i;
            long j;
            double k;
        };";
    $SOURCE1 .= "
        int AddedMiddlePaddedField::method(int param) { return 0; }";
    
    $HEADER2 .= "
        struct $DECL_SPEC AddedMiddlePaddedField
        {
            int method(int param);
            short i;
            short added_padded_field;
            long j;
            double k;
        };";
    $SOURCE2 .= "
        int AddedMiddlePaddedField::method(int param) { return 0; }";
        
    # Added_Field (tail padding)
    $HEADER1 .= "
        struct $DECL_SPEC AddedTailField
        {
            int method(int param);
            int i1, i2, i3, i4, i5, i6, i7;
            short s;
        };";
    $SOURCE1 .= "
        int AddedTailField::method(int param) { return 0; }";
    
    $HEADER2 .= "
        struct $DECL_SPEC AddedTailField
        {
            int method(int param);
            int i1, i2, i3, i4, i5, i6, i7;
            short s;
            short added_tail_field;
        };";
    $SOURCE2 .= "
        int AddedTailField::method(int param) { return 0; }";
        
    # Test Alignment
    $HEADER1 .= "
        struct $DECL_SPEC TestAlignment
        {
            int method(int param);
            short s:9;
            short   j:9;
            char  c;
            short t:9;
            short u:9;
            char d;
        };";
    $SOURCE1 .= "
        int TestAlignment::method(int param) { return 0; }";
    
    $HEADER2 .= "
        struct $DECL_SPEC TestAlignment
        {
            int method(int param);
            short s:9;
            short   j:9;
            char  c;
            short t:9;
            short u:9;
            char d;
        };";
    $SOURCE2 .= "
        int TestAlignment::method(int param) { return 0; }";
    
    # Renamed_Field
    $HEADER1 .= "
        struct $DECL_SPEC RenamedField
        {
            int method(RenamedField param);
            long i;
            long j;
            double k;
            RenamedField* p;
        };";
    $SOURCE1 .= "
        int RenamedField::method(RenamedField param) { return 0; }";
    
    $HEADER2 .= "
        struct $DECL_SPEC RenamedField
        {
            int method(RenamedField param);
            long renamed_member;
            long j;
            double k;
            RenamedField* p;
        };";
    $SOURCE2 .= "
        int RenamedField::method(RenamedField param) { return 0; }";
    
    # Removed_Field_And_Size
    $HEADER1 .= "
        struct $DECL_SPEC RemovedFieldAndSize
        {
            int method(RemovedFieldAndSize param);
            double i, j, k;
            RemovedFieldAndSize* p;
            int removed_member1;
            long removed_member2;
        };";
    $SOURCE1 .= "
        int RemovedFieldAndSize::method(RemovedFieldAndSize param) { return 0; }";
    
    $HEADER2 .= "
        struct $DECL_SPEC RemovedFieldAndSize
        {
            int method(RemovedFieldAndSize param);
            double i, j, k;
            RemovedFieldAndSize* p;
        };";
    $SOURCE2 .= "
        int RemovedFieldAndSize::method(RemovedFieldAndSize param) { return 0; }";
        
    # Field Position
    $HEADER1 .= "
        struct $DECL_SPEC MovedField
        {
            int method(int param);
            double i;
            int j;
        };";
    $SOURCE1 .= "
        int MovedField::method(int param) { return 0; }";
    
    $HEADER2 .= "
        struct $DECL_SPEC MovedField
        {
            int method(int param);
            int j;
            double i;
        };";
    $SOURCE2 .= "
        int MovedField::method(int param) { return 0; }";
    
    # Removed_Middle_Field_And_Size
    $HEADER1 .= "
        struct $DECL_SPEC RemovedMiddleFieldAndSize
        {
            int method(RemovedMiddleFieldAndSize param);
            int i;
            int removed_middle_member;
            long j;
            double k;
            RemovedMiddleFieldAndSize* p;
        };";
    $SOURCE1 .= "
        int RemovedMiddleFieldAndSize::method(RemovedMiddleFieldAndSize param) { return 0; }";
    
    $HEADER2 .= "
        struct $DECL_SPEC RemovedMiddleFieldAndSize
        {
            int method(RemovedMiddleFieldAndSize param);
            int i;
            long j;
            double k;
            RemovedMiddleFieldAndSize* p;
        };";
    $SOURCE2 .= "
        int RemovedMiddleFieldAndSize::method(RemovedMiddleFieldAndSize param) { return 0; }";
    
    # Enum_Member_Value
    $HEADER1 .= "
        enum EnumMemberValue
        {
            MEMBER_1=1,
            MEMBER_2=2
        };";
    $HEADER1 .= "
        $DECL_SPEC int enumMemberValueChange(enum EnumMemberValue param);";
    $SOURCE1 .= "
        int enumMemberValueChange(enum EnumMemberValue param) { return 0; }";
    
    $HEADER2 .= "
        enum EnumMemberValue
        {
            MEMBER_1=2,
            MEMBER_2=1
        };";
    $HEADER2 .= "
        $DECL_SPEC int enumMemberValueChange(enum EnumMemberValue param);";
    $SOURCE2 .= "
        int enumMemberValueChange(enum EnumMemberValue param) { return 0; }";
    
    # Enum_Member_Name
    $HEADER1 .= "
        enum EnumMemberRename
        {
            BRANCH_1=1,
            BRANCH_2=2
        };";
    $HEADER1 .= "
        $DECL_SPEC int enumMemberRename(enum EnumMemberRename param);";
    $SOURCE1 .= "
        int enumMemberRename(enum EnumMemberRename param) { return 0; }";
    
    $HEADER2 .= "
        enum EnumMemberRename
        {
            BRANCH_FIRST=1,
            BRANCH_SECOND=2
        };";
    $HEADER2 .= "
        $DECL_SPEC int enumMemberRename(enum EnumMemberRename param);";
    $SOURCE2 .= "
        int enumMemberRename(enum EnumMemberRename param) { return 0; }";
    
    # Field_Type_And_Size
    $HEADER1 .= "
        struct $DECL_SPEC FieldTypeAndSize
        {
            int method(FieldTypeAndSize param);
            int i;
            long j;
            double k;
            FieldTypeAndSize* p;
        };";
    $SOURCE1 .= "
        int FieldTypeAndSize::method(FieldTypeAndSize param) { return 0; }";
    
    $HEADER2 .= "
        struct $DECL_SPEC FieldTypeAndSize
        {
            int method(FieldTypeAndSize param);
            long long i;
            long j;
            double k;
            FieldTypeAndSize* p;
        };";
    $SOURCE2 .= "
        int FieldTypeAndSize::method(FieldTypeAndSize param) { return 0; }";
    
    # Member_Type
    $HEADER1 .= "
        struct $DECL_SPEC MemberType
        {
            int method(MemberType param);
            int i;
            long j;
            double k;
            MemberType* p;
        };";
    $SOURCE1 .= "
        int MemberType::method(MemberType param) { return 0; }";
    
    $HEADER2 .= "
        struct $DECL_SPEC MemberType
        {
            int method(MemberType param);
            float i;
            long j;
            double k;
            MemberType* p;
        };";
    $SOURCE2 .= "
        int MemberType::method(MemberType param) { return 0; }";
    
    # Field_BaseType
    $HEADER1 .= "
        struct $DECL_SPEC FieldBaseType
        {
            int method(FieldBaseType param);
            int *i;
            long j;
            double k;
            FieldBaseType* p;
        };";
    $SOURCE1 .= "
        int FieldBaseType::method(FieldBaseType param) { return 0; }";
    
    $HEADER2 .= "
        struct $DECL_SPEC FieldBaseType
        {
            int method(FieldBaseType param);
            long long *i;
            long j;
            double k;
            FieldBaseType* p;
        };";
    $SOURCE2 .= "
        int FieldBaseType::method(FieldBaseType param) { return 0; }";
    
    # Field_PointerLevel_Increased (and size)
    $HEADER1 .= "
        struct $DECL_SPEC FieldPointerLevelAndSize
        {
            int method(FieldPointerLevelAndSize param);
            long long i;
            long j;
            double k;
            FieldPointerLevelAndSize* p;
        };";
    $SOURCE1 .= "
        int FieldPointerLevelAndSize::method(FieldPointerLevelAndSize param) { return 0; }";
    
    $HEADER2 .= "
        struct $DECL_SPEC FieldPointerLevelAndSize
        {
            int method(FieldPointerLevelAndSize param);
            long long *i;
            long j;
            double k;
            FieldPointerLevelAndSize* p;
        };";
    $SOURCE2 .= "
        int FieldPointerLevelAndSize::method(FieldPointerLevelAndSize param) { return 0; }";
    
    # Field_PointerLevel
    $HEADER1 .= "
        struct $DECL_SPEC FieldPointerLevel
        {
            int method(FieldPointerLevel param);
            int **i;
            long j;
            double k;
            FieldPointerLevel* p;
        };";
    $SOURCE1 .= "
        int FieldPointerLevel::method(FieldPointerLevel param) { return 0; }";
    
    $HEADER2 .= "
        struct $DECL_SPEC FieldPointerLevel
        {
            int method(FieldPointerLevel param);
            int *i;
            long j;
            double k;
            FieldPointerLevel* p;
        };";
    $SOURCE2 .= "
        int FieldPointerLevel::method(FieldPointerLevel param) { return 0; }";
    
    # Added_Interface (method)
    $HEADER1 .= "
        struct $DECL_SPEC AddedInterface
        {
            int method(AddedInterface param);
            int i;
            long j;
            double k;
            AddedInterface* p;
        };";
    $SOURCE1 .= "
        int AddedInterface::method(AddedInterface param) { return 0; }";
    
    $HEADER2 .= "
        struct $DECL_SPEC AddedInterface
        {
            int method(AddedInterface param);
            int added_func(AddedInterface param);
            int i;
            long j;
            double k;
            AddedInterface* p;
        };";
    $SOURCE2 .= "
        int AddedInterface::method(AddedInterface param) { return 0; }";
    $SOURCE2 .= "
        int AddedInterface::added_func(AddedInterface param) { return 0; }";
    
    # Added_Interface (function)
    $HEADER2 .= "
        $DECL_SPEC int addedFunc2(void *** param);";
    $SOURCE2 .= "
        int addedFunc2(void *** param) { return 0; }";
    
    # Added_Interface (global variable)
    $HEADER1 .= "
        struct $DECL_SPEC AddedVariable
        {
            int method(AddedVariable param);
            int i1, i2;
            long j;
            double k;
            AddedVariable* p;
        };";
    $SOURCE1 .= "
        int AddedVariable::method(AddedVariable param) {
            return i1;
        }";
    
    $HEADER2 .= "
        struct $DECL_SPEC AddedVariable
        {
            int method(AddedVariable param);
            static int i1;
            static int i2;
            long j;
            double k;
            AddedVariable* p;
        };";
    $SOURCE2 .= "
        int AddedVariable::method(AddedVariable param) { return AddedVariable::i1; }";
    $SOURCE2 .= "
        int AddedVariable::i1=0;";
    $SOURCE2 .= "
        int AddedVariable::i2=0;";
    
    # Removed_Interface (method)
    $HEADER1 .= "
        struct $DECL_SPEC RemovedInterface
        {
            int method(RemovedInterface param);
            int removed_func(RemovedInterface param);
            int i;
            long j;
            double k;
            RemovedInterface* p;
        };";
    $SOURCE1 .= "
        int RemovedInterface::method(RemovedInterface param) { return 0; }";
    $SOURCE1 .= "
        int RemovedInterface::removed_func(RemovedInterface param) { return 0; }";
    
    $HEADER2 .= "
        struct $DECL_SPEC RemovedInterface
        {
            int method(RemovedInterface param);
            int i;
            long j;
            double k;
            RemovedInterface* p;
        };";
    $SOURCE2 .= "
        int RemovedInterface::method(RemovedInterface param) { return 0; }";
    
    # Removed_Interface (function)
    $HEADER1 .= "
        $DECL_SPEC int removedFunc2(void *** param);";
    $SOURCE1 .= "
        int removedFunc2(void *** param) { return 0; }";
    
    # Method_Became_Static
    $HEADER1 .= "
        struct $DECL_SPEC MethodBecameStatic
        {
            MethodBecameStatic becameStatic(MethodBecameStatic param);
            int **i;
            long j;
            double k;
            MethodBecameStatic* p;
        };";
    $SOURCE1 .= "
        MethodBecameStatic MethodBecameStatic::becameStatic(MethodBecameStatic param) { return param; }";
    
    $HEADER2 .= "
        struct $DECL_SPEC MethodBecameStatic
        {
            static MethodBecameStatic becameStatic(MethodBecameStatic param);
            int **i;
            long j;
            double k;
            MethodBecameStatic* p;
        };";
    $SOURCE2 .= "
        MethodBecameStatic MethodBecameStatic::becameStatic(MethodBecameStatic param) { return param; }";
    
    # Method_Became_Non_Static
    $HEADER1 .= "
        struct $DECL_SPEC MethodBecameNonStatic
        {
            static MethodBecameNonStatic becameNonStatic(MethodBecameNonStatic param);
            int **i;
            long j;
            double k;
            MethodBecameNonStatic* p;
        };";
    $SOURCE1 .= "
        MethodBecameNonStatic MethodBecameNonStatic::becameNonStatic(MethodBecameNonStatic param) { return param; }";
    
    $HEADER2 .= "
        struct $DECL_SPEC MethodBecameNonStatic
        {
            MethodBecameNonStatic becameNonStatic(MethodBecameNonStatic param);
            int **i;
            long j;
            double k;
            MethodBecameNonStatic* p;
        };";
    $SOURCE2 .= "
        MethodBecameNonStatic MethodBecameNonStatic::becameNonStatic(MethodBecameNonStatic param) { return param; }";
    
    # Parameter_Type_And_Size
    $HEADER1 .= "
        $DECL_SPEC int funcParameterTypeAndSize(int param, int other_param);";
    $SOURCE1 .= "
        int funcParameterTypeAndSize(int param, int other_param) { return other_param; }";
    
    $HEADER2 .= "
        $DECL_SPEC int funcParameterTypeAndSize(long long param, int other_param);";
    $SOURCE2 .= "
        int funcParameterTypeAndSize(long long param, int other_param) { return other_param; }";
    
    # Parameter_Type
    $HEADER1 .= "
        $DECL_SPEC int funcParameterType(int param, int other_param);";
    $SOURCE1 .= "
        int funcParameterType(int param, int other_param) { return other_param; }";
    
    $HEADER2 .= "
        $DECL_SPEC int funcParameterType(float param, int other_param);";
    $SOURCE2 .= "
        int funcParameterType(float param, int other_param) { return other_param; }";
    
    # Parameter_BaseType
    $HEADER1 .= "
        $DECL_SPEC int funcParameterBaseType(int *param);";
    $SOURCE1 .= "
        int funcParameterBaseType(int *param) { return sizeof(*param); }";
    
    $HEADER2 .= "
        $DECL_SPEC int funcParameterBaseType(long long *param);";
    $SOURCE2 .= "
        int funcParameterBaseType(long long *param) { return sizeof(*param); }";
    
    # Parameter_PointerLevel
    $HEADER1 .= "
        $DECL_SPEC long long funcParameterPointerLevelAndSize(long long param);";
    $SOURCE1 .= "
        long long funcParameterPointerLevelAndSize(long long param) { return param; }";
    
    $HEADER2 .= "
        $DECL_SPEC long long funcParameterPointerLevelAndSize(long long *param);";
    $SOURCE2 .= "
        long long funcParameterPointerLevelAndSize(long long *param) { return param[5]; }";
    
    # Parameter_PointerLevel
    $HEADER1 .= "
        $DECL_SPEC int funcParameterPointerLevel(int *param);";
    $SOURCE1 .= "
        int funcParameterPointerLevel(int *param) { return param[5]; }";
    
    $HEADER2 .= "
        $DECL_SPEC int funcParameterPointerLevel(int **param);";
    $SOURCE2 .= "
        int funcParameterPointerLevel(int **param) { return param[5][5]; }";
    
    # Return_Type_And_Size
    $HEADER1 .= "
        $DECL_SPEC int funcReturnTypeAndSize(int param);";
    $SOURCE1 .= "
        int funcReturnTypeAndSize(int param) { return 0; }";
    
    $HEADER2 .= "
        $DECL_SPEC long long funcReturnTypeAndSize(int param);";
    $SOURCE2 .= "
        long long funcReturnTypeAndSize(int param) { return 0; }";
    
    # Return_Type
    $HEADER1 .= "
        $DECL_SPEC int funcReturnType(int param);";
    $SOURCE1 .= "
        int funcReturnType(int param) { return 0; }";
    
    $HEADER2 .= "
        $DECL_SPEC float funcReturnType(int param);";
    $SOURCE2 .= "
        float funcReturnType(int param) { return 0.7; }";

    # Return_Type_Became_Void ("int" to "void")
    $HEADER1 .= "
        $DECL_SPEC int funcReturnTypeBecameVoid(int param);";
    $SOURCE1 .= "
        int funcReturnTypeBecameVoid(int param) { return 0; }";
    
    $HEADER2 .= "
        $DECL_SPEC void funcReturnTypeBecameVoid(int param);";
    $SOURCE2 .= "
        void funcReturnTypeBecameVoid(int param) { return; }";
    
    # Return_BaseType
    $HEADER1 .= "
        $DECL_SPEC int* funcReturnBaseType(int param);";
    $SOURCE1 .= "
        int* funcReturnBaseType(int param) {
            int *x = new int[10];
            return x;
        }";
    
    $HEADER2 .= "
        $DECL_SPEC long long* funcReturnBaseType(int param);";
    $SOURCE2 .= "
        long long* funcReturnBaseType(int param) {
            long long *x = new long long[10];
            return x;
        }";
    
    # Return_PointerLevel
    $HEADER1 .= "
        $DECL_SPEC long long funcReturnPointerLevelAndSize(int param);";
    $SOURCE1 .= "
        long long funcReturnPointerLevelAndSize(int param) { return 0; }";
    
    $HEADER2 .= "
        $DECL_SPEC long long* funcReturnPointerLevelAndSize(int param);";
    $SOURCE2 .= "
        long long* funcReturnPointerLevelAndSize(int param) { return new long long[10]; }";
    
    # Return_PointerLevel
    $HEADER1 .= "
        $DECL_SPEC int* funcReturnPointerLevel(int param);";
    $SOURCE1 .= "
        int* funcReturnPointerLevel(int param) { return new int[10]; }";
    
    $HEADER2 .= "
        $DECL_SPEC int** funcReturnPointerLevel(int param);";
    $SOURCE2 .= "
        int** funcReturnPointerLevel(int param) { return new int*[10]; }";
    
    # Size (anon type)
    $HEADER1 .= "
        typedef struct {
            int i;
            long j;
            double k;
        } AnonTypedef;
        $DECL_SPEC int funcAnonTypedef(AnonTypedef param);";
    $SOURCE1 .= "
        int funcAnonTypedef(AnonTypedef param) { return 0; }";
    
    $HEADER2 .= "
        typedef struct {
            int i;
            long j;
            double k;
            union {
                int dummy[256];
                struct {
                    char q_skiptable[256];
                    const char *p;
                    int l;
                } p;
            };
        } AnonTypedef;
        $DECL_SPEC int funcAnonTypedef(AnonTypedef param);";
    $SOURCE2 .= "
        int funcAnonTypedef(AnonTypedef param) { return 0; }";
    
    # Added_Field (safe: opaque)
    $HEADER1 .= "
        struct $DECL_SPEC OpaqueType
        {
        public:
            OpaqueType method(OpaqueType param);
            int i;
            long j;
            double k;
            OpaqueType* p;
        };";
    $SOURCE1 .= "
        OpaqueType OpaqueType::method(OpaqueType param) { return param; }";
    
    $HEADER2 .= "
        struct $DECL_SPEC OpaqueType
        {
        public:
            OpaqueType method(OpaqueType param);
            int i;
            long j;
            double k;
            OpaqueType* p;
            int added_member;
        };";
    $SOURCE2 .= "
        OpaqueType OpaqueType::method(OpaqueType param) { return param; }";
    
    # Added_Field (safe: internal)
    $HEADER1 .= "
        struct $DECL_SPEC InternalType {
            InternalType method(InternalType param);
            int i;
            long j;
            double k;
            InternalType* p;
        };";
    $SOURCE1 .= "
        InternalType InternalType::method(InternalType param) { return param; }";
    
    $HEADER2 .= "
        struct $DECL_SPEC InternalType {
            InternalType method(InternalType param);
            int i;
            long j;
            double k;
            InternalType* p;
            int added_member;
        };";
    $SOURCE2 .= "
        InternalType InternalType::method(InternalType param) { return param; }";
    
    # Size (unnamed struct/union fields within structs/unions)
    $HEADER1 .= "
        typedef struct {
            int a;
            struct {
                int u1;
                float u2;
            };
            int d;
        } UnnamedTypeSize;
        $DECL_SPEC int unnamedTypeSize(UnnamedTypeSize param);";
    $SOURCE1 .= "
        int unnamedTypeSize(UnnamedTypeSize param) { return 0; }";
    
    $HEADER2 .= "
        typedef struct {
            int a;
            struct {
                long double u1;
                float u2;
            };
            int d;
        } UnnamedTypeSize;
        $DECL_SPEC int unnamedTypeSize(UnnamedTypeSize param);";
    $SOURCE2 .= "
        int unnamedTypeSize(UnnamedTypeSize param) { return 0; }";
    
    # Changed_Constant
    $HEADER1 .= "
        #define PUBLIC_CONSTANT \"old_value\"";
    $HEADER2 .= "
        #define PUBLIC_CONSTANT \"new_value\"";
    
    $HEADER1 .= "
        #define PUBLIC_VERSION \"1.2 (3.4)\"";
    $HEADER2 .= "
        #define PUBLIC_VERSION \"1.2 (3.5)\"";
    
    $HEADER1 .= "
        #define PRIVATE_CONSTANT \"old_value\"
        #undef PRIVATE_CONSTANT";
    $HEADER2 .= "
        #define PRIVATE_CONSTANT \"new_value\"
        #undef PRIVATE_CONSTANT";
    
    # Added_Field (union)
    $HEADER1 .= "
        union UnionAddedField {
            int a;
            struct {
                int b;
                float c;
            };
            int d;
        };
        $DECL_SPEC int unionAddedField(UnionAddedField param);";
    $SOURCE1 .= "
        int unionAddedField(UnionAddedField param) { return 0; }";
    
    $HEADER2 .= "
        union UnionAddedField {
            int a;
            struct {
                long double x, y;
            } new_field;
            struct {
                int b;
                float c;
            };
            int d;
        };
        $DECL_SPEC int unionAddedField(UnionAddedField param);";
    $SOURCE2 .= "
        int unionAddedField(UnionAddedField param) { return 0; }";
    
    # Removed_Field (union)
    $HEADER1 .= "
        union UnionRemovedField {
            int a;
            struct {
                long double x, y;
            } removed_field;
            struct {
                int b;
                float c;
            };
            int d;
        };
        $DECL_SPEC int unionRemovedField(UnionRemovedField param);";
    $SOURCE1 .= "
        int unionRemovedField(UnionRemovedField param) { return 0; }";
    
    $HEADER2 .= "
        union UnionRemovedField {
            int a;
            struct {
                int b;
                float c;
            };
            int d;
        };
        $DECL_SPEC int unionRemovedField(UnionRemovedField param);";
    $SOURCE2 .= "
        int unionRemovedField(UnionRemovedField param) { return 0; }";

    # Added (typedef change)
    $HEADER1 .= "
        typedef float TYPEDEF_TYPE;
        $DECL_SPEC int parameterTypedefChange(TYPEDEF_TYPE param);";
    $SOURCE1 .= "
        int parameterTypedefChange(TYPEDEF_TYPE param) { return 1; }";
    
    $HEADER2 .= "
        typedef int TYPEDEF_TYPE;
        $DECL_SPEC int parameterTypedefChange(TYPEDEF_TYPE param);";
    $SOURCE2 .= "
        int parameterTypedefChange(TYPEDEF_TYPE param) { return 1; }";

    # Parameter_Default_Value_Changed (safe)
    # Converted from void* to const char*
    $HEADER1 .= "
        $DECL_SPEC int paramDefaultValue_Converted(const char* arg = 0); ";
    $SOURCE1 .= "
        int paramDefaultValue_Converted(const char* arg) { return 0; }";
    
    $HEADER2 .= "
        $DECL_SPEC int paramDefaultValue_Converted(const char* arg = (const char*)((void*) 0)); ";
    $SOURCE2 .= "
        int paramDefaultValue_Converted(const char* arg) { return 0; }";
    
    # Parameter_Default_Value_Changed
    # Integer
    $HEADER1 .= "
        $DECL_SPEC int paramDefaultValueChanged_Integer(int param = 0xf00f); ";
    $SOURCE1 .= "
        int paramDefaultValueChanged_Integer(int param) { return param; }";
    
    $HEADER2 .= "
        $DECL_SPEC int paramDefaultValueChanged_Integer(int param = 0xf00b); ";
    $SOURCE2 .= "
        int paramDefaultValueChanged_Integer(int param) { return param; }";

    # Parameter_Default_Value_Changed
    # String
    $HEADER1 .= "
        $DECL_SPEC int paramDefaultValueChanged_String(char const* param = \" str  1 \"); ";
    $SOURCE1 .= "
        int paramDefaultValueChanged_String(char const* param) { return 0; }";
    
    $HEADER2 .= "
        $DECL_SPEC int paramDefaultValueChanged_String(char const* param = \" str  2 \"); ";
    $SOURCE2 .= "
        int paramDefaultValueChanged_String(char const* param) { return 0; }";

    # Parameter_Default_Value_Changed
    # Character
    $HEADER1 .= "
        $DECL_SPEC int paramDefaultValueChanged_Char(char param = \'A\'); ";
    $SOURCE1 .= "
        int paramDefaultValueChanged_Char(char param) { return 0; }";
    
    $HEADER2 .= "
        $DECL_SPEC int paramDefaultValueChanged_Char(char param = \'B\'); ";
    $SOURCE2 .= "
        int paramDefaultValueChanged_Char(char param) { return 0; }";

    # Parameter_Default_Value_Changed
    # Bool
    $HEADER1 .= "
        $DECL_SPEC int paramDefaultValueChanged_Bool(bool param = true); ";
    $SOURCE1 .= "
        int paramDefaultValueChanged_Bool(bool param) { return 0; }";
    
    $HEADER2 .= "
        $DECL_SPEC int paramDefaultValueChanged_Bool(bool param = false); ";
    $SOURCE2 .= "
        int paramDefaultValueChanged_Bool(bool param) { return 0; }";

    # Parameter_Default_Value_Removed
    $HEADER1 .= "
        $DECL_SPEC int parameterDefaultValueRemoved(int param = 15);
    ";
    $SOURCE1 .= "
        int parameterDefaultValueRemoved(int param) { return param; }";
    
    $HEADER2 .= "
        $DECL_SPEC int parameterDefaultValueRemoved(int param);";
    $SOURCE2 .= "
        int parameterDefaultValueRemoved(int param) { return param; }";

    # Parameter_Default_Value_Added
    $HEADER1 .= "
        $DECL_SPEC int parameterDefaultValueAdded(int param);
    ";
    $SOURCE1 .= "
        int parameterDefaultValueAdded(int param) { return param; }";
    
    $HEADER2 .= "
        $DECL_SPEC int parameterDefaultValueAdded(int param = 15);";
    $SOURCE2 .= "
        int parameterDefaultValueAdded(int param) { return param; }";
    
    # Field_Type (typedefs in member type)
    $HEADER1 .= "
        typedef float TYPEDEF_TYPE_2;
        struct $DECL_SPEC FieldTypedefChange{
        public:
            TYPEDEF_TYPE_2 m;
            TYPEDEF_TYPE_2 n;
        };
        $DECL_SPEC int fieldTypedefChange(FieldTypedefChange param);";
    $SOURCE1 .= "
        int fieldTypedefChange(FieldTypedefChange param) { return 1; }";
    
    $HEADER2 .= "
        typedef int TYPEDEF_TYPE_2;
        struct $DECL_SPEC FieldTypedefChange{
        public:
            TYPEDEF_TYPE_2 m;
            TYPEDEF_TYPE_2 n;
        };
        $DECL_SPEC int fieldTypedefChange(FieldTypedefChange param);";
    $SOURCE2 .= "
        int fieldTypedefChange(FieldTypedefChange param) { return 1; }";

    # Callback (testCallback symbol should be affected
    # instead of callback1 and callback2)
    $HEADER1 .= "
        class $DECL_SPEC Callback {
        public:
            virtual int callback1(int x, int y)=0;
            virtual int callback2(int x, int y)=0;
        };
        $DECL_SPEC int testCallback(Callback* p);";
    $SOURCE1 .= "
        int testCallback(Callback* p) {
            p->callback2(1, 2);
            return 0;
        }";

    $HEADER2 .= "
        class $DECL_SPEC Callback {
        public:
            virtual int callback1(int x, int y)=0;
            virtual int added_callback(int x, int y)=0;
            virtual int callback2(int x, int y)=0;
        };
        $DECL_SPEC int testCallback(Callback* p);";
    $SOURCE2 .= "
        int testCallback(Callback* p) {
            p->callback2(1, 2);
            return 0;
        }";
    
    # End namespace
    $HEADER1 .= "\n}\n";
    $HEADER2 .= "\n}\n";
    $SOURCE1 .= "\n}\n";
    $SOURCE2 .= "\n}\n";
    
    runTests("libsample_cpp", "C++", $HEADER1, $SOURCE1, $HEADER2, $SOURCE2, "TestNS::OpaqueType", "_ZN6TestNS12InternalType6methodES0_");
}

sub testC()
{
    printMsg("INFO", "\nverifying detectable C library changes");
    my ($HEADER1, $SOURCE1, $HEADER2, $SOURCE2) = ();
    my $DECL_SPEC = ($OSgroup eq "windows")?"__declspec( dllexport )":"";
    my $EXTERN = ($OSgroup eq "windows")?"extern ":""; # add "extern" for CL compiler
    
    # Struct to union
    $HEADER1 .= "
        typedef struct StructToUnion {
            unsigned char A[64];
        } StructToUnion;
        
        $DECL_SPEC int structToUnion(StructToUnion *p);";
    $SOURCE1 .= "
        int structToUnion(StructToUnion *p) { return 0; }";
    
    $HEADER2 .= "
        typedef union StructToUnion {
            unsigned char A[64];
            void *p;
        } StructToUnion;
        
        $DECL_SPEC int structToUnion(StructToUnion *p);";
    $SOURCE2 .= "
        int structToUnion(StructToUnion *p) { return 0; }";
    
    # Typedef to function
    $HEADER1 .= "
        typedef int(TypedefToFunction)(int pX);
        
        $DECL_SPEC int typedefToFunction(TypedefToFunction* p);";
    $SOURCE1 .= "
        int typedefToFunction(TypedefToFunction* p) { return 0; }";
    
    $HEADER2 .= "
        typedef int(TypedefToFunction)(int pX, int pY);
        
        $DECL_SPEC int typedefToFunction(TypedefToFunction* p);";
    $SOURCE2 .= "
        int typedefToFunction(TypedefToFunction* p) { return 0; }";
    
    # Used_Reserved
    $HEADER1 .= "
        typedef struct {
            int f;
            void* reserved0;
            void* reserved1;
        } UsedReserved;
        
        $DECL_SPEC int usedReserved(UsedReserved p);";
    $SOURCE1 .= "
        int usedReserved(UsedReserved p) { return 0; }";
    
    $HEADER2 .= "
        typedef struct {
            int f;
            void* f0;
            void* f1;
        } UsedReserved;
        
        $DECL_SPEC int usedReserved(UsedReserved p);";
    $SOURCE2 .= "
        int usedReserved(UsedReserved p) { return 0; }";
    
    # Parameter_Type_And_Register
    $HEADER1 .= "
        typedef struct {
            int a[4];
        } ARRAY;
        $DECL_SPEC void callConv5 (ARRAY i, int j);";
    $SOURCE1 .= "
        void callConv5 (ARRAY i, int j) { }";
    
    $HEADER2 .= "
        typedef struct {
            int a[4];
        } ARRAY;
        $DECL_SPEC void callConv5 (ARRAY i, double j);";
    $SOURCE2 .= "
        void callConv5 (ARRAY i, double j) { }";
    
    # Parameter_Type_And_Register
    $HEADER1 .= "
        typedef union {
            int a;
            double b;
        } UNION;
        $DECL_SPEC void callConv4 (UNION i, int j);";
    $SOURCE1 .= "
        void callConv4 (UNION i, int j) { }";
    
    $HEADER2 .= "
        typedef union {
            int a;
            double b;
        } UNION;
        $DECL_SPEC void callConv4 (UNION i, double j);";
    $SOURCE2 .= "
        void callConv4 (UNION i, double j) { }";
    
    # Parameter_Type_And_Register
    $HEADER1 .= "
        typedef struct {
            long a:4;
            long b:16;
        } POD2;
        $DECL_SPEC void callConv3 (POD2 i, int j);";
    $SOURCE1 .= "
        void callConv3 (POD2 i, int j) { }";
    
    $HEADER2 .= "
        typedef struct {
            long a:4;
            long b:16;
        } POD2;
        $DECL_SPEC void callConv3 (POD2 i, double j);";
    $SOURCE2 .= "
        void callConv3 (POD2 i, double j) { }";
    
    # Parameter_Type_And_Register
    $HEADER1 .= "
        typedef struct {
            short s:9;
            int j:9;
            char c;
            short t:9;
            short u:9;
            char d;
        } POD;
        $DECL_SPEC void callConv2 (POD i, int j);";
    $SOURCE1 .= "
        void callConv2 (POD i, int j) { }";
    
    $HEADER2 .= "
        typedef struct {
            short s:9;
            int j:9;
            char c;
            short t:9;
            short u:9;
            char d;
        } POD;
        $DECL_SPEC void callConv2 (POD i, double j);";
    $SOURCE2 .= "
        void callConv2 (POD i, double j) { }";
    
    # Parameter_Type_And_Register
    $HEADER1 .= "
        typedef struct {
            int a, b;
            double d;
        } POD1;
        $DECL_SPEC void callConv (int e, int f, POD1 s, int g, int h, long double ld, double m, double n, int i, int j, int k);";
    $SOURCE1 .= "
        void callConv(int e, int f, POD1 s, int g, int h, long double ld, double m, double n, int i, int j, int k) { }";
    
    $HEADER2 .= "
        typedef struct {
            int a, b;
            double d;
        } POD1;
        $DECL_SPEC void callConv (int e, int f, POD1 s, int g, int h, long double ld, double m, double n, int i, int j, double k);";
    $SOURCE2 .= "
        void callConv(int e, int f, POD1 s, int g, int h, long double ld, double m, double n, int i, int j, double k) { }";
    
    # Parameter_Type (int to "int const")
    $HEADER1 .= "
        $DECL_SPEC void parameterBecameConstInt(int arg);";
    $SOURCE1 .= "
        void parameterBecameConstInt(int arg) { }";
    
    $HEADER2 .= "
        $DECL_SPEC void parameterBecameConstInt(const int arg);";
    $SOURCE2 .= "
        void parameterBecameConstInt(const int arg) { }";

    # Parameter_Type ("int const" to int)
    $HEADER1 .= "
        $DECL_SPEC void parameterBecameNonConstInt(const int arg);";
    $SOURCE1 .= "
        void parameterBecameNonConstInt(const int arg) { }";
    
    $HEADER2 .= "
        $DECL_SPEC void parameterBecameNonConstInt(int arg);";
    $SOURCE2 .= "
        void parameterBecameNonConstInt(int arg) { }";
    
    # Parameter_Became_Register
    $HEADER1 .= "
        $DECL_SPEC void parameterBecameRegister(int arg);";
    $SOURCE1 .= "
        void parameterBecameRegister(int arg) { }";
    
    $HEADER2 .= "
        $DECL_SPEC void parameterBecameRegister(register int arg);";
    $SOURCE2 .= "
        void parameterBecameRegister(register int arg) { }";
    
    # Return_Type_Became_Const
    $HEADER1 .= "
        $DECL_SPEC char* returnTypeBecameConst(int param);";
    $SOURCE1 .= "
        char* returnTypeBecameConst(int param) { return (char*)malloc(256); }";
    
    $HEADER2 .= "
        $DECL_SPEC const char* returnTypeBecameConst(int param);";
    $SOURCE2 .= "
        const char* returnTypeBecameConst(int param) { return \"abc\"; }";
    
    # Return_Type_Became_Const (2)
    $HEADER1 .= "
        $DECL_SPEC char* returnTypeBecameConst2(int param);";
    $SOURCE1 .= "
        char* returnTypeBecameConst2(int param) { return (char*)malloc(256); }";
    
    $HEADER2 .= "
        $DECL_SPEC char*const returnTypeBecameConst2(int param);";
    $SOURCE2 .= "
        char*const returnTypeBecameConst2(int param) { return (char*const)malloc(256); }";
    
    # Return_Type_Became_Const (3)
    $HEADER1 .= "
        $DECL_SPEC char* returnTypeBecameConst3(int param);";
    $SOURCE1 .= "
        char* returnTypeBecameConst3(int param) { return (char*)malloc(256); }";
    
    $HEADER2 .= "
        $DECL_SPEC char const*const returnTypeBecameConst3(int param);";
    $SOURCE2 .= "
        char const*const returnTypeBecameConst3(int param) { return (char const*const)malloc(256); }";
    
    # Return_Type_Became_Volatile
    $HEADER1 .= "
        $DECL_SPEC char* returnTypeBecameVolatile(int param);";
    $SOURCE1 .= "
        char* returnTypeBecameVolatile(int param) { return (char*)malloc(256); }";
    
    $HEADER2 .= "
        $DECL_SPEC volatile char* returnTypeBecameVolatile(int param);";
    $SOURCE2 .= "
        volatile char* returnTypeBecameVolatile(int param) { return \"abc\"; }";
    
    # Added_Enum_Member
    $HEADER1 .= "
        enum AddedEnumMember {
            OldMember
        };
        $DECL_SPEC int addedEnumMember(enum AddedEnumMember param);";
    $SOURCE1 .= "
        int addedEnumMember(enum AddedEnumMember param) { return 0; }";
    
    $HEADER2 .= "
        enum AddedEnumMember {
            OldMember,
            NewMember
        };
        $DECL_SPEC int addedEnumMember(enum AddedEnumMember param);";
    $SOURCE2 .= "
        int addedEnumMember(enum AddedEnumMember param) { return 0; }";
    
    # Parameter_Type (Array)
    $HEADER1 .= "
        $DECL_SPEC int arrayParameterType(int param[5]);";
    $SOURCE1 .= "
        int arrayParameterType(int param[5]) { return 0; }";
    
    $HEADER2 .= "
        $DECL_SPEC int arrayParameterType(int param[7]);";
    $SOURCE2 .= "
        int arrayParameterType(int param[7]) { return 0; }";
    
    # Field_Type
    $HEADER1 .= "
        struct ArrayFieldType
        {
            int f;
            int i[1];
        };
        $DECL_SPEC int arrayFieldType(struct ArrayFieldType param);";
    $SOURCE1 .= "
        int arrayFieldType(struct ArrayFieldType param) { return param.i[0]; }";
    
    $HEADER2 .= "
        struct ArrayFieldType
        {
            int f;
            int i[];
        };
        $DECL_SPEC int arrayFieldType(struct ArrayFieldType param);";
    $SOURCE2 .= "
        int arrayFieldType(struct ArrayFieldType param) { return param.i[0]; }";
    
    # Field_Type_And_Size (Array)
    $HEADER1 .= "
        struct ArrayFieldSize
        {
            int i[5];
        };
        $DECL_SPEC int arrayFieldSize(struct ArrayFieldSize param);";
    $SOURCE1 .= "
        int arrayFieldSize(struct ArrayFieldSize param) { return 0; }";
    
    $HEADER2 .= "
        struct ArrayFieldSize
        {
            int i[7];
        };
        $DECL_SPEC int arrayFieldSize(struct ArrayFieldSize param);";
    $SOURCE2 .= "
        int arrayFieldSize(struct ArrayFieldSize param) { return 0; }";
    
    # Parameter_Became_Non_VaList
    $HEADER1 .= "
        $DECL_SPEC int parameterNonVaList(int param, ...);";
    $SOURCE1 .= "
        int parameterNonVaList(int param, ...) { return param; }";
    
    $HEADER2 .= "
        $DECL_SPEC int parameterNonVaList(int param1, int param2);";
    $SOURCE2 .= "
        int parameterNonVaList(int param1, int param2) { return param1; }";

    # Parameter_Became_VaList
    $HEADER1 .= "
        $DECL_SPEC int parameterVaList(int param1, int param2);";
    $SOURCE1 .= "
        int parameterVaList(int param1, int param2) { return param1; }";
    
    $HEADER2 .= "
        $DECL_SPEC int parameterVaList(int param, ...);";
    $SOURCE2 .= "
        int parameterVaList(int param, ...) { return param; }";
    
    # Field_Type_And_Size
    $HEADER1 .= "
        struct FieldSizePadded
        {
            int i;
            char changed_field;
            // padding (3 bytes)
            int j;
        };
        $DECL_SPEC int fieldSizePadded(struct FieldSizePadded param);";
    $SOURCE1 .= "
        int fieldSizePadded(struct FieldSizePadded param) { return 0; }";
    
    $HEADER2 .= "
        struct FieldSizePadded
        {
            int i;
            int changed_field;
            int j;
        };
        $DECL_SPEC int fieldSizePadded(struct FieldSizePadded param);";
    $SOURCE2 .= "
        int fieldSizePadded(struct FieldSizePadded param) { return 0; }";
    
    # Parameter_Type_Format
    $HEADER1 .= "
        struct DType1
        {
            int i;
            double j[7];
        };
        $DECL_SPEC int parameterTypeFormat(struct DType1 param);";
    $SOURCE1 .= "
        int parameterTypeFormat(struct DType1 param) { return 0; }";
    
    $HEADER2 .= "
        struct DType2
        {
            double i[7];
            int j;
        };
        $DECL_SPEC int parameterTypeFormat(struct DType2 param);";
    $SOURCE2 .= "
        int parameterTypeFormat(struct DType2 param) { return 0; }";
    
    # Field_Type_Format
    $HEADER1 .= "
        struct FieldTypeFormat
        {
            int i;
            struct DType1 j;
        };
        $DECL_SPEC int fieldTypeFormat(struct FieldTypeFormat param);";
    $SOURCE1 .= "
        int fieldTypeFormat(struct FieldTypeFormat param) { return 0; }";
    
    $HEADER2 .= "
        struct FieldTypeFormat
        {
            int i;
            struct DType2 j;
        };
        $DECL_SPEC int fieldTypeFormat(struct FieldTypeFormat param);";
    $SOURCE2 .= "
        int fieldTypeFormat(struct FieldTypeFormat param) { return 0; }";
    
    # Parameter_Type_Format (struct to union)
    $HEADER1 .= "
        struct DType
        {
            int i;
            double j;
        };
        $DECL_SPEC int parameterTypeFormat2(struct DType param);";
    $SOURCE1 .= "
        int parameterTypeFormat2(struct DType param) { return 0; }";
    
    $HEADER2 .= "
        union DType
        {
            int i;
            long double j;
        };
        $DECL_SPEC int parameterTypeFormat2(union DType param);";
    $SOURCE2 .= "
        int parameterTypeFormat2(union DType param) { return 0; }";
    
    # Global_Data_Size
    $HEADER1 .= "
        struct GlobalDataSize {
            int a;
        };
        $EXTERN $DECL_SPEC struct GlobalDataSize globalDataSize;";
    
    $HEADER2 .= "
        struct GlobalDataSize {
            int a, b;
        };
        $EXTERN $DECL_SPEC struct GlobalDataSize globalDataSize;";

    # Global_Data_Type
    $HEADER1 .= "
        $EXTERN $DECL_SPEC int globalDataType;";
    
    $HEADER2 .= "
        $EXTERN $DECL_SPEC float globalDataType;";

    # Global_Data_Type_And_Size
    $HEADER1 .= "
        $EXTERN $DECL_SPEC int globalDataTypeAndSize;";
    
    $HEADER2 .= "
        $EXTERN $DECL_SPEC short globalDataTypeAndSize;";
    
    # Global_Data_Value_Changed
    # Integer
    $HEADER1 .= "
        $EXTERN $DECL_SPEC const int globalDataValue_Integer = 10;";
    
    $HEADER2 .= "
        $EXTERN $DECL_SPEC const int globalDataValue_Integer = 15;";

    # Global_Data_Value_Changed
    # Character
    $HEADER1 .= "
        $EXTERN $DECL_SPEC const char globalDataValue_Char = \'o\';";
    
    $HEADER2 .= "
        $EXTERN $DECL_SPEC const char globalDataValue_Char = \'N\';";
    
    # Global_Data_Became_Non_Const
    $HEADER1 .= "
        $EXTERN $DECL_SPEC const int globalDataBecameNonConst = 10;";
    
    $HEADER2 .= "
        extern $DECL_SPEC int globalDataBecameNonConst;";
    $SOURCE2 .= "
        int globalDataBecameNonConst = 15;";

    # Global_Data_Became_Non_Const
    # Typedef
    $HEADER1 .= "
        typedef const int CONST_INT;
        $EXTERN $DECL_SPEC CONST_INT globalDataBecameNonConst_Typedef = 10;";
    
    $HEADER2 .= "
        extern $DECL_SPEC int globalDataBecameNonConst_Typedef;";
    $SOURCE2 .= "
        int globalDataBecameNonConst_Typedef = 15;";

    # Global_Data_Became_Const
    $HEADER1 .= "
        extern $DECL_SPEC int globalDataBecameConst;";
    $SOURCE1 .= "
        int globalDataBecameConst = 10;";
    
    $HEADER2 .= "
        $EXTERN $DECL_SPEC const int globalDataBecameConst = 15;";
    
    # Global_Data_Became_Non_Const
    $HEADER1 .= "
        struct GlobalDataType{int a;int b;struct GlobalDataType* p;};
        $EXTERN $DECL_SPEC const struct GlobalDataType globalStructDataBecameNonConst = { 1, 2, (struct GlobalDataType*)0 };";
    
    $HEADER2 .= "
        struct GlobalDataType{int a;int b;struct GlobalDataType* p;};
        $EXTERN $DECL_SPEC struct GlobalDataType globalStructDataBecameNonConst = { 1, 2, (struct GlobalDataType*)0 };";
    
    # Removed_Parameter
    $HEADER1 .= "
        $DECL_SPEC int removedParameter(int param, int removed_param);";
    $SOURCE1 .= "
        int removedParameter(int param, int removed_param) { return 0; }";
    
    $HEADER2 .= "
        $DECL_SPEC int removedParameter(int param);";
    $SOURCE2 .= "
        int removedParameter(int param) { return 0; }";
    
    # Added_Parameter
    $HEADER1 .= "
        $DECL_SPEC int addedParameter(int param);";
    $SOURCE1 .= "
        int addedParameter(int param) { return param; }";
    
    $HEADER2 .= "
        $DECL_SPEC int addedParameter(int param, int added_param, int added_param2);";
    $SOURCE2 .= "
        int addedParameter(int param, int added_param, int added_param2) { return added_param2; }";
    
    # Added_Interface (typedef to funcptr parameter)
    $HEADER2 .= "
        typedef int (*FUNCPTR_TYPE)(int a, int b);
        $DECL_SPEC int addedFunc(FUNCPTR_TYPE*const** f);";
    $SOURCE2 .= "
        int addedFunc(FUNCPTR_TYPE*const** f) { return 0; }";
    
    # Added_Interface (funcptr parameter)
    $HEADER2 .= "
        $DECL_SPEC int addedFunc2(int(*func)(int, int));";
    $SOURCE2 .= "
        int addedFunc2(int(*func)(int, int)) { return 0; }";
    
    # Added_Interface (no limited parameters)
    $HEADER2 .= "
        $DECL_SPEC int addedFunc3(float p1, ...);";
    $SOURCE2 .= "
        int addedFunc3(float p1, ...) { return 0; }";
    
    # Size
    $HEADER1 .= "
        struct TypeSize
        {
            long long i[5];
            long j;
            double k;
            struct TypeSize* p;
        };
        $DECL_SPEC int testSize(struct TypeSize param, int param_2);";
    $SOURCE1 .= "
        int testSize(struct TypeSize param, int param_2) { return param_2; }";
    
    $HEADER2 .= "
        struct TypeSize
        {
            long long i[15];
            long long j;
            double k;
            struct TypeSize* p;
        };
        $DECL_SPEC int testSize(struct TypeSize param, int param_2);";
    $SOURCE2 .= "
        int testSize(struct TypeSize param, int param_2) { return param_2; }";
    
    # Added_Field_And_Size
    $HEADER1 .= "
        struct AddedFieldAndSize
        {
            int i;
            long j;
            double k;
            struct AddedFieldAndSize* p;
        };
        $DECL_SPEC int addedFieldAndSize(struct AddedFieldAndSize param, int param_2);";
    $SOURCE1 .= "
        int addedFieldAndSize(struct AddedFieldAndSize param, int param_2) { return param_2; }";
    
    $HEADER2 .= "
        struct AddedFieldAndSize
        {
            int i;
            long j;
            double k;
            struct AddedFieldAndSize* p;
            int added_member1;
            int added_member2;
        };
        $DECL_SPEC int addedFieldAndSize(struct AddedFieldAndSize param, int param_2);";
    $SOURCE2 .= "
        int addedFieldAndSize(struct AddedFieldAndSize param, int param_2) { return param_2; }";
    
    # Added_Middle_Field_And_Size
    $HEADER1 .= "
        struct AddedMiddleFieldAndSize
        {
            int i;
            long j;
            double k;
            struct AddedMiddleFieldAndSize* p;
        };
        $DECL_SPEC int addedMiddleFieldAndSize(struct AddedMiddleFieldAndSize param, int param_2);";
    $SOURCE1 .= "
        int addedMiddleFieldAndSize(struct AddedMiddleFieldAndSize param, int param_2) { return param_2; }";
    
    $HEADER2 .= "
        struct AddedMiddleFieldAndSize
        {
            int i;
            int added_middle_member;
            long j;
            double k;
            struct AddedMiddleFieldAndSize* p;
        };
        $DECL_SPEC int addedMiddleFieldAndSize(struct AddedMiddleFieldAndSize param, int param_2);";
    $SOURCE2 .= "
        int addedMiddleFieldAndSize(struct AddedMiddleFieldAndSize param, int param_2) { return param_2; }";

    # Added_Middle_Field
    $HEADER1 .= "
        struct AddedMiddleField
        {
            unsigned char field1;
            unsigned short field2;
        };
        $DECL_SPEC int addedMiddleField(struct AddedMiddleField param, int param_2);";
    $SOURCE1 .= "
        int addedMiddleField(struct AddedMiddleField param, int param_2) { return param_2; }";
    
    $HEADER2 .= "
        struct AddedMiddleField
        {
            unsigned char field1;
            unsigned char added_field;
            unsigned short field2;
        };
        $DECL_SPEC int addedMiddleField(struct AddedMiddleField param, int param_2);";
    $SOURCE2 .= "
        int addedMiddleField(struct AddedMiddleField param, int param_2) { return param_2; }";
    
    # Renamed_Field
    $HEADER1 .= "
        struct RenamedField
        {
            long i;
            long j;
            double k;
            struct RenamedField* p;
        };
        $DECL_SPEC int renamedField(struct RenamedField param, int param_2);";
    $SOURCE1 .= "
        int renamedField(struct RenamedField param, int param_2) { return param_2; }";
    
    $HEADER2 .= "
        struct RenamedField
        {
            long renamed_member;
            long j;
            double k;
            struct RenamedField* p;
        };
        $DECL_SPEC int renamedField(struct RenamedField param, int param_2);";
    $SOURCE2 .= "
        int renamedField(struct RenamedField param, int param_2) { return param_2; }";
        
    # Renamed_Field
    $HEADER1 .= "
        union RenamedUnionField
        {
            int renamed_from;
            double j;
        };
        $DECL_SPEC int renamedUnionField(union RenamedUnionField param);";
    $SOURCE1 .= "
        int renamedUnionField(union RenamedUnionField param) { return 0; }";
    
    $HEADER2 .= "
        union RenamedUnionField
        {
            int renamed_to;
            double j;
        };
        $DECL_SPEC int renamedUnionField(union RenamedUnionField param);";
    $SOURCE2 .= "
        int renamedUnionField(union RenamedUnionField param) { return 0; }";
    
    # Removed_Field_And_Size
    $HEADER1 .= "
        struct RemovedFieldAndSize
        {
            int i;
            long j;
            double k;
            struct RemovedFieldAndSize* p;
            int removed_member1;
            int removed_member2;
        };
        $DECL_SPEC int removedFieldAndSize(struct RemovedFieldAndSize param, int param_2);";
    $SOURCE1 .= "
        int removedFieldAndSize(struct RemovedFieldAndSize param, int param_2) { return param_2; }";
    
    $HEADER2 .= "
        struct RemovedFieldAndSize
        {
            int i;
            long j;
            double k;
            struct RemovedFieldAndSize* p;
        };
        $DECL_SPEC int removedFieldAndSize(struct RemovedFieldAndSize param, int param_2);";
    $SOURCE2 .= "
        int removedFieldAndSize(struct RemovedFieldAndSize param, int param_2) { return param_2; }";
    
    # Removed_Middle_Field
    $HEADER1 .= "
        struct RemovedMiddleField
        {
            int i;
            int removed_middle_member;
            long j;
            double k;
            struct RemovedMiddleField* p;
        };
        $DECL_SPEC int removedMiddleField(struct RemovedMiddleField param, int param_2);";
    $SOURCE1 .= "
        int removedMiddleField(struct RemovedMiddleField param, int param_2) { return param_2; }";
    
    $HEADER2 .= "
        struct RemovedMiddleField
        {
            int i;
            long j;
            double k;
            struct RemovedMiddleField* p;
        };
        $DECL_SPEC int removedMiddleField(struct RemovedMiddleField param, int param_2);";
    $SOURCE2 .= "
        int removedMiddleField(struct RemovedMiddleField param, int param_2) { return param_2; }";
    
    # Enum_Member_Value
    $HEADER1 .= "
        enum EnumMemberValue
        {
            MEMBER1=1,
            MEMBER2=2
        };
        $DECL_SPEC int enumMemberValue(enum EnumMemberValue param);";
    $SOURCE1 .= "
        int enumMemberValue(enum EnumMemberValue param) { return 0; }";
    
    $HEADER2 .= "
        enum EnumMemberValue
        {
            MEMBER1=2,
            MEMBER2=1
        };
        $DECL_SPEC int enumMemberValue(enum EnumMemberValue param);";
    $SOURCE2 .= "
        int enumMemberValue(enum EnumMemberValue param) { return 0; }";

    # Enum_Member_Removed
    $HEADER1 .= "
        enum EnumMemberRemoved
        {
            MEMBER=1,
            MEMBER_REMOVED=2
        };
        $DECL_SPEC int enumMemberRemoved(enum EnumMemberRemoved param);";
    $SOURCE1 .= "
        int enumMemberRemoved(enum EnumMemberRemoved param) { return 0; }";
    
    $HEADER2 .= "
        enum EnumMemberRemoved
        {
            MEMBER=1
        };
        $DECL_SPEC int enumMemberRemoved(enum EnumMemberRemoved param);";
    $SOURCE2 .= "
        int enumMemberRemoved(enum EnumMemberRemoved param) { return 0; }";

    # Enum_Member_Removed (middle)
    $HEADER1 .= "
        enum EnumMiddleMemberRemoved
        {
            MEM_REMOVED,
            MEM1,
            MEM2
        };
        $DECL_SPEC int enumMiddleMemberRemoved(enum EnumMiddleMemberRemoved param);";
    $SOURCE1 .= "
        int enumMiddleMemberRemoved(enum EnumMiddleMemberRemoved param) { return 0; }";
    
    $HEADER2 .= "
        enum EnumMiddleMemberRemoved
        {
            MEM1,
            MEM2
        };
        $DECL_SPEC int enumMiddleMemberRemoved(enum EnumMiddleMemberRemoved param);";
    $SOURCE2 .= "
        int enumMiddleMemberRemoved(enum EnumMiddleMemberRemoved param) { return 0; }";
    
    # Enum_Member_Name
    $HEADER1 .= "
        enum EnumMemberName
        {
            BRANCH1=1,
            BRANCH2=2
        };
        $DECL_SPEC int enumMemberName(enum EnumMemberName param);";
    $SOURCE1 .= "
        int enumMemberName(enum EnumMemberName param) { return 0; }";
    
    $HEADER2 .= "
        enum EnumMemberName
        {
            BRANCH_FIRST=1,
            BRANCH_SECOND=2
        };
        $DECL_SPEC int enumMemberName(enum EnumMemberName param);";
    $SOURCE2 .= "
        int enumMemberName(enum EnumMemberName param) { return 0; }";
    
    # Field_Type_And_Size
    $HEADER1 .= "
        struct FieldTypeAndSize
        {
            int i;
            long j;
            double k;
            struct FieldTypeAndSize* p;
        };
        $DECL_SPEC int fieldTypeAndSize(struct FieldTypeAndSize param, int param_2);";
    $SOURCE1 .= "
        int fieldTypeAndSize(struct FieldTypeAndSize param, int param_2) { return param_2; }";
    
    $HEADER2 .= "
        struct FieldTypeAndSize
        {
            int i;
            long long j;
            double k;
            struct FieldTypeAndSize* p;
        };
        $DECL_SPEC int fieldTypeAndSize(struct FieldTypeAndSize param, int param_2);";
    $SOURCE2 .= "
        int fieldTypeAndSize(struct FieldTypeAndSize param, int param_2) { return param_2; }";
    
    # Field_Type
    $HEADER1 .= "
        struct FieldType
        {
            int i;
            long j;
            double k;
            struct FieldType* p;
        };
        $DECL_SPEC int fieldType(struct FieldType param, int param_2);";
    $SOURCE1 .= "
        int fieldType(struct FieldType param, int param_2) { return param_2; }";
    
    $HEADER2 .= "
        struct FieldType
        {
            float i;
            long j;
            double k;
            struct FieldType* p;
        };
        $DECL_SPEC int fieldType(struct FieldType param, int param_2);";
    $SOURCE2 .= "
        int fieldType(struct FieldType param, int param_2) { return param_2; }";
    
    # Field_BaseType
    $HEADER1 .= "
        struct FieldBaseType
        {
            int i;
            long *j;
            double k;
            struct FieldBaseType* p;
        };
        $DECL_SPEC int fieldBaseType(struct FieldBaseType param, int param_2);";
    $SOURCE1 .= "
        int fieldBaseType(struct FieldBaseType param, int param_2) { return param_2; }";
    
    $HEADER2 .= "
        struct FieldBaseType
        {
            int i;
            long long *j;
            double k;
            struct FieldBaseType* p;
        };
        $DECL_SPEC int fieldBaseType(struct FieldBaseType param, int param_2);";
    $SOURCE2 .= "
        int fieldBaseType(struct FieldBaseType param, int param_2) { return param_2; }";
    
    # Field_PointerLevel (and Size)
    $HEADER1 .= "
        struct FieldPointerLevelAndSize
        {
            int i;
            long long j;
            double k;
            struct FieldPointerLevelAndSize* p;
        };
        $DECL_SPEC int fieldPointerLevelAndSize(struct FieldPointerLevelAndSize param, int param_2);";
    $SOURCE1 .= "
        int fieldPointerLevelAndSize(struct FieldPointerLevelAndSize param, int param_2) { return param_2; }";
    
    $HEADER2 .= "
        struct FieldPointerLevelAndSize
        {
            int i;
            long long *j;
            double k;
            struct FieldPointerLevelAndSize* p;
        };
        $DECL_SPEC int fieldPointerLevelAndSize(struct FieldPointerLevelAndSize param, int param_2);";
    $SOURCE2 .= "
        int fieldPointerLevelAndSize(struct FieldPointerLevelAndSize param, int param_2) { return param_2; }";
    
    # Field_PointerLevel
    $HEADER1 .= "
        struct FieldPointerLevel
        {
            int i;
            long *j;
            double k;
            struct FieldPointerLevel* p;
        };
        $DECL_SPEC int fieldPointerLevel(struct FieldPointerLevel param, int param_2);";
    $SOURCE1 .= "
        int fieldPointerLevel(struct FieldPointerLevel param, int param_2) { return param_2; }";
    
    $HEADER2 .= "
        struct FieldPointerLevel
        {
            int i;
            long **j;
            double k;
            struct FieldPointerLevel* p;
        };
        $DECL_SPEC int fieldPointerLevel(struct FieldPointerLevel param, int param_2);";
    $SOURCE2 .= "
        int fieldPointerLevel(struct FieldPointerLevel param, int param_2) { return param_2; }";
    
    # Added_Interface
    $HEADER2 .= "
        $DECL_SPEC int addedFunc4(int param);";
    $SOURCE2 .= "
        int addedFunc4(int param) { return param; }";
    
    # Removed_Interface
    $HEADER1 .= "
        $DECL_SPEC int removedFunc(int param);";
    $SOURCE1 .= "
        int removedFunc(int param) { return param; }";
    
    # Parameter_Type_And_Size
    $HEADER1 .= "
        $DECL_SPEC int parameterTypeAndSize(int param, int other_param);";
    $SOURCE1 .= "
        int parameterTypeAndSize(int param, int other_param) { return other_param; }";
    
    $HEADER2 .= "
        $DECL_SPEC int parameterTypeAndSize(long long param, int other_param);";
    $SOURCE2 .= "
        int parameterTypeAndSize(long long param, int other_param) { return other_param; }";
    
    # Parameter_Type_And_Size + Parameter_Became_Non_Const
    $HEADER1 .= "
        $DECL_SPEC int parameterTypeAndSizeBecameNonConst(int* const param, int other_param);";
    $SOURCE1 .= "
        int parameterTypeAndSizeBecameNonConst(int* const param, int other_param) { return other_param; }";
    
    $HEADER2 .= "
        $DECL_SPEC int parameterTypeAndSizeBecameNonConst(long double param, int other_param);";
    $SOURCE2 .= "
        int parameterTypeAndSizeBecameNonConst(long double param, int other_param) { return other_param; }";

    # Parameter_Type_And_Size (test calling conventions)
    $HEADER1 .= "
        $DECL_SPEC int parameterCallingConvention(int p1, int p2, int p3);";
    $SOURCE1 .= "
        int parameterCallingConvention(int p1, int p2, int p3) { return 0; }";
    
    $HEADER2 .= "
        $DECL_SPEC float parameterCallingConvention(char p1, int p2, int p3);";
    $SOURCE2 .= "
        float parameterCallingConvention(char p1, int p2, int p3) { return 7.0f; }";
    
    # Parameter_Type
    $HEADER1 .= "
        $DECL_SPEC int parameterType(int param, int other_param);";
    $SOURCE1 .= "
        int parameterType(int param, int other_param) { return other_param; }";
    
    $HEADER2 .= "
        $DECL_SPEC int parameterType(float param, int other_param);";
    $SOURCE2 .= "
        int parameterType(float param, int other_param) { return other_param; }";
    
    # Parameter_Became_Non_Const
    $HEADER1 .= "
        $DECL_SPEC int parameterBecameNonConst(int const* param);";
    $SOURCE1 .= "
        int parameterBecameNonConst(int const* param) { return *param; }";
    
    $HEADER2 .= "
        $DECL_SPEC int parameterBecameNonConst(int* param);";
    $SOURCE2 .= "
        int parameterBecameNonConst(int* param) {
            *param=10;
            return *param;
        }";
    
    # Parameter_Became_Non_Const + Parameter_Became_Non_Volatile
    $HEADER1 .= "
        $DECL_SPEC int parameterBecameNonConstNonVolatile(int const volatile* param);";
    $SOURCE1 .= "
        int parameterBecameNonConstNonVolatile(int const volatile* param) { return *param; }";
    
    $HEADER2 .= "
        $DECL_SPEC int parameterBecameNonConstNonVolatile(int* param);";
    $SOURCE2 .= "
        int parameterBecameNonConstNonVolatile(int* param) {
            *param=10;
            return *param;
        }";
    
    # Parameter_BaseType (Typedef)
    $HEADER1 .= "
        typedef int* PARAM_TYPEDEF;
        $DECL_SPEC int parameterBaseTypedefChange(PARAM_TYPEDEF param);";
    $SOURCE1 .= "
        int parameterBaseTypedefChange(PARAM_TYPEDEF param) { return 0; }";
    
    $HEADER2 .= "
        typedef const int* PARAM_TYPEDEF;
        $DECL_SPEC int parameterBaseTypedefChange(PARAM_TYPEDEF param);";
    $SOURCE2 .= "
        int parameterBaseTypedefChange(PARAM_TYPEDEF param) { return 0; }";
    
    # Parameter_BaseType
    $HEADER1 .= "
        $DECL_SPEC int parameterBaseTypeChange(int *param);";
    $SOURCE1 .= "
        int parameterBaseTypeChange(int *param) { return sizeof(*param); }";
    
    $HEADER2 .= "
        $DECL_SPEC int parameterBaseTypeChange(long long *param);";
    $SOURCE2 .= "
        int parameterBaseTypeChange(long long *param) { return sizeof(*param); }";
    
    # Parameter_PointerLevel
    $HEADER1 .= "
        $DECL_SPEC long long parameterPointerLevelAndSize(long long param);";
    $SOURCE1 .= "
        long long parameterPointerLevelAndSize(long long param) { return param; }";
    
    $HEADER2 .= "
        $DECL_SPEC long long parameterPointerLevelAndSize(long long *param);";
    $SOURCE2 .= "
        long long parameterPointerLevelAndSize(long long *param) { return param[5]; }";
    
    # Parameter_PointerLevel
    $HEADER1 .= "
        $DECL_SPEC int parameterPointerLevel(int *param);";
    $SOURCE1 .= "
        int parameterPointerLevel(int *param) { return param[5]; }";
    
    $HEADER2 .= "
        $DECL_SPEC int parameterPointerLevel(int **param);";
    $SOURCE2 .= "
        int parameterPointerLevel(int **param) { return param[5][5]; }";
    
    # Return_Type_And_Size
    $HEADER1 .= "
        $DECL_SPEC int returnTypeAndSize(int param);";
    $SOURCE1 .= "
        int returnTypeAndSize(int param) { return 0; }";
    
    $HEADER2 .= "
        $DECL_SPEC long long returnTypeAndSize(int param);";
    $SOURCE2 .= "
        long long returnTypeAndSize(int param) { return 0; }";
    
    # Return_Type
    $HEADER1 .= "
        $DECL_SPEC int returnType(int param);";
    $SOURCE1 .= "
        int returnType(int param) { return 1; }";
    
    $HEADER2 .= "
        $DECL_SPEC float returnType(int param);";
    $SOURCE2 .= "
        float returnType(int param) { return 1; }";

    # Return_Type_Became_Void ("int" to "void")
    $HEADER1 .= "
        $DECL_SPEC int returnTypeChangeToVoid(int param);";
    $SOURCE1 .= "
        int returnTypeChangeToVoid(int param) { return 0; }";
    
    $HEADER2 .= "
        $DECL_SPEC void returnTypeChangeToVoid(int param);";
    $SOURCE2 .= "
        void returnTypeChangeToVoid(int param) { return; }";

    # Return_Type ("struct" to "void*")
    $HEADER1 .= "
        struct SomeStruct {
            int a;
            double b, c, d;
        };
        $DECL_SPEC struct SomeStruct* returnTypeChangeToVoidPtr(int param);";
    $SOURCE1 .= "
        struct SomeStruct* returnTypeChangeToVoidPtr(int param) { return (struct SomeStruct*)0; }";
    
    $HEADER2 .= "
        struct SomeStruct {
            int a;
            double b, c, d;
        };
        $DECL_SPEC void* returnTypeChangeToVoidPtr(int param);";
    $SOURCE2 .= "
        void* returnTypeChangeToVoidPtr(int param) { return (void*)0; }";
    
    # Return_Type (structure change)
    $HEADER1 .= "
        struct SomeStruct2 {
            int a;
            int b;
        };
        $DECL_SPEC struct SomeStruct2 returnType2(int param);";
    $SOURCE1 .= "
        struct SomeStruct2 returnType2(int param) { struct SomeStruct2 r = {1, 2};return r; }";
    
    $HEADER2 .= "
        struct SomeStruct2 {
            int a;
        };
        $DECL_SPEC struct SomeStruct2 returnType2(int param);";
    $SOURCE2 .= "
        struct SomeStruct2 returnType2(int param) { struct SomeStruct2 r = {1};return r; }";
        
    # Return_Type (structure change)
    $HEADER1 .= "
        struct SomeStruct3 {
            int a;
            int b;
        };
        $DECL_SPEC struct SomeStruct3 returnType3(int param);";
    $SOURCE1 .= "
        struct SomeStruct3 returnType3(int param) { struct SomeStruct3 r = {1, 2};return r; }";
    
    $HEADER2 .= "
        struct SomeStruct3 {
            int a;
            long double b;
        };
        $DECL_SPEC struct SomeStruct3 returnType3(int param);";
    $SOURCE2 .= "
        struct SomeStruct3 returnType3(int param) { struct SomeStruct3 r = {1, 2.0L};return r; }";

    # Return_Type_From_Void_And_Stack_Layout ("void" to "struct")
    $HEADER1 .= "
        $DECL_SPEC void returnTypeChangeFromVoidToStruct(int param);";
    $SOURCE1 .= "
        void returnTypeChangeFromVoidToStruct(int param) { return; }";
    
    $HEADER2 .= "
        $DECL_SPEC struct SomeStruct returnTypeChangeFromVoidToStruct(int param);";
    $SOURCE2 .= "
        struct SomeStruct returnTypeChangeFromVoidToStruct(int param) {
            struct SomeStruct obj = {1,2};
            return obj;
        }";

    # Return_Type_Became_Void_And_Stack_Layout ("struct" to "void")
    $HEADER1 .= "
        $DECL_SPEC struct SomeStruct returnTypeChangeFromStructToVoid(int param);";
    $SOURCE1 .= "
        struct SomeStruct returnTypeChangeFromStructToVoid(int param) {
            struct SomeStruct obj = {1,2};
            return obj;
        }";
    
    $HEADER2 .= "
        $DECL_SPEC void returnTypeChangeFromStructToVoid(int param);";
    $SOURCE2 .= "
        void returnTypeChangeFromStructToVoid(int param) { return; }";
    
    # Return_Type_From_Void_And_Stack_Layout (safe, "void" to "long")
    $HEADER1 .= "
        $DECL_SPEC void returnTypeChangeFromVoidToLong(int param);";
    $SOURCE1 .= "
        void returnTypeChangeFromVoidToLong(int param) { return; }";
    
    $HEADER2 .= "
        $DECL_SPEC long returnTypeChangeFromVoidToLong(int param);";
    $SOURCE2 .= "
        long returnTypeChangeFromVoidToLong(int param) { return 0; }";

    # Return_Type_From_Void_And_Stack_Layout (safe, "void" to "void*")
    $HEADER1 .= "
        $DECL_SPEC void returnTypeChangeFromVoidToVoidPtr(int param);";
    $SOURCE1 .= "
        void returnTypeChangeFromVoidToVoidPtr(int param) { return; }";
    
    $HEADER2 .= "
        $DECL_SPEC void* returnTypeChangeFromVoidToVoidPtr(int param);";
    $SOURCE2 .= "
        void* returnTypeChangeFromVoidToVoidPtr(int param) { return 0; }";
    
    # Return_Type_From_Register_To_Stack ("int" to "struct")
    $HEADER1 .= "
        $DECL_SPEC int returnTypeChangeFromIntToStruct(int param);";
    $SOURCE1 .= "
        int returnTypeChangeFromIntToStruct(int param) { return param; }";
    
    $HEADER2 .= "
        $DECL_SPEC struct SomeStruct returnTypeChangeFromIntToStruct(int param);";
    $SOURCE2 .= "
        struct SomeStruct returnTypeChangeFromIntToStruct(int param) {
            struct SomeStruct obj = {1,2};
            return obj;
        }";
    
    # Return_Type_From_Stack_To_Register (from struct to int)
    $HEADER1 .= "
        $DECL_SPEC struct SomeStruct returnTypeChangeFromStructToInt(int param);";
    $SOURCE1 .= "
        struct SomeStruct returnTypeChangeFromStructToInt(int param) {
            struct SomeStruct obj = {1,2};
            return obj;
        }";
    
    $HEADER2 .= "
        $DECL_SPEC int returnTypeChangeFromStructToInt(int param);";
    $SOURCE2 .= "
        int returnTypeChangeFromStructToInt(int param) { return param; }";

     # Return_Type_From_Stack_To_Register (from struct to int, without parameters)
    $HEADER1 .= "
        $DECL_SPEC struct SomeStruct returnTypeChangeFromStructToIntWithNoParams();";
    $SOURCE1 .= "
        struct SomeStruct returnTypeChangeFromStructToIntWithNoParams() {
            struct SomeStruct obj = {1,2};
            return obj;
        }";
    
    $HEADER2 .= "
        $DECL_SPEC int returnTypeChangeFromStructToIntWithNoParams();";
    $SOURCE2 .= "
        int returnTypeChangeFromStructToIntWithNoParams() { return 0; }";
    
    # Return_BaseType
    $HEADER1 .= "
        $DECL_SPEC int *returnBaseTypeChange(int param);";
    $SOURCE1 .= "
        int *returnBaseTypeChange(int param) { return (int*)0; }";
    
    $HEADER2 .= "
        $DECL_SPEC long long *returnBaseTypeChange(int param);";
    $SOURCE2 .= "
        long long *returnBaseTypeChange(int param) { return (long long*)0; }";
    
    # Return_PointerLevel
    $HEADER1 .= "
        $DECL_SPEC long long returnPointerLevelAndSize(int param);";
    $SOURCE1 .= "
        long long returnPointerLevelAndSize(int param) { return 100; }";
    
    $HEADER2 .= "
        $DECL_SPEC long long *returnPointerLevelAndSize(int param);";
    $SOURCE2 .= "
        long long *returnPointerLevelAndSize(int param) { return (long long *)0; }";
    
    # Return_PointerLevel
    $HEADER1 .= "
        $DECL_SPEC long long *returnPointerLevel(int param);";
    $SOURCE1 .= "
        long long *returnPointerLevel(int param) { return (long long *)0; }";
    
    $HEADER2 .= "
        $DECL_SPEC long long **returnPointerLevel(int param);";
    $SOURCE2 .= "
        long long **returnPointerLevel(int param) { return (long long **)0; }";
    
    # Size (typedef to anon structure)
    $HEADER1 .= "
        typedef struct
        {
            int i;
            long j;
            double k;
        } AnonTypedef;
        $DECL_SPEC int anonTypedef(AnonTypedef param);";
    $SOURCE1 .= "
        int anonTypedef(AnonTypedef param) { return 0; }";
    
    $HEADER2 .= "
        typedef struct
        {
            int i;
            long j;
            double k;
            union {
                int dummy[256];
                struct {
                    char q_skiptable[256];
                    const char *p;
                    int l;
                } p;
            };
        } AnonTypedef;
        $DECL_SPEC int anonTypedef(AnonTypedef param);";
    $SOURCE2 .= "
        int anonTypedef(AnonTypedef param) { return 0; }";
    
    # Size (safe: opaque)
    $HEADER1 .= "
        struct OpaqueType
        {
            long long i[5];
            long j;
            double k;
            struct OpaqueType* p;
        };
        $DECL_SPEC int opaqueTypeUse(struct OpaqueType param, int param_2);";
    $SOURCE1 .= "
        int opaqueTypeUse(struct OpaqueType param, int param_2) { return param_2; }";
    
    $HEADER2 .= "
        struct OpaqueType
        {
            long long i[5];
            long long j;
            double k;
            struct OpaqueType* p;
        };
        $DECL_SPEC int opaqueTypeUse(struct OpaqueType param, int param_2);";
    $SOURCE2 .= "
        int opaqueTypeUse(struct OpaqueType param, int param_2) { return param_2; }";
    
    # Size (safe: internal)
    $HEADER1 .= "
        struct InternalType
        {
            long long i[5];
            long j;
            double k;
            struct InternalType* p;
        };
        $DECL_SPEC int internalTypeUse(struct InternalType param, int param_2);";
    $SOURCE1 .= "
        int internalTypeUse(struct InternalType param, int param_2) { return param_2; }";
    
    $HEADER2 .= "
        struct InternalType
        {
            long long i[5];
            long long j;
            double k;
            struct InternalType* p;
        };
        $DECL_SPEC int internalTypeUse(struct InternalType param, int param_2);";
    $SOURCE2 .= "
        int internalTypeUse(struct InternalType param, int param_2) { return param_2; }";
    
    if($OSgroup eq "linux")
    {
        # Changed version
        $HEADER1 .= "
            $DECL_SPEC int changedVersion(int param);
            $DECL_SPEC int changedDefaultVersion(int param);";
        $SOURCE1 .= "
            int changedVersion(int param) { return 0; }
            __asm__(\".symver changedVersion,changedVersion\@VERSION_2.0\");
            int changedDefaultVersion(int param) { return 0; }";
        
        $HEADER2 .= "
            $DECL_SPEC int changedVersion(int param);
            $DECL_SPEC int changedDefaultVersion(long param);";
        $SOURCE2 .= "
            int changedVersion(int param) { return 0; }
            __asm__(\".symver changedVersion,changedVersion\@VERSION_3.0\");
            int changedDefaultVersion(long param) { return 0; }";
        
        # Unchanged version
        $HEADER1 .= "
            $DECL_SPEC int unchangedVersion(int param);
            $DECL_SPEC int unchangedDefaultVersion(int param);";
        $SOURCE1 .= "
            int unchangedVersion(int param) { return 0; }
            __asm__(\".symver unchangedVersion,unchangedVersion\@VERSION_1.0\");
            int unchangedDefaultVersion(int param) { return 0; }";
        
        $HEADER2 .= "
            $DECL_SPEC int unchangedVersion(int param);
            $DECL_SPEC int unchangedDefaultVersion(int param);";
        $SOURCE2 .= "
            int unchangedVersion(int param) { return 0; }
            __asm__(\".symver unchangedVersion,unchangedVersion\@VERSION_1.0\");
            int unchangedDefaultVersion(int param) { return 0; }";
        
        # Non-Default to Default
        $HEADER1 .= "
            $DECL_SPEC int changedVersionToDefault(int param);";
        $SOURCE1 .= "
            int changedVersionToDefault(int param) { return 0; }
            __asm__(\".symver changedVersionToDefault,changedVersionToDefault\@VERSION_1.0\");";
        
        $HEADER2 .= "
            $DECL_SPEC int changedVersionToDefault(long param);";
        $SOURCE2 .= "
            int changedVersionToDefault(long param) { return 0; }";
        
        # Default to Non-Default
        $HEADER1 .= "
            $DECL_SPEC int changedVersionToNonDefault(int param);";
        $SOURCE1 .= "
            int changedVersionToNonDefault(int param) { return 0; }";
        
        $HEADER2 .= "
            $DECL_SPEC int changedVersionToNonDefault(long param);";
        $SOURCE2 .= "
            int changedVersionToNonDefault(long param) { return 0; }
            __asm__(\".symver changedVersionToNonDefault,changedVersionToNonDefault\@VERSION_3.0\");";
        
        # Added version
        $HEADER1 .= "
            $DECL_SPEC int addedVersion(int param);
            $DECL_SPEC int addedDefaultVersion(int param);";
        $SOURCE1 .= "
            int addedVersion(int param) { return 0; }
            int addedDefaultVersion(int param) { return 0; }";
        
        $HEADER2 .= "
            $DECL_SPEC int addedVersion(int param);
            $DECL_SPEC int addedDefaultVersion(int param);";
        $SOURCE2 .= "
            int addedVersion(int param) { return 0; }
            __asm__(\".symver addedVersion,addedVersion\@VERSION_2.0\");
            int addedDefaultVersion(int param) { return 0; }";

        # Removed version
        $HEADER1 .= "
            $DECL_SPEC int removedVersion(int param);
            $DECL_SPEC int removedVersion2(int param);
            $DECL_SPEC int removedDefaultVersion(int param);";
        $SOURCE1 .= "
            int removedVersion(int param) { return 0; }
            __asm__(\".symver removedVersion,removedVersion\@VERSION_1.0\");
            int removedVersion2(int param) { return 0; }
            __asm__(\".symver removedVersion2,removedVersion\@VERSION_3.0\");
            int removedDefaultVersion(int param) { return 0; }";
        
        $HEADER2 .= "
            $DECL_SPEC int removedVersion(int param);
            $DECL_SPEC int removedVersion2(int param);
            $DECL_SPEC int removedDefaultVersion(int param);";
        $SOURCE2 .= "
            int removedVersion(int param) { return 0; }
            int removedVersion2(int param) { return 0; }
            __asm__(\".symver removedVersion2,removedVersion\@VERSION_3.0\");
            int removedDefaultVersion(int param) { return 0; }";
        
        # Return_Type (good versioning)
        $HEADER1 .= "
            $DECL_SPEC int goodVersioning(int param);";
        $SOURCE1 .= "
            int goodVersioning(int param) { return 0; }
            __asm__(\".symver goodVersioning,goodVersioning\@VERSION_1.0\");";
        
        $HEADER2 .= "
            $DECL_SPEC int goodVersioningOld(int param);";
        $SOURCE2 .= "
            int goodVersioningOld(int param) { return 0; }
            __asm__(\".symver goodVersioningOld,goodVersioning\@VERSION_1.0\");";
        
        $HEADER2 .= "
            $DECL_SPEC float goodVersioning(int param);";
        $SOURCE2 .= "
            float goodVersioning(int param) { return 0.7; }
            __asm__(\".symver goodVersioning,goodVersioning\@VERSION_2.0\");";
        
        # Return_Type (bad versioning)
        $HEADER1 .= "
            $DECL_SPEC int badVersioning(int param);";
        $SOURCE1 .= "
            int badVersioning(int param) { return 0; }
            __asm__(\".symver badVersioning,badVersioning\@VERSION_1.0\");";
        
        $HEADER2 .= "
            $DECL_SPEC float badVersioningOld(int param);";
        $SOURCE2 .= "
            float badVersioningOld(int param) { return 0.7; }
            __asm__(\".symver badVersioningOld,badVersioning\@VERSION_1.0\");";
        
        $HEADER2 .= "
            $DECL_SPEC float badVersioning(int param);";
        $SOURCE2 .= "
            float badVersioning(int param) { return 0.7; }
            __asm__(\".symver badVersioning,badVersioning\@VERSION_2.0\");";
    }
    # unnamed struct/union fields within structs/unions
    $HEADER1 .= "
        typedef struct
        {
            int a;
            union {
                int b;
                float c;
            };
            int d;
        } UnnamedTypeSize;
        $DECL_SPEC int unnamedTypeSize(UnnamedTypeSize param);";
    $SOURCE1 .= "
        int unnamedTypeSize(UnnamedTypeSize param) { return 0; }";
    
    $HEADER2 .= "
        typedef struct
        {
            int a;
            union {
                long double b;
                float c;
            };
            int d;
        } UnnamedTypeSize;
        $DECL_SPEC int unnamedTypeSize(UnnamedTypeSize param);";
    $SOURCE2 .= "
        int unnamedTypeSize(UnnamedTypeSize param) { return 0; }";
    
    # Changed_Constant (#define)
    $HEADER1 .= "
        #define PUBLIC_CONSTANT \"old_value\"";
    $HEADER2 .= "
        #define PUBLIC_CONSTANT \"new_value\"";
    
    # Changed_Constant (Safe)
    $HEADER1 .= "
        #define INTEGER_CONSTANT 0x01";
    $HEADER2 .= "
        #define INTEGER_CONSTANT 1";
    
    # Changed_Constant (Safe)
    $HEADER1 .= "
        #define PRIVATE_CONSTANT \"old_value\"
        #undef PRIVATE_CONSTANT";
    $HEADER2 .= "
        #define PRIVATE_CONSTANT \"new_value\"
        #undef PRIVATE_CONSTANT";
    
    # Changed_Constant (enum)
    $HEADER1 .= "
        enum {
            SOME_CONSTANT=0x1
        };";
    $HEADER2 .= "
        enum {
            SOME_CONSTANT=0x2
        };";
    
    # Added_Constant (#define)
    $HEADER2 .= "
        #define ADDED_CNST \"value\"";
        
    # Added_Constant (enum)
    $HEADER1 .= "
        enum {
            CONSTANT1
        };";
    $HEADER2 .= "
        enum {
            CONSTANT1,
            ADDED_CONSTANT
        };";
        
    # Removed_Constant (#define)
    $HEADER1 .= "
        #define REMOVED_CNST \"value\"";
    
    # Removed_Constant (enum)
    $HEADER1 .= "
        enum {
            CONSTANT2,
            REMOVED_CONSTANT
        };";
    $HEADER2 .= "
        enum {
            CONSTANT2
        };";
    
    # Added_Field (union)
    $HEADER1 .= "
        union UnionTypeAddedField
        {
            int a;
            struct {
                int b;
                float c;
            };
            int d;
        };
        $DECL_SPEC int unionTypeAddedField(union UnionTypeAddedField param);";
    $SOURCE1 .= "
        int unionTypeAddedField(union UnionTypeAddedField param) { return 0; }";
    
    $HEADER2 .= "
        union UnionTypeAddedField
        {
            int a;
            struct {
                long double x, y;
            } new_field;
            struct {
                int b;
                float c;
            };
            int d;
        };
        $DECL_SPEC int unionTypeAddedField(union UnionTypeAddedField param);";
    $SOURCE2 .= "
        int unionTypeAddedField(union UnionTypeAddedField param) { return 0; }";
    
    # Prameter_BaseType (typedef)
    $HEADER1 .= "
        typedef float TYPEDEF_TYPE;
        $DECL_SPEC int parameterTypedefChange(TYPEDEF_TYPE param);";
    $SOURCE1 .= "
        int parameterTypedefChange(TYPEDEF_TYPE param) { return 1.0; }";
    
    $HEADER2 .= "
        typedef int TYPEDEF_TYPE;
        $DECL_SPEC int parameterTypedefChange(TYPEDEF_TYPE param);";
    $SOURCE2 .= "
        int parameterTypedefChange(TYPEDEF_TYPE param) { return 1; }";
    
    # Field_BaseType (typedef in member type)
    $HEADER1 .= "
        typedef float TYPEDEF_TYPE_2;
        struct FieldBaseTypedefChange {
            TYPEDEF_TYPE_2 m;
        };
        $DECL_SPEC int fieldBaseTypedefChange(struct FieldBaseTypedefChange param);";
    $SOURCE1 .= "
        int fieldBaseTypedefChange(struct FieldBaseTypedefChange param) { return 1; }";
    
    $HEADER2 .= "
        typedef int TYPEDEF_TYPE_2;
        struct FieldBaseTypedefChange {
            TYPEDEF_TYPE_2 m;
        };
        $DECL_SPEC int fieldBaseTypedefChange(struct FieldBaseTypedefChange param);";
    $SOURCE2 .= "
        int fieldBaseTypedefChange(struct FieldBaseTypedefChange param) { return 1; }";
    
    # C++ keywords in C code
    $HEADER1 .= "
        $DECL_SPEC int testCppKeywords1(int class, int virtual, int (*new)(int));";
    $SOURCE1 .= "
        $DECL_SPEC int testCppKeywords1(int class, int virtual, int (*new)(int)) { return 0; }";
    
    $HEADER2 .= "
        $DECL_SPEC int testCppKeywords1(int class, int virtual);
        $DECL_SPEC int testCppKeywords2(int operator, int other);
        $DECL_SPEC int testCppKeywords3(int operator);
        $DECL_SPEC int operator(int class, int this);
        $DECL_SPEC int delete(int virtual, int* this);
        struct CppKeywords {
            int bool: 8;
            //int*this;
        };
        #ifdef __cplusplus
            class TestCppKeywords {
                void operator delete(void*);
                void operator ()(int);
                void operator,(int);
                void delete() {
                    delete this;
                };
            };
        #endif";
    $SOURCE2 .= "
        $DECL_SPEC int testCppKeywords1(int class, int virtual) { return 0; }";
    
    # Regression
    $HEADER1 .= "
        $DECL_SPEC int* testRegression(int *pointer, char const *name, ...);";
    $SOURCE1 .= "
        int* testRegression(int *pointer, char const *name, ...) { return 0; }";

    $HEADER2 .= "
        $DECL_SPEC int* testRegression(int *pointer, char const *name, ...);";
    $SOURCE2 .= "
        int* testRegression(int *pointer, char const *name, ...) { return 0; }";
    
    runTests("libsample_c", "C", $HEADER1, $SOURCE1, $HEADER2, $SOURCE2, "struct OpaqueType", "internalTypeUse");
}

sub runTests($$$$$$$$)
{
    my ($LibName, $Lang, $HEADER1, $SOURCE1, $HEADER2, $SOURCE2, $Opaque, $Private) = @_;
    
    my $SrcE = ($Lang eq "C++")?"cpp":"c";
    rmtree($LibName);
    
    my $ObjName = "libsample";
    
    # creating test suite
    my $Path_v1 = "$LibName/$ObjName.v1";
    my $Path_v2 = "$LibName/$ObjName.v2";
    mkpath($Path_v1);
    mkpath($Path_v2);
    writeFile("$Path_v1/$ObjName.h", $HEADER1."\n");
    writeFile("$Path_v1/$ObjName.$SrcE", "#include \"$ObjName.h\"\n".$SOURCE1."\n");
    writeFile("$LibName/v1.xml", "
        <version>
            1.0
        </version>
        
        <headers>
            ".get_abs_path($Path_v1)."
        </headers>
        
        <libs>
            ".get_abs_path($Path_v1)."
        </libs>
        
        <skip_types>
            $Opaque
        </skip_types>
        
        <skip_symbols>
            $Private
        </skip_symbols>
        
        <include_paths>
            ".get_abs_path($Path_v1)."
        </include_paths>\n");
    writeFile("$Path_v1/test.$SrcE", "
        #include \"$ObjName.h\"
        #include <stdio.h>
        ".($Lang eq "C++"?"using namespace TestNS;":"")."
        int main()
        {
            int ret = 0;
            printf(\"\%d\\n\", ret);
            return 0;
        }\n");
    
    writeFile("$Path_v2/$ObjName.h", $HEADER2."\n");
    writeFile("$Path_v2/$ObjName.$SrcE", "#include \"$ObjName.h\"\n".$SOURCE2."\n");
    writeFile("$LibName/v2.xml", "
        <version>
            2.0
        </version>
        
        <headers>
            ".get_abs_path($Path_v2)."
        </headers>
        
        <libs>
            ".get_abs_path($Path_v2)."
        </libs>
        
        <skip_types>
            $Opaque
        </skip_types>
        
        <skip_symbols>
            $Private
        </skip_symbols>
        
        <include_paths>
            ".get_abs_path($Path_v2)."
        </include_paths>\n");
    writeFile("$Path_v2/test.$SrcE", "
        #include \"$ObjName.h\"
        #include <stdio.h>
        ".($Lang eq "C++"?"using namespace TestNS;":"")."
        int main()
        {
            int ret = 0;
            printf(\"\%d\\n\", ret);
            return 0;
        }\n");
    
    my ($BuildCmd, $BuildCmd_Test) = ("", "");
    if($OSgroup eq "windows")
    {
        check_win32_env(); # to run MS VC++ compiler
        my $CL = get_CmdPath("cl");
        
        if(not $CL) {
            exitStatus("Not_Found", "can't find \"cl\" compiler");
        }
        $BuildCmd = "$CL /LD $ObjName.$SrcE >build_log.txt 2>&1";
        $BuildCmd_Test = "$CL test.$SrcE $ObjName.$LIB_EXT";
    }
    elsif($OSgroup eq "linux")
    {
        if($Lang eq "C")
        { # tests for symbol versioning
            writeFile("$Path_v1/version", "
                VERSION_1.0 {
                    unchangedDefaultVersion;
                    removedDefaultVersion;
                };
                VERSION_2.0 {
                    changedDefaultVersion;
                };
                VERSION_3.0 {
                    changedVersionToNonDefault;
                };
            ");
            writeFile("$Path_v2/version", "
                VERSION_1.0 {
                    unchangedDefaultVersion;
                    changedVersionToDefault;
                };
                VERSION_2.0 {
                    addedDefaultVersion;
                };
                VERSION_3.0 {
                    changedDefaultVersion;
                };
            ");
            $BuildCmd = $GCC_PATH." -Wl,--version-script version -shared $ObjName.$SrcE -o $ObjName.$LIB_EXT -g -Og";
            $BuildCmd_Test = $GCC_PATH." -Wl,--version-script version test.$SrcE -Wl,$ObjName.$LIB_EXT -o test";
        }
        else
        {
            $BuildCmd = $GCC_PATH." -shared -x c++ $ObjName.$SrcE -lstdc++ -o $ObjName.$LIB_EXT -g -Og";
            $BuildCmd_Test = $GCC_PATH." -x c++ test.$SrcE -lstdc++ -Wl,$ObjName.$LIB_EXT -o test";
        }
        if(getArch_GCC(1)=~/\A(arm|x86_64)\Z/i)
        { # relocation R_ARM_MOVW_ABS_NC against `a local symbol' can not be used when making a shared object; recompile with -fPIC
            $BuildCmd .= " -fPIC";
            $BuildCmd_Test .= " -fPIC";
        }
    }
    elsif($OSgroup eq "macos")
    { # using GCC -dynamiclib
        if($Lang eq "C")
        {
            $BuildCmd = $GCC_PATH." -dynamiclib $ObjName.$SrcE -o $ObjName.$LIB_EXT";
            $BuildCmd_Test = $GCC_PATH." test.$SrcE $ObjName.$LIB_EXT -o test";
        }
        else
        { # C++
            $BuildCmd = $GCC_PATH." -dynamiclib -x c++ $ObjName.$SrcE -lstdc++ -o $ObjName.$LIB_EXT";
            $BuildCmd_Test = $GCC_PATH." -x c++ test.$SrcE $ObjName.$LIB_EXT -o test";
        }
    }
    else
    { # default unix-like
      # symbian target
        if($Lang eq "C")
        {
            $BuildCmd = $GCC_PATH." -shared $ObjName.$SrcE -o $ObjName.$LIB_EXT -g -Og";
            $BuildCmd_Test = $GCC_PATH." test.$SrcE -Wl,$ObjName.$LIB_EXT -o test";
        }
        else
        { # C++
            $BuildCmd = $GCC_PATH." -shared -x c++ $ObjName.$SrcE -lstdc++ -o $ObjName.$LIB_EXT -g -Og";
            $BuildCmd_Test = $GCC_PATH." -x c++ test.$SrcE -Wl,$ObjName.$LIB_EXT -o test";
        }
    }
    
    if(my $Opts = getGCC_Opts(1))
    { # user-defined options
        $BuildCmd .= " ".$Opts;
        $BuildCmd_Test .= " ".$Opts;
    }
    
    my $MkContent = "all:\n\t$BuildCmd\ntest:\n\t$BuildCmd_Test\n";
    if($OSgroup eq "windows") {
        $MkContent .= "clean:\n\tdel test $ObjName.so\n";
    }
    else {
        $MkContent .= "clean:\n\trm test $ObjName.so\n";
    }
    writeFile("$Path_v1/Makefile", $MkContent);
    writeFile("$Path_v2/Makefile", $MkContent);
    system("cd $Path_v1 && $BuildCmd >build-log.txt 2>&1");
    if($?)
    {
        my $Msg = "can't compile $LibName v.1: \'$Path_v1/build-log.txt\'";
        if(readFile("$Path_v1/build-log.txt")=~/error trying to exec \W+cc1plus\W+/) {
            $Msg .= "\nDid you install G++?";
        }
        exitStatus("Error", $Msg);
    }
    system("cd $Path_v2 && $BuildCmd >build-log.txt 2>&1");
    if($?) {
        exitStatus("Error", "can't compile $LibName v.2: \'$Path_v2/build-log.txt\'");
    }
    # executing the tool
    my @Cmd = ("perl", $0, "-l", $LibName);
    
    if($TestABIDumper and $OSgroup eq "linux")
    {
        my @Cmd_d1 = ("abi-dumper", $Path_v1."/".$ObjName.".".$LIB_EXT, "-o", $LibName."/ABIv1.dump");
        @Cmd_d1 = (@Cmd_d1, "-public-headers", $Path_v1, "-lver", "1.0");
        if($Debug)
        { # debug mode
            printMsg("INFO", "executing @Cmd_d1");
        }
        system(@Cmd_d1);
        printMsg("INFO", "");
        
        my @Cmd_d2 = ("abi-dumper", $Path_v2."/".$ObjName.".".$LIB_EXT, "-o", $LibName."/ABIv2.dump");
        @Cmd_d2 = (@Cmd_d2, "-public-headers", $Path_v2, "-lver", "2.0");
        if($Debug)
        { # debug mode
            printMsg("INFO", "executing @Cmd_d2");
        }
        system(@Cmd_d2);
        printMsg("INFO", "");
        
        @Cmd = (@Cmd, "-old", $LibName."/ABIv1.dump", "-new", $LibName."/ABIv2.dump");
    }
    else
    {
        @Cmd = (@Cmd, "-old", "$LibName/v1.xml", "-new", "$LibName/v2.xml");
    }
    
    if($Lang eq "C") {
        @Cmd = (@Cmd, "-cxx-incompatible");
    }
    
    if($TestDump)
    {
        @Cmd = (@Cmd, "-use-dumps");
        if($SortDump) {
            @Cmd = (@Cmd, "-sort");
        }
    }
    if($DumpFormat and $DumpFormat ne "perl")
    { # Perl Data::Dumper is default format
        @Cmd = (@Cmd, "-dump-format", $DumpFormat);
    }
    if($GCC_PATH ne "gcc") {
        @Cmd = (@Cmd, "-cross-gcc", $GCC_PATH);
    }
    if($Quiet)
    { # quiet mode
        @Cmd = (@Cmd, "-quiet");
        @Cmd = (@Cmd, "-logging-mode", "a");
    }
    elsif($LogMode and $LogMode ne "w")
    { # "w" is default
        @Cmd = (@Cmd, "-logging-mode", $LogMode);
    }
    if($ExtendedCheck)
    { # extended mode
        @Cmd = (@Cmd, "-extended");
        if($Lang eq "C") {
            @Cmd = (@Cmd, "-lang", "C");
        }
    }
    if($ReportFormat and $ReportFormat ne "html")
    { # HTML is default format
        @Cmd = (@Cmd, "-report-format", $ReportFormat);
    }
    if($CheckHeadersOnly) {
        @Cmd = (@Cmd, "-headers-only");
    }
    if($OldStyle) {
        @Cmd = (@Cmd, "-old-style");
    }
    if($Debug)
    { # debug mode
        @Cmd = (@Cmd, "-debug");
        printMsg("INFO", "executing @Cmd");
    }
    system(@Cmd);
    
    my $ECode = $?>>8;
    
    if($ECode!~/\A[0-1]\Z/)
    { # error
        exitStatus("Error", "analysis has failed");
    }
    
    my $RPath = "compat_reports/$LibName/1.0_to_2.0/compat_report.$ReportFormat";
    my $NProblems = 0;
    if($ReportFormat eq "xml")
    {
        my $Content = readFile($RPath);
        # binary
        if(my $PSummary = parseTag(\$Content, "problem_summary"))
        {
            $NProblems += int(parseTag(\$PSummary, "removed_symbols"));
            if(my $TProblems = parseTag(\$PSummary, "problems_with_types"))
            {
                $NProblems += int(parseTag(\$TProblems, "high"));
                $NProblems += int(parseTag(\$TProblems, "medium"));
            }
            if(my $IProblems = parseTag(\$PSummary, "problems_with_symbols"))
            {
                $NProblems += int(parseTag(\$IProblems, "high"));
                $NProblems += int(parseTag(\$IProblems, "medium"));
            }
        }
        # source
        if(my $PSummary = parseTag(\$Content, "problem_summary"))
        {
            $NProblems += int(parseTag(\$PSummary, "removed_symbols"));
            if(my $TProblems = parseTag(\$PSummary, "problems_with_types"))
            {
                $NProblems += int(parseTag(\$TProblems, "high"));
                $NProblems += int(parseTag(\$TProblems, "medium"));
            }
            if(my $IProblems = parseTag(\$PSummary, "problems_with_symbols"))
            {
                $NProblems += int(parseTag(\$IProblems, "high"));
                $NProblems += int(parseTag(\$IProblems, "medium"));
            }
        }
    }
    else
    {
        my $BReport = readAttributes($RPath, 0);
        $NProblems += $BReport->{"removed"};
        $NProblems += $BReport->{"type_problems_high"}+$BReport->{"type_problems_medium"};
        $NProblems += $BReport->{"interface_problems_high"}+$BReport->{"interface_problems_medium"};
        my $SReport = readAttributes($RPath, 1);
        $NProblems += $SReport->{"removed"};
        $NProblems += $SReport->{"type_problems_high"}+$SReport->{"type_problems_medium"};
        $NProblems += $SReport->{"interface_problems_high"}+$SReport->{"interface_problems_medium"};
    }
    if(($LibName eq "libsample_c" and $NProblems>70)
    or ($LibName eq "libsample_cpp" and $NProblems>150)) {
        printMsg("INFO", "result: SUCCESS ($NProblems problems found)\n");
    }
    else {
        printMsg("ERROR", "result: FAILED ($NProblems problems found)\n");
    }
}

return 1;