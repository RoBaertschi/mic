package mic

check_stmt :: proc(c: ^Checker_Context, stmt: ^Ast_Stmt) {
	switch s in stmt.variant {
	case ^Ast_Stmt_Error:
		check_error(c, s.t, "invalid statement")
	case ^Ast_Stmt_Expr:
		o: Operand
		check_expr(c, s.expr, &o)
	case ^Ast_Stmt_Return:
		o: Operand
		check_expr(c, s.result, &o)
	case ^Ast_Stmt_If:
		o: Operand
		check_expr(c, s.condition, &o)
		check_stmt(c, s.then)
		if s.else_ != nil {
			check_stmt(c, s.else_)
		}
	case ^Ast_Stmt_Label:
		if label, ok := check_lookup_label(c, s.name); ok {
			if label.stmt != nil {
				check_error(c, s.t, "duplicate label %q", s.name.ident)
			} else {
				check_resolve_label(c, label, s)
			}
		} else {
			check_new_label(c, s)
		}

		check_stmt(c, s.inner)
	case ^Ast_Stmt_Goto:
		if label, ok := check_lookup_label(c, s.label); ok {
			s.entity = label
		} else {
			check_new_unresolved_label(c, s)
		}
	}
}
