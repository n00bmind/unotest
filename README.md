# unotest

A unit testing non-framework that tries to do just one thing.

## Installation

Simply drop `unotest.jai` into your private or system modules folder, and `#import` away!

## Usage

The basic premise is you write each of your tests as a normal procedure (no args), and then tag it with the `@test` note, so that it's picked up and run together with all the rest in the final test executable
```jai
TestFoo :: ()
{
    result := 2 + 2;
    Expect( result == 5 );
} @test
```

Build-time tests are supported as well. Simply use the `@test_buildtime` note instead. You can even combine both notes, if you're crazy like that..

Now, in your build proc, you will need to create a new workspace to generate the test executable. The easiest way to do this is to simply call `BuildTestsWorkspace`, passing a name for the workspace, any custom build options you want to apply to the generated executable, plus a list of filepaths containing your test procedures
```jai
#import "unotest";
build :: ()
{
    set_build_options_dc( .{do_output=false} );  // No executable for this workspace.
    global_options := get_build_options();
    global_options.output_path = "bin";

    // Test executable
    BuildTestsWorkspace( "Tests", global_options, .[ "src/test.jai" ] );
}
#run build();
```
This would build a `bin/test.exe` file (on Windows) that will run all the test procs that were found in succession. The order in which they run isn't guaranteed and will probably vary from build to build (but your tests are supposed to be independant of each other and have no side effects, right!?)


TO DO More fine-grained options, and a note about relative paths

## Contributing

All feedback is appreciated. Please feel free to open an issue to discuss any improvements or problems you may encounter.
