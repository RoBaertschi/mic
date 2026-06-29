#+vet explicit-allocators
package mic

import "base:intrinsics"
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
	case ^Ast_Stmt_Switch:
		temp := TEMP_ALLOCATOR_GUARD()

		// TODO(robin): would it make sense to only have one global map for these
		//              as the actual keys are all unique across the program
		//              but we would use more memory and the map would maybe be slower
		//              we should measure that someday
		old_switch_cases_map    := c.switch_cases_map
		old_switch_default_case := c.switch_default_case
		defer {
			delete(c.switch_cases_map)
			c.switch_cases_map    = old_switch_cases_map
			c.switch_default_case = old_switch_default_case
		}

		c.switch_cases_map = make(map[^Ast_Stmt_Case]Tacky_Label, xar.len(s.cases), temp)

		label_break := tacky_gen_make_label(c)
		xar.push_back(&c.targets_break, label_break)
		defer {
			assert(xar.pop(&c.targets_break) == label_break)
		}

		dst   := tacky_gen_make_temporary(c)
		value := tacky_gen_expr(c, s.expr)

		for it := xar.iterator(&s.cases); case_ in xar.iterate_by_val(&it) {
			label                     := tacky_gen_make_label(c)
			c.switch_cases_map[case_]  = label

			tacky_gen_expr(c, case_.condition)

			#assert(intrinsics.type_union_variant_count(Const_Value) == 1)
			tacky_gen_instructions(
				c,
				Tacky_Inst_Binary {
					operator = .Equal,
					dst = dst,
					lhs = value,
					rhs = Tacky_Value_Constant(case_.condition.value.(int)),
				},
				Tacky_Inst_Jump_If_Not_Zero {
					condition = dst,
					target    = label,
				},
			)
		}

		if s.default != nil {
			c.switch_default_case = tacky_gen_make_label(c)
			tacky_gen_instructions(
				c,
				Tacky_Inst_Jump {
					target = c.switch_default_case,
				},
			)
		} else {
			tacky_gen_instructions(
				c,
				Tacky_Inst_Jump {
					target = label_break,
				},
			)
		}

		tacky_gen_stmt(c, s.body)

		tacky_gen_instructions(
			c,
			label_break,
		)
	case ^Ast_Stmt_Case:
		label, ok := c.switch_cases_map[s]
		assert(ok)

		tacky_gen_instructions(
			c,
			label,
		)

		tacky_gen_stmt(
			c,
			s.inner,
		)
	case ^Ast_Stmt_Default:
		label := c.switch_default_case

		tacky_gen_instructions(
			c,
			label,
		)

		tacky_gen_stmt(
			c,
			s.inner,
		)
	}
}
