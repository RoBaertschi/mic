package mic


check_decl :: proc(c: ^Checker_Context, decl: ^Ast_Decl) {
	switch d in decl.variant {
	case ^Ast_Decl_Error:
		check_error(c, d.t, "invalid declaration")
	case ^Ast_Decl_Variable:
		e, ok := check_lookup_scope(c, d.name.ident)
		if ok {
			check_error(c, d.t, "redeclaration for %q", e.name.ident)
			return
		}

		e = entity_new(c.u, .Variable, d.name, d)
		check_insert_scope(c, e)

		if d.init != nil {
			o: Operand
			check_expr(c, d.init, &o)
		}
	}
}
