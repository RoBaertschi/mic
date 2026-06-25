The semantic analysis will not be based on the book, I wanna use something heavly inspired by Odin. It looks like this:

# Basic Checker path

1. Check and collect all global declarations and definitions except function bodies.
2. Push all the function bodies onto an array
3. After global checking is done, push them all into a thread pool.
4. The thread pool checks the functions in parralel.
5. When done, collect all diagnostics and report

# Problems

There are a few problems with that design, in C, declarations are only visible after itself. Before that, it is not seen. Also a newer declaration can update an old one with a new type/more information on said type.

Thats why we will build the global scope a bit different:

1. Collect all declarations and definitions until a function definition is reached.
2. Create a new FunctionInfo that contains said scope
3. Create a new scope, each scope in the global scope from now on will have the kind `Snapshot` and points back to the pervious global scope.
4. Collect all following declarations, when a new function definition is reached, pass that Scope down and repeat Step 3.

This could impact performance quite a bit for larger files when trying to access globals. If that comes true, add a function local cache for globals. Also not every function definition needs a new scope, they only need a new one if not already declared exactly like that.

# Entities

Everything will be collected as an entity, variables, global variables, function declarations. These will be what you get on a scope access. They also store an `Operand`.
