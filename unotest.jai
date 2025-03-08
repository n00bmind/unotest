// TODO Usage comments!

#import "Basic";
#import "String";
#import "Compiler";
#import "Program_Print";


//// Public API (for user metaprograms)

BuildTestWorkspace :: ( name: string, baseOptions: Build_Options, filePaths: [] string, loc := #caller_location ) -> Workspace #compile_time
{
    w := BeginTestWorkspace( name, baseOptions, loc );

    // Use caller's location in the call to add_build_file
    // to ensure any relative paths stay relative to the enclosing workspace
    for filePaths
        add_build_file( it, w, loc );

    EndTestWorkspace( w );
    return w;
}

BeginTestWorkspace :: ( name: string, baseOptions: Build_Options, loc := #caller_location ) -> Workspace #compile_time
{
    w := compiler_create_workspace( name );

    options := baseOptions;
    options.output_type = .EXECUTABLE;
    options.output_executable_name = "test";
    set_build_options( options, w, loc );

    verboseTests := array_find( get_build_options().compile_time_command_line, "-verbose-tests" );

    compiler_begin_intercept( w );
    AddTestStrings( w, verboseTests );

    return w;
}

BeginTestWorkspace :: ( name: string, loc := #caller_location ) -> Workspace #compile_time
{
    return BeginTestWorkspace( name, get_build_options(), loc );
}

AddTestStrings :: ( w: Workspace, verboseBuildtimeTests := false ) #compile_time
{
    str := tprint( UserString, verboseBuildtimeTests );
    add_build_string( str, w );
}

HandleTestMessage :: ( message: *Message, w: Workspace ) #compile_time
{
    OnMessage( message, w );
}

EndTestWorkspace :: ( w: Workspace ) #compile_time
{
    MessageLoop( w );
    compiler_end_intercept(w);
}


//// Public API (test helpers)

Expect :: ( $expr: Code, loc := #caller_location ) -> bool #expand
{
    result: bool = #insert expr;

    exprString : string : #insert -> string
    {
        nodes := compiler_get_nodes( expr );

        builder: String_Builder;
        print_to_builder( *builder, "\"" );
        print_expression( *builder, nodes );
        print_to_builder( *builder, "\";" );

        return builder_to_string(*builder);
    };
    // AppendMsg( "Evaluated expression '%' (%).\n", exprString, ifx result "pass" else "fail" );

    // Only store the first failure for now..
    if !result && !context.testCase.failed
    {
        context.testCase.failedExpr = exprString;
        context.testCase.failedLocation = loc;
        context.testCase.failed = true;
    }
}

Assert :: ( $expr: Code, loc := #caller_location ) -> bool #expand
{
    result := Expect( expr, loc );
    if !result
        `return;
}

DeepEquals :: ( a: Any, b: Any ) -> bool
{
    errorStr: String_Builder;
    errorStr.allocator = temp;

    print_type_to_builder( *errorStr, a.type );

    result := DeepEqualsInternal( cast(*Any_Struct) *a, cast(*Any_Struct) *b, "", *errorStr );
    if !result
    {
        log( "%\n", builder_to_string( *errorStr ) );
        free_buffers( *errorStr );
    }
    return result;
}

//// Internal stuff
//// Some things here still need to be exported, since they'll be called from the user's application scope

TestCase :: struct
{
    name: string;
    proc: #type ();

    msgBuffer: = String_Builder.{ allocator = temp };
    failedExpr: string;
    failedLocation: Source_Code_Location;
    failed: bool = false;
}
#add_context testCase: *TestCase;

// Returns how many tests fails from the given list failed
RunTests :: ( tests: [] TestCase, verbose: bool ) -> s32
{
    failedCount: s32 = 0;

    if verbose
        context.log_level = .VERBOSE;

    startTime := current_time_monotonic();

    for t: tests
    {
        PrintAndIndent( "Running %...", t.name );

        newContext := context;
        newContext.testCase = *t;
        newContext.logger = TestMsgLogger;
        push_context newContext
        {
            t.proc();
        }

        if t.failed
        {
            print_color( "FAILED!\n", color = .RED );
            failedCount += 1;
        }
        else
        {
            print_color( "OK.\n", color = .GREEN );
        }

        if t.msgBuffer.initialized && context.log_level >= .VERBOSE
        {
            // TODO Can this be a bit less contrast still?
            log( builder_to_string( *t.msgBuffer ), flags = .VERBOSE_ONLY );
        }

        if t.failed
            // TODO Want to also log this (but not print the line twice!)
            print_color( "%: Expression '%' evaluated as false.\n", t.failedLocation, t.failedExpr, color = .WHITE );

        reset_temporary_storage();
    }

    endTime := current_time_monotonic();
    totalElapsedMillis := to_milliseconds( endTime - startTime, true );

    print_color( "\n% tests ran in % ms.\n", tests.count, totalElapsedMillis, color = .HI_WHITE );
    if failedCount > 0
    {
        print_color( "% PASSED. ", tests.count - failedCount, color = .GREEN );
        print_color( "% FAILED.\n", failedCount, color = .RED );
    }
    else
    {
        print_color( "ALL PASSED.\n", color = .GREEN );
    }

    return failedCount;
}

UserString :: #string END
#import "Command_Line";

#placeholder AllTests; // [] TestCase
#placeholder AllBuildtimeTests; // [] TestCase

RunAllTests :: () -> s32
{
    Arguments :: struct
    {
        verbose: bool;
    }
    parsedOk, args, is_set := parse_arguments( Arguments );
    verbose := parsedOk && is_set.verbose;

    failedCount := RunTests( AllTests, verbose );
    return failedCount;
}

RunAllBuildtimeTests :: () -> s32 #compile_time
{
    failedCount := RunTests( AllBuildtimeTests, %1 );
    print( "\n" );
    return failedCount;
}

main :: ()
{
    exitCode := RunAllTests();
    exit( exitCode );
}
END

#scope_module


// TODO Metaprogram plugin
get_plugin :: () -> *Metaprogram_Plugin
{
    // We are making this on the heap so you could have more than one instance of this plugin running.
    p := New( Metaprogram_Plugin );

    // You don't have to provide all of these hooks. You can leave them null
    // and they just won't be called.
    // p.before_intercept  = before_intercept;
    p.add_source        = OnAddSource;
    p.message           = OnMessage;
    // p.finish            = finish;
    // p.shutdown          = shutdown;
    // p.handle_one_option = handle_one_option;
    // p.log_help          = log_help;

    return p;
}


#scope_file

#import "Print_Color";

MessageLoop :: ( w: Workspace )
{
    while true
    {
        message := compiler_wait_for_message();
        OnMessage( message, w );

        if message.kind == .COMPLETE
            break;
    }
}

OnMessage :: ( message: *Message, w: Workspace )
{
    if message.kind ==
    {
    case .TYPECHECKED;
        typechecked := cast(*Message_Typechecked) message;

        for tc: typechecked.procedure_headers
        {
            proc := tc.expression;

            // Skip procs that are imported from somewhere
            // TODO Do we ever wanna support this
            if proc.enclosing_load && proc.enclosing_load.enclosing_import {
                if proc.enclosing_load.enclosing_import.module_type != .MAIN_PROGRAM
                    continue;
            }

            // If it is a procedure we want to test, make note of it for later.
            if HasNote( proc, "test" )
                array_add( *globalRuntimeTests, proc );
            if HasNote( proc, "test_buildtime" )
                array_add( *globalBuildtimeTests, proc );
        }

    case .PHASE;
        phase := cast(*Message_Phase) message;
        if phase.phase ==
        {
            case .TYPECHECKED_ALL_WE_CAN;
            {
                // Emit all tests we've found until now
                if !globalEmittedRuntimeTests
                {
                    // Emit all struct nodes as a constant array
                    print_to_builder( *globalBuilder, "AllTests: [%] TestCase = .[\n", globalRuntimeTests.count );

                    for globalRuntimeTests
                        print_to_builder( *globalBuilder, "    .{ name = \"%\", proc = % },\n", it.name, it.name );

                    append( *globalBuilder, "];\n" );

                    add_build_string( builder_to_string( *globalBuilder ), w );
                    free_buffers( *globalBuilder );

                    array_reset( *globalRuntimeTests );
                    globalEmittedRuntimeTests = true;
                }

                if !globalEmittedBuildtimeTests
                {
                    print_to_builder( *globalBuilder, "AllBuildtimeTests: [%] TestCase = .[\n", globalBuildtimeTests.count );

                    for globalBuildtimeTests
                    print_to_builder( *globalBuilder, "    .{ name = \"%\", proc = % },\n", it.name, it.name );

                    append( *globalBuilder, "];\n" );

                    add_build_string( builder_to_string( *globalBuilder ), w );
                    free_buffers( *globalBuilder );
                    array_reset( *globalBuildtimeTests );

                    globalEmittedBuildtimeTests = true;
                }
                else if !ranBuildtimeTests
                {
                    // NOTE Need this to be stallable if we wanna support tests depending on the output of other tests
                    append( *globalBuilder, "#run,stallable RunAllBuildtimeTests();\n" );
                    add_build_string( builder_to_string( *globalBuilder ), w );
                    free_buffers( *globalBuilder );

                    ranBuildtimeTests = true;
                }
            }
        }
    }
}

OnAddSource :: ( p: *Metaprogram_Plugin )
{
    // TODO Verbose flag?
    AddTestStrings( p.workspace, false );
}

OnMessage :: ( p: *Metaprogram_Plugin, message: *Message )
{
    OnMessage( message, p.workspace );
}

HasNote :: ( header: *Code_Procedure_Header, note: string, args: *string = null ) -> bool
{
    for header.notes
    {
        if it.text == note
            return true;
        // Crappy check to also account for notes followed by "arguments"
        else if starts_with( it.text, tprint( "%(", note ) )
        {
            if args
            {
                // Anything in parenthesis is considered arguments to the note
                s := slice( it.text, note.count, it.text.count - note.count );
                if s && s[0] == #char "(" && s[s.count - 1] == #char ")"
                {
                    <<args = slice( s, 1, s.count - 2 );
                }
            }
            return true;
        }
    }
    return false;
}


PrintAndIndent :: ( fmt: string, args: ..Any )
{
    msg := tprint( fmt, ..args );
    // TODO Want to also log this (but not print the line twice!)
    print_color( msg, color = .HI_WHITE );

    Spaces16 :: "                ";
    IndentCol :: 70;

    num_spaces := IndentCol - msg.count;
    if num_spaces <= 0
        return;

    div := num_spaces / 16;
    mod := num_spaces % 16;

    for 1..div
        write_string( Spaces16 );

    s := Spaces16;
    s.count = mod;
    write_string( s );
}

TestMsgLogger :: ( msg: string, data: *void, info: Log_Info )
{
    AppendMsg( msg );
}

AppendMsg :: ( fmt: string, args: ..Any )
{
    msg := tprint( fmt, ..args );

    assert( context.testCase != null );
    append( *context.testCase.msgBuffer, msg );
}

globalBuilder: String_Builder;
globalRuntimeTests: [..] *Code_Procedure_Header;
globalBuildtimeTests: [..] *Code_Procedure_Header;
globalEmittedRuntimeTests: bool = false;
globalEmittedBuildtimeTests: bool = false;
ranBuildtimeTests: bool = false;


DeepEqualsInternal :: ( a: *Any_Struct, b: *Any_Struct, scope: string, errorStr: *String_Builder ) -> bool
{
    if a.type != b.type
    {
        print_to_builder( errorStr, " - Types differ (a is %, b is %)", a.type, b.type );
        return false;
    }

    builderState: struct
    {
        currentBuffer: *String_Builder.Buffer;
        currentBufferCount: s64;
    }
    // Save current state in the stack
    builderState.currentBuffer = get_current_buffer( errorStr );
    builderState.currentBufferCount = builderState.currentBuffer.count;

    append( errorStr, scope );

    if a.type.type ==
    {
        case .STRUCT;
        {
            aType := cast(*Type_Info_Struct) a.type;
            for aType.members
            {
                aIt := Any_Struct.{ it.type, a.value_pointer + it.offset_in_bytes };
                bIt := Any_Struct.{ it.type, b.value_pointer + it.offset_in_bytes };

                scope := tprint( ".%", it.name );
                result := DeepEqualsInternal( *aIt, *bIt, scope, errorStr );
                if !result
                    return false;
            }
        }
        case .ARRAY;
        {
            aType := cast(*Type_Info_Array) a.type;
            bType := cast(*Type_Info_Array) b.type;
            itType := aType.element_type;

            aBase, bBase: *void = null;
            aCount, bCount: s64 = 0;
            if aType.array_type ==
            {
                case .FIXED;
                    aBase = a.value_pointer;
                    bBase = b.value_pointer;
                    aCount = aType.array_count;
                    bCount = bType.array_count;
                case .VIEW;
                    aArray := cast(*Array_View_64) a.value_pointer;
                    bArray := cast(*Array_View_64) b.value_pointer;
                    aBase = aArray.data;
                    bBase = bArray.data;
                    aCount = aArray.count;
                    bCount = bArray.count;
                case .RESIZABLE;
                    aArray := cast(*Resizable_Array) a.value_pointer;
                    bArray := cast(*Resizable_Array) b.value_pointer;
                    aBase = aArray.data;
                    bBase = bArray.data;
                    aCount = aArray.count;
                    bCount = bArray.count;
            }

            if aCount != bCount
            {
                print_to_builder( errorStr, " - Array counts differ (a is %, b is %)", aCount, bCount );
                return false;
            }
            for idx: 0 .. aCount - 1
            {
                aIt := Any_Struct.{ itType, aBase + idx * itType.runtime_size };
                bIt := Any_Struct.{ itType, bBase + idx * itType.runtime_size };
                scope := tprint( ".[%]", idx );
                result := DeepEqualsInternal( *aIt, *bIt, scope, errorStr );
                if !result
                    return false;
            }
        }
        case .STRING;
        {
            aString := cast(*string) a.value_pointer;
            bString := cast(*string) b.value_pointer;
            result := <<aString == <<bString;
            if !result
            {
                print_to_builder( errorStr, " - Strings differ (a is '%', b is '%')", <<aString, <<bString );
                return false;
            }
        }
        case;
        {
            // Simply memcmp their bytes
            result := memcmp( a.value_pointer, b.value_pointer, a.type.runtime_size ) == 0;
            if !result
            {
                append( errorStr, " - Contents differ (a is <" );
                print_item_to_builder( errorStr, <<cast(*Any)a, false );
                append( errorStr, ">, b is <" );
                print_item_to_builder( errorStr, <<cast(*Any)b, false );
                append( errorStr, ">)" );
                return false;
            }
        }
    }

    // Rewind current error path by restoring the builder's state
    errorStr.current_buffer = builderState.currentBuffer;
    errorStr.current_buffer.count = builderState.currentBufferCount;

    return true;
}

