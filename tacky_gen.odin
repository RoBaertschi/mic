#+vet explicit-allocators
package mic

import "base:runtime"

import "core:fmt"
import "core:container/xar"

Tacky_Gen_Context :: struct {
	u:             ^Tacky_Unit,
	entity_values: map[^Entity]Tacky_Value,
	entity_labels: map[^Entity]Tacky_Label,
	function:      ^Tacky_Def_Function,
	locals:        Tacky_Value_Variable,
	labels:        Tacky_Label,
}

tacky_gen :: proc(u: ^Unit, out_u: ^Tacky_Unit) {
	function      := tacky_new(out_u, Tacky_Def_Function)
	function.name  = tacky_clone_string(out_u, u.function.name.ident)
	out_u.function = function

	xar.init(&function.instructions, tacky_allocator(out_u))

	c := Tacky_Gen_Context {
		function = function,
		entity_values = make(map[^Entity]Tacky_Value, allocator = runtime.heap_allocator()),
		entity_labels = make(map[^Entity]Tacky_Label, allocator = runtime.heap_allocator()),
		u        = out_u,
	}
	defer {
		delete(c.entity_values)
		delete(c.entity_labels)
	}

	tacky_gen_block(&c, &u.function.body)
	tacky_gen_instructions(&c, Tacky_Inst_Return(Tacky_Value_Constant(0)))
}

tacky_gen_instructions :: proc(c: ^Tacky_Gen_Context, insts: ..Tacky_Inst) {
	xar.append(&c.function.instructions, ..insts)
}

tacky_gen_make_temporary :: proc(c: ^Tacky_Gen_Context) -> (var: Tacky_Value_Variable) {
	var       = c.locals
	c.locals += 1
	return
}

tacky_gen_make_label :: proc(c: ^Tacky_Gen_Context) -> (label: Tacky_Label) {
	label     = c.labels
	c.labels += 1
	return
}

tacky_gen_block :: proc(c: ^Tacky_Gen_Context, body: ^Ast_Block) {
	for it := xar.iterator(body); block_item in xar.iterate_by_val(&it) {
		switch bi in block_item {
		case ^Ast_Stmt:
			tacky_gen_stmt(c, bi)
		case ^Ast_Decl:
			tacky_gen_decl(c, bi)
		}
	}
}

tacky_gen_decl :: proc(c: ^Tacky_Gen_Context, decl: ^Ast_Decl) {
	switch d in decl.variant {
	case ^Ast_Decl_Error: panic("error decl")
	case ^Ast_Decl_Variable:
		ensure(d.entity != nil)
		var                  := tacky_gen_make_temporary(c)
		c.entity_values[d.entity]  = var
		if d.init != nil {
			init := tacky_gen_expr(c, d.init)
			tacky_gen_instructions(
				c,
				Tacky_Inst_Copy {
					src = init,
					dst = var,
				},
			)
		}
	}
}

tacky_gen_stmt :: proc(c: ^Tacky_Gen_Context, stmt: ^Ast_Stmt) {
	lazy_label :: proc(c: ^Tacky_Gen_Context, e: ^Entity) -> Tacky_Label {
		ensure(e != nil)
		label, ok := c.entity_labels[e]
		if !ok {
			label              = tacky_gen_make_label(c)
			c.entity_labels[e] = label
		}

		return label
	}

	switch s in stmt.variant {
	case nil: // valid, but do nothing
	case ^Ast_Stmt_Error:  panic("Error stmt")
	case ^Ast_Stmt_Return:
		value := tacky_gen_expr(c, s.result)
		tacky_gen_instructions(
			c,
			Tacky_Inst_Return(value),
		)
	case ^Ast_Stmt_Expr:
		tacky_gen_expr(c, s.expr)
	case ^Ast_Stmt_If:
		condition := tacky_gen_expr(c, s.condition)
		end_label := tacky_gen_make_label(c)

		if s.else_ == nil {
			tacky_gen_instructions(
				c,
				Tacky_Inst_Jump_If_Zero {
					condition = condition,
					target    = end_label,
				},
			)

			tacky_gen_stmt(c, s.then)

			tacky_gen_instructions(
				c,
				end_label,
			)
		} else {
			else_label := tacky_gen_make_label(c)

			tacky_gen_instructions(
				c,
				Tacky_Inst_Jump_If_Zero {
					condition = condition,
					target    = else_label,
				},
			)

			tacky_gen_stmt(c, s.then)

			tacky_gen_instructions(
				c,
				Tacky_Inst_Jump {
					target = end_label,
				},
				else_label,
			)

			tacky_gen_stmt(c, s.else_)

			tacky_gen_instructions(
				c,
				end_label,
			)
		}
	case ^Ast_Stmt_Label:
		label := lazy_label(c, s.entity)

		tacky_gen_instructions(
			c,
			label,
		)

		tacky_gen_stmt(
			c,
			s.inner,
		)
	case ^Ast_Stmt_Goto:
		label := lazy_label(c, s.entity)

		tacky_gen_instructions(
			c,
			Tacky_Inst_Jump {
				target = label,
			},
		)
	case ^Ast_Stmt_Compound:
		tacky_gen_block(c, &s.block)
	}
}

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
		return Tacky_Value_Constant(e.value)
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
