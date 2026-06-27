package mic

check_expr :: proc(c: ^Checker_Context, expr: ^Ast_Expr, o: ^Operand) {
	defer o.expr = expr

	switch e in expr.variant {
	case ^Ast_Expr_Error:
		check_error(c, e.t, "invalid expression")
		o.mode = .Invalid
	case ^Ast_Expr_Constant:
		o.mode = .RValue
		return
	case ^Ast_Expr_Variable:
		variable, ok := check_lookup_scope(c, e.name.ident)
		if !ok {
			check_error(c, e.t, "invalid reference %q", e.name.ident)
			o.mode = .Invalid
			return
		}

		switch variable.kind {
		case .Invalid:
			check_error(c, e.t, "invalid entity %q", e.name.ident)
		case .Variable:
			o.mode = .LValue
		}

		e.entity = variable
		return

	case ^Ast_Expr_Unary:
		check_expr(c, e.inner, o)

		if o.mode == .Invalid {
			return
		}

		#partial switch e.operator {
		case .Increment, .Decrement:
			if o.mode != .LValue {
				check_error(c, o.expr.t, "expected l-value for %q operator", e.expr.t.content)

				o.mode = .Invalid
				return
			}
		}

		o.mode = .RValue
		return
	case ^Ast_Expr_Postfix:
		check_expr(c, e.inner, o)
		if o.mode == .Invalid {
			return
		}

		if o.mode != .LValue {
			check_error(c, o.expr.t, "expected l-value for %q operator", e.expr.t.content)

			o.mode = .Invalid
			return
		}
		
		if o.mode != .Invalid {
			o.mode = .RValue
		}
		return
	case ^Ast_Expr_Binary:
		check_expr(c, e.lhs, o)
		rhs: Operand
		check_expr(c, e.rhs, &rhs)

		if rhs.mode == .Invalid || o.mode == .Invalid {
			o.mode = .Invalid
		} else {
			o.mode = .RValue
		}
		return
	case ^Ast_Expr_Assignment:
		check_expr(c, e.lhs, o)
		rhs: Operand
		check_expr(c, e.rhs, &rhs)

		if rhs.mode == .Invalid || o.mode == .Invalid {
			o.mode = .Invalid
			return
		}

		if o.mode != .LValue {
			check_error(c, o.expr.t, "expected l-value on left side of a assignment")
			o.mode = .Invalid
			return
		}

		o.mode = .RValue
		return
	case ^Ast_Expr_Conditional:
		check_expr(c, e.condition, o)
		then, else_: Operand
		check_expr(c, e.then, &then)
		check_expr(c, e.else_, &else_)

		if o.mode == .Invalid || then.mode == .Invalid || else_.mode == .Invalid {
			o.mode = .Invalid
			return
		}

		o.mode = .RValue
		return
	}
}
