#+vet explicit-allocators
package mic

import "core:fmt"

tacky_gen_get_lvalue :: proc(c: ^Tacky_Gen_Context, expr: ^Ast_Expr) -> Tacky_Value {
	#partial switch e in expr.variant {
	case ^Ast_Expr_Variable:
		ensure(e.entity != nil)
		value, ok := c.entity_values[e.entity]
		ensure(ok)
		return value
	case:
		fmt.panicf("invalid l-value expression %v", e)
	}
}

tacky_gen_expr :: proc(c: ^Tacky_Gen_Context, expr: ^Ast_Expr) -> Tacky_Value {
	switch e in expr.variant {
	case nil:             panic("nil expr")
	case ^Ast_Expr_Error: panic("error expr")
	case ^Ast_Expr_Constant:
		return Tacky_Value_Constant(e.constant)
	case ^Ast_Expr_Unary:
		switch e.operator {
		case .Complement, .Negate, .Not:
			@(static)
			ast_to_tacky := #partial [Ast_Unary_Operator]Tacky_Unary_Operator {
				.Complement = .Complement,
				.Negate     = .Negate,
				.Not        = .Not,
			}

			src := tacky_gen_expr(c, e.inner)
			dst := tacky_gen_make_temporary(c)
			tacky_gen_instructions(
				c,
				Tacky_Inst_Unary {
					operator = ast_to_tacky[e.operator],
					dst      = dst,
					src      = src,
				},
			)
			return dst
		case .Increment, .Decrement:
			@(static)
			ast_to_tacky := #partial [Ast_Unary_Operator]Tacky_Binary_Operator {
				.Increment = .Add,
				.Decrement = .Subtract,
			}

			dst := tacky_gen_make_temporary(c)
			var := tacky_gen_get_lvalue(c, e.inner)
			tacky_gen_instructions(
				c,
				Tacky_Inst_Binary {
					operator = ast_to_tacky[e.operator],
					lhs      = var,
					rhs      = Tacky_Value_Constant(1),
					dst      = var,
				},
				Tacky_Inst_Copy {
					src = var,
					dst = dst,
				},
			)
			return dst
		}

	case ^Ast_Expr_Postfix:
		dst := tacky_gen_make_temporary(c)
		var := tacky_gen_get_lvalue(c, e.inner)

		@(static)
		ast_to_tacky := [Ast_Postfix_Operator]Tacky_Binary_Operator {
			.Increment = .Add,
			.Decrement = .Subtract,
		}

		tacky_gen_instructions(
			c,
			Tacky_Inst_Copy {
				src = var,
				dst = dst,
			},
			Tacky_Inst_Binary {
				operator = ast_to_tacky[e.operator],
				lhs      = var,
				rhs      = Tacky_Value_Constant(1),
				dst      = var,
			},
		)
		return dst
	case ^Ast_Expr_Binary:
		#partial switch e.operator {
		case .And:
			false_label := tacky_gen_make_label(c)
			end_label   := tacky_gen_make_label(c)
			dst         := tacky_gen_make_temporary(c)
			lhs         := tacky_gen_expr(c, e.lhs)

			tacky_gen_instructions(
				c,
				Tacky_Inst_Jump_If_Zero {
					condition = lhs,
					target    = false_label,
				}
			)
			rhs := tacky_gen_expr(c, e.rhs)

			tacky_gen_instructions(
				c,
				Tacky_Inst_Jump_If_Zero {
					target    = false_label,
					condition = rhs,
				},
				Tacky_Inst_Copy {
					src = Tacky_Value_Constant(1),
					dst = dst,
				},
				Tacky_Inst_Jump {
					target = end_label,
				},
				false_label,
				Tacky_Inst_Copy {
					src = Tacky_Value_Constant(0),
					dst = dst,
				},
				end_label,
			)

			return dst

		case .Or:
			true_label := tacky_gen_make_label(c)
			end_label   := tacky_gen_make_label(c)
			dst         := tacky_gen_make_temporary(c)
			lhs         := tacky_gen_expr(c, e.lhs)

			tacky_gen_instructions(
				c,
				Tacky_Inst_Jump_If_Not_Zero {
					condition = lhs,
					target    = true_label,
				}
			)
			rhs := tacky_gen_expr(c, e.rhs)

			tacky_gen_instructions(
				c,
				Tacky_Inst_Jump_If_Not_Zero {
					target    = true_label,
					condition = rhs,
				},
				Tacky_Inst_Copy {
					src = Tacky_Value_Constant(0),
					dst = dst,
				},
				Tacky_Inst_Jump {
					target = end_label,
				},
				true_label,
				Tacky_Inst_Copy {
					src = Tacky_Value_Constant(1),
					dst = dst,
				},
				end_label,
			)

			return dst

		case:
			@(static)
			ast_to_tacky := #partial [Ast_Binary_Operator]Tacky_Binary_Operator {
				.Add              = .Add,
				.Subtract         = .Subtract,
				.Multiply         = .Multiply,
				.Divide           = .Divide,
				.Remainder        = .Remainder,
				.Bitwise_And      = .Bitwise_And,
				.Bitwise_Or       = .Bitwise_Or,
				.Bitwise_Xor      = .Bitwise_Xor,
				.Left_Shift       = .Left_Shift,
				.Right_Shift      = .Right_Shift,
				.Equal            = .Equal,
				.Not_Equal        = .Not_Equal,
				.Less_Than        = .Less_Than,
				.Less_Or_Equal    = .Less_Or_Equal,
				.Greater_Than     = .Greater_Than,
				.Greater_Or_Equal = .Greater_Or_Equal,
			}

			lhs, rhs := tacky_gen_expr(c, e.lhs), tacky_gen_expr(c, e.rhs)
			dst      := tacky_gen_make_temporary(c)
			tacky_gen_instructions(
				c,
				Tacky_Inst_Binary {
					operator = ast_to_tacky[e.operator],
					lhs      = lhs,
					rhs      = rhs,
					dst      = dst,
				},
			)
			return dst
		}
	case ^Ast_Expr_Variable:
		var := c.entity_values[e.entity]
		ensure(var != nil)
		return var
	case ^Ast_Expr_Assignment:
		var    := tacky_gen_get_lvalue(c, e.lhs)
		result := tacky_gen_expr(c, e.rhs)

		if e.operator != .None {
			@(static)
			ast_to_tacky := [Ast_Assignment_Operator]Tacky_Binary_Operator {
				.None        = .Subtract,
				.Add         = .Add,
				.Subtract    = .Subtract,
				.Multiply    = .Multiply,
				.Divide      = .Divide,
				.Remainder   = .Remainder,
				.Bitwise_And = .Bitwise_And,
				.Bitwise_Or  = .Bitwise_Or,
				.Bitwise_Xor = .Bitwise_Xor,
				.Left_Shift  = .Left_Shift,
				.Right_Shift = .Right_Shift,
			}

			tacky_gen_instructions(
				c,
				Tacky_Inst_Binary {
					operator = ast_to_tacky[e.operator],
					lhs      = var,
					rhs      = result,
					dst      = var,
				},
			)
		} else {
			tacky_gen_instructions(
				c,
				Tacky_Inst_Copy {
					src = result,
					dst = var,
				},
			)
		}

		return var
	case ^Ast_Expr_Conditional:
		dst := tacky_gen_make_temporary(c)

		condition := tacky_gen_expr(c, e.condition)

		else_label := tacky_gen_make_label(c)
		end_label  := tacky_gen_make_label(c)

		tacky_gen_instructions(
			c,
			Tacky_Inst_Jump_If_Zero {
				condition = condition,
				target    = else_label,
			},
		)

		then_value := tacky_gen_expr(c, e.then)

		tacky_gen_instructions(
			c,
			Tacky_Inst_Copy {
				src = then_value,
				dst = dst,
			},
			Tacky_Inst_Jump {
				target = end_label,
			},
			else_label,
		)

		else_value := tacky_gen_expr(c, e.else_)

		tacky_gen_instructions(
			c,
			Tacky_Inst_Copy {
				src = else_value,
				dst = dst,
			},
			end_label,
		)
		return dst
	}
	fmt.panicf("invalid expr %v", expr.variant)
}
