package mic

check_stmt :: proc(c: ^Checker_Context, stmt: ^Ast_Stmt, flags: Check_Stmt_Flags) {
	switch s in stmt.variant {
	case ^Ast_Stmt_Error:
		check_error(c, s.t, "invalid statement")
	case ^Ast_Stmt_Expr:
		check_expr(c, s.expr, &{})
	case ^Ast_Stmt_Return:
		check_expr(c, s.result, &{})
	case ^Ast_Stmt_If:
		check_expr(c, s.condition, &{})
		check_stmt(c, s.then, flags)
		if s.else_ != nil {
			check_stmt(c, s.else_, flags)
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

		check_stmt(c, s.inner, flags)
	case ^Ast_Stmt_Goto:
		if label, ok := check_lookup_label(c, s.label); ok {
			s.entity = label
		} else {
			check_new_unresolved_label(c, s)
		}
	case ^Ast_Stmt_Compound:
		check_scope_guard(c)

		check_block(c, &s.block, flags)
	case ^Ast_Stmt_Break:
		if .Break_Allowed not_in flags {
			check_error(c, s.t, "break is only allowed inside a loop or a switch")
		}
	case ^Ast_Stmt_Continue:
		if .Continue_Allowed not_in flags {
			check_error(c, s.t, "continue is only allowed inside a loop")
		}
	case ^Ast_Stmt_While:
		flags := flags
		flags += {.Break_Allowed, .Continue_Allowed}

		check_expr(c, s.condition, &{})
		check_stmt(c, s.body, flags)

	case ^Ast_Stmt_Do_While:
		flags := flags
		flags += {.Break_Allowed, .Continue_Allowed}

		check_expr(c, s.condition, &{})
		check_stmt(c, s.body, flags)
	case ^Ast_Stmt_For:
		flags := flags
		flags += {.Break_Allowed, .Continue_Allowed}

		// New scope for init declaration
		check_scope_guard(c)

		switch init in s.init {
		case nil: // do nothing
		case ^Ast_Decl:
			check_decl(c, init)
		case ^Ast_Expr:
			check_expr(c, init, &{})
		}

		if s.condition != nil {
			check_expr(c, s.condition, &{})
		}

		if s.post != nil {
			check_expr(c, s.post, &{})
		}

		check_stmt(c, s.body, flags)
	}
}
