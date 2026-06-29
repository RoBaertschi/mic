package mic

import "core:container/xar"

@(private="file")
tacky_gen_push_loop_targets :: proc(c: ^Tacky_Gen_Context) -> (label_break, label_continue: Tacky_Label) {
	label_break, label_continue = tacky_gen_make_label(c), tacky_gen_make_label(c)

	xar.push_back(&c.targets_break, label_break)
	xar.push_back(&c.targets_continue, label_continue)

	return
}

@(private="file")
tacky_gen_pop_loop_targets_assert :: proc(c: ^Tacky_Gen_Context, label_break, label_continue: Tacky_Label) {
	assert(xar_last(&c.targets_break) == label_break)
	assert(xar_last(&c.targets_continue) == label_continue)

	xar.pop(&c.targets_break)
	xar.pop(&c.targets_continue)
}

/*
Guards a loop push of the break and continue label. This also asserts that on pop, that the current targets are actually active.
*/
@(deferred_in_out=tacky_gen_pop_loop_targets_assert, private="file")
tacky_gen_push_loop_targets_guard :: proc(c: ^Tacky_Gen_Context) -> (label_break, label_continue: Tacky_Label) {
	return tacky_gen_push_loop_targets(c)
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
	case ^Ast_Stmt_Break:
		assert(xar.len(c.targets_break) > 0)

		tacky_gen_instructions(
			c,
			Tacky_Inst_Jump {
				target = xar_last(&c.targets_break),
			},
		)
	case ^Ast_Stmt_Continue:
		assert(xar.len(c.targets_continue) > 0)

		tacky_gen_instructions(
			c,
			Tacky_Inst_Jump {
				target = xar_last(&c.targets_continue),
			},
		)
	case ^Ast_Stmt_Do_While:
		label_break, label_continue := tacky_gen_push_loop_targets_guard(c)
		label_start                 := tacky_gen_make_label(c)

		tacky_gen_instructions(
			c,
			label_start,
		)

		tacky_gen_stmt(c, s.body)
		tacky_gen_instructions(
			c,
			label_continue,
		)
		condition := tacky_gen_expr(c, s.condition)
		tacky_gen_instructions(
			c,
			Tacky_Inst_Jump_If_Not_Zero {
				condition = condition,
				target    = label_start,
			},
			label_break,
		)

	case ^Ast_Stmt_While:
		label_break, label_continue := tacky_gen_push_loop_targets_guard(c)

		tacky_gen_instructions(
			c,
			label_continue,
		)
		condition := tacky_gen_expr(c, s.condition)
		tacky_gen_instructions(
			c,
			Tacky_Inst_Jump_If_Zero {
				condition = condition,
				target    = label_break,
			},
		)

		tacky_gen_stmt(c, s.body)
		tacky_gen_instructions(
			c,
			Tacky_Inst_Jump {
				target = label_continue,
			},
			label_break,
		)
	case ^Ast_Stmt_For:
		label_break, label_continue := tacky_gen_push_loop_targets_guard(c)
		label_start                 := tacky_gen_make_label(c)

		switch init in s.init {
		case nil: // Do nothing
		case ^Ast_Decl:
			tacky_gen_decl(c, init)
		case ^Ast_Expr:
			tacky_gen_expr(c, init)
		}

		tacky_gen_instructions(
			c,
			label_start,
		)

		condition: Tacky_Value
		if s.condition != nil {
			condition = tacky_gen_expr(c, s.condition)
		} else {
			condition = Tacky_Value_Constant(1)
		}

		tacky_gen_instructions(
			c,
			Tacky_Inst_Jump_If_Zero {
				condition = condition,
				target    = label_break,
			},
		)

		tacky_gen_stmt(c, s.body)

		tacky_gen_instructions(
			c,
			label_continue,
		)

		if s.post != nil {
			tacky_gen_expr(
				c,
				s.post,
			)
		}

		tacky_gen_instructions(
			c,
			Tacky_Inst_Jump {
				target = label_start,
			},
			label_break,
		)
	case ^Ast_Stmt_Switch:  unimplemented()
	case ^Ast_Stmt_Case:    unimplemented()
	case ^Ast_Stmt_Default: unimplemented()
	}
}

