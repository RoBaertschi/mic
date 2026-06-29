package mic

import "core:container/intrusive/list"
import "core:container/xar"

check_block :: proc(c: ^Checker_Context, b: ^Ast_Block, flags: Check_Stmt_Flags) {
	check_scope_guard(c)

	for it := xar.iterator(b); block_item in xar.iterate_by_val(&it) {
		switch bi in block_item {
		case ^Ast_Stmt:
			check_stmt(c, bi, flags)
		case ^Ast_Decl:
			check_decl(c, bi)
		}
	}
}

check_def_function :: proc(c: ^Checker_Context, f: ^Ast_Def_Function) {
	c.label_scope      = scope_new(c.u, nil)
	c.label_scope.kind = .Label

	// TODO: currently not doing much
	check_block(c, &f.body, {})

	for it := list.iterator_head(c.unresolved_labels, Entity, "unresolved_node");
	    e in list.iterate_next(&it)
	{
		// TODO(robin): attach correct token
		check_error(c, f.t, "use of undefined label %q", e.name.ident)
	}
}
