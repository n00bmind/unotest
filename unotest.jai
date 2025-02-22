// TODO Usage comments!

#import "Basic";
#import "String";
#import "Compiler";
#import "Program_Print";


BuildTestWorkspace :: ( name: string, baseOptions: Build_Options, filePaths: [] string, loc := #caller_location ) -> Workspace #compile_time
{
    w := BeginTestWorkspace( name, baseOptions );

    // Use caller's location in the call to add_build_file
    // to ensure any relative paths stay relative to the enclosing workspace
    for filePaths
        add_build_file( it, w, loc );

    EndTestWorkspace( w );
    return w;
}

BeginTestWorkspace :: ( name: string, baseOptions: Build_Options ) -> Workspace #compile_time
{
    w := compiler_create_workspace( name );

    options := baseOptions;
    options.output_type = .EXECUTABLE;
    options.output_executable_name = "test";
    set_build_options( options, w );

    verboseTests := array_find( get_build_options().compile_time_command_line, "-verbose-tests" );

    compiler_begin_intercept( w );
    AddTestStrings( w, verboseTests );

    return w;
}

BeginTestWorkspace :: ( name: string ) -> Workspace #compile_time
{
    return BeginTestWorkspace( name, get_build_options() );
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
            print_color( "%: Expression '%' evaluated as false.\n", t.failedLocation, t.failedExpr, color = .HI_WHITE );

        reset_temporary_storage();
    }

    // TODO Summary

    return failedCount;
}

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
