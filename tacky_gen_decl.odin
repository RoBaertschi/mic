package mic

tacky_gen_decl :: proc(c: ^Tacky_Gen_Context, decl: ^Ast_Decl) {
	switch d in decl.variant {
	case ^Ast_Decl_Error: panic("error decl")
	case ^Ast_Decl_Variable:
		ensure(d.entity != nil)
		var                       := tacky_gen_make_temporary(c)
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

