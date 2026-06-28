package mic

import "core:container/intrusive/list"
import "core:container/xar"

check_def_function :: proc(c: ^Checker_Context, f: ^Ast_Def_Function) {
	c.label_scope      = scope_new(c.u, nil)
	c.label_scope.kind = .Label

	check_scope_guard(c)

	// TODO: currently not doing much
	for it := xar.iterator(&f.body); block_item in xar.iterate_by_val(&it) {
		switch bi in block_item {
		case ^Ast_Stmt:
			check_stmt(c, bi)
		case ^Ast_Decl:
			check_decl(c, bi)
		}
	}

	for it := list.iterator_head(c.unresolved_labels, Entity, "unresolved_node");
	    e in list.iterate_next(&it)
	{
		// TODO(robin): attach correct token
		check_error(c, f.t, "use of undefined label %q", e.name.ident)
	}
}
