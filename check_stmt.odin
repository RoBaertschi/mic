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
	}
}
