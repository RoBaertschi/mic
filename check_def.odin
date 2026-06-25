package mic

import "core:container/xar"

check_def_function :: proc(c: ^Checker_Context, f: ^Ast_Def_Function) {
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
}
