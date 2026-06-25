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
	}
}
