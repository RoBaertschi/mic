#+vet explicit-allocators
package mic

import "core:mem/virtual"
import "base:runtime"

import "core:container/xar"

Tacky_Gen_Context :: struct {
	u:             ^Tacky_Unit,
	entity_values: map[^Entity]Tacky_Value,
	entity_labels: map[^Entity]Tacky_Label,
	function:      ^Tacky_Def_Function,
	locals:        Tacky_Value_Variable,
	labels:        Tacky_Label,

	arena:            virtual.Arena,
	targets_continue: xar.Array(Tacky_Label, 8),
	targets_break:    xar.Array(Tacky_Label, 8),
}

tacky_context_allocator :: proc(c: ^Tacky_Gen_Context) -> runtime.Allocator {
	return virtual.arena_allocator(&c.arena)
}

tacky_gen :: proc(u: ^Unit, out_u: ^Tacky_Unit) {
	function      := tacky_new(out_u, Tacky_Def_Function)
	function.name  = tacky_clone_string(out_u, u.function.name.ident)
	out_u.function = function

	xar.init(&function.instructions, tacky_allocator(out_u))

	c := Tacky_Gen_Context {
		function = function,
		entity_values = make(map[^Entity]Tacky_Value, allocator = runtime.heap_allocator()),
		entity_labels = make(map[^Entity]Tacky_Label, allocator = runtime.heap_allocator()),
		u        = out_u,
	}

	xar.init(&c.targets_break, tacky_context_allocator(&c))
	xar.init(&c.targets_continue, tacky_context_allocator(&c))

	defer {
		delete(c.entity_values)
		delete(c.entity_labels)

		virtual.arena_destroy(&c.arena)
	}

	tacky_gen_block(&c, &u.function.body)
	tacky_gen_instructions(&c, Tacky_Inst_Return(Tacky_Value_Constant(0)))
}

tacky_gen_instructions :: proc(c: ^Tacky_Gen_Context, insts: ..Tacky_Inst) {
	xar.append(&c.function.instructions, ..insts)
}

tacky_gen_make_temporary :: proc(c: ^Tacky_Gen_Context) -> (var: Tacky_Value_Variable) {
	var       = c.locals
	c.locals += 1
	return
}

tacky_gen_make_label :: proc(c: ^Tacky_Gen_Context) -> (label: Tacky_Label) {
	label     = c.labels
	c.labels += 1
	return
}

tacky_gen_block :: proc(c: ^Tacky_Gen_Context, body: ^Ast_Block) {
	for it := xar.iterator(body); block_item in xar.iterate_by_val(&it) {
		switch bi in block_item {
		case ^Ast_Stmt:
			tacky_gen_stmt(c, bi)
		case ^Ast_Decl:
			tacky_gen_decl(c, bi)
		}
	}
}
