# unotest

A unit testing non-framework that tries to do just one thing.

Some features:
- Extremely simple to use. Just tag your test procedures, and add a single call to your build program
- Colorized output
- You can add any number of diagnostic messages to your tests (hidden by default), to help you figure out what went wrong

## Installation

Simply drop `unotest.jai` into your private or system modules folder, and `#import` away!

## Usage

The basic premise is you write each of your tests as a normal procedure (no args), and then tag it with the `@test` note, so that it's picked up and run together with all the rest in the final test executable. Each procedure that was tagged in this way will constitute a separate "test case".
```jai
#import "unotest";

TestFoo :: ()
{
    result := 2 + 2;
    Expect( result == 5 );
} @test
```

Build-time tests are supported as well. Simply use the `@test_buildtime` note instead. You can even combine both notes, if you're crazy like that..

As you can see, you can use the `Expect` macro to express your test's invariants. This macro will check that the condition you passed does indeed evaluate to true, and in case it doesnt, it will mark the test case as failed and record the failed expression as well as its location. `Expect` does not interrupt the execution of the test case though. If you want to immediately abort the test case upon a failure you can use `Assert` instead.

Now, in your build proc, you will need to create a new workspace to generate the test executable. The easiest way to do this is to simply call `BuildTestWorkspace`, passing a name for the workspace, any custom build options you want to apply to the generated executable, plus a list of filepaths containing your test procedures (any relative paths are relative to your own build file's dir).
```jai
#import "unotest";
build :: ()
{
    set_build_options_dc( .{do_output=false} );  // No executable for this workspace.
    global_options := get_build_options();
    global_options.output_path = "bin";

    // Test executable
    BuildTestWorkspace( "Tests", global_options, .[ "src/test.jai" ] );
}
#run build();
```
This would build a `bin/test.exe` file (on Windows) that will run all the test procs that were found in succession. The order in which they run isn't guaranteed and will probably vary from build to build (but your tests are supposed to be independant of each other and have no side effects, right!?)

That's basically it, really.

#### Further customization

- If you want to customize your test workspace a bit more, you can use `BeginTestWorkspace`/`EndTestWorkspace` instead of `BuildTestWorkspace`. This will allow you to tinker with the generated Workspace as much as you want.
```jai
#import "unotest";
build :: ()
{
    [...]

    // Test executable
    {
        w := BeginTestWorkspace( "Tests", global_options );

        // Do whatever..
        AddRandomStrings( w );
        // You're responsible for adding your own files, now!
        add_build_file( "src/test.jai", w );

        EndTestWorkspace( w );
    }
}
#run build();
```
- If that's still not enough, and you want to drive your own message loop in this workspace and all the shebang, you can then forget about the above and just call `AddTestStrings` at any point before entering said message loop, then call `HandleTestMessage` on each received message.
```jai
#import "unotest";
build :: ()
{
    [...]

    // Test executable
    {
        w := compiler_create_workspace( "CustomTests" );

        options := global_options;
        options.output_type = .EXECUTABLE;
        options.output_executable_name = "custom_test";
        set_build_options( options, w );

        compiler_begin_intercept( w );
        AddRandomStrings( w );
        add_build_file( "src/test.jai", w );

        // Don't forget this
        AddTestStrings( w );

        MyMessageLoop( w );

        compiler_end_intercept(w);
    }
}
#run build();

MyMessageLoop :: ( w: Workspace, verboseTests := false )
{
    while true
    {
        message := compiler_wait_for_message();
        HandleTestMessage( message, w );

        [...]

        if message.kind == .COMPLETE
            break;
    }
}
```

[TO DO explain verbose messages]

NOTE If you don't have a build metaprogram yet, I am also considering writing a metaprogram plugin to enable all this functionality straight from the command line, but so far I haven't needed this yet.. if you're interested, bug me and I'll get it done!

## Contributing

All feedback is appreciated. Please feel free to open an issue to discuss any improvements or problems you may encounter.
