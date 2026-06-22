#+vet explicit-allocators
package mic

import "core:fmt"
import "core:container/xar"

codegen :: proc(u: ^Tacky_Unit, out_u: ^Asm_Unit) {
	initial_gen :: proc(u: ^Tacky_Unit, out_u: ^Asm_Unit) {
		function       := asm_new(out_u, Asm_Def_Function)
		function.name   = asm_clone_string(out_u, u.function.name)
		out_u.function  = function

		insts :: proc(function: ^Asm_Def_Function, instructions: ..Asm_Inst) {
			xar.append(&function.instructions, ..instructions)
		}

		convert_value_to_operand :: proc(function: ^Asm_Def_Function, operand: Tacky_Value) -> Asm_Operand {
			switch op in operand {
			case Tacky_Value_Constant:
				return Asm_Immediate(op)
			case Tacky_Value_Variable:
				pseudo := Asm_Pseudo(op)
				function.largest_pseudo = max(function.largest_pseudo, pseudo)
				return pseudo
			}
			fmt.panicf("invalid operand %v", operand)
		}

		for it := xar.iterator(&u.function.instructions); inst in xar.iterate_by_val(&it) {
			switch i in inst {
			case Tacky_Inst_Return:
				insts(
					function,
					Asm_Inst_Mov {
						src = convert_value_to_operand(function, Tacky_Value(i)),
						dst = .AX,
					},
					Asm_Inst_Ret {},
				)
			case Tacky_Inst_Unary:
				dst := convert_value_to_operand(function, i.dst)

				insts(
					function,
					Asm_Inst_Mov {
						src = convert_value_to_operand(function, i.src),
						dst = dst,
					},
					Asm_Inst_Unary {
						operand  = dst,
						operator = tacky_unary_operator_to_asm_unary_operator(i.operator),
					},
				)
			}
		}
	}

	replace_pseudo :: proc(u: ^Asm_Unit) -> int {
		temp := TEMP_ALLOCATOR_GUARD()
		pseudo_to_stack_table := make_slice([]Asm_Stack, u.function.largest_pseudo+1, allocator = temp)

		for i in 0..=u.function.largest_pseudo {
			// +1 because we have to start at -4
			pseudo_to_stack_table[i] = Asm_Stack(-((i + 1) * 4))
		}

		current_stack_depth := 0

		replace_operand :: proc(operand: ^Asm_Operand, pseudo_to_stack_table: []Asm_Stack, current_stack_depth: ^int) {
			pseudo, ok := operand.(Asm_Pseudo)
			if !ok {
				return
			}

			operand^ = pseudo_to_stack_table[pseudo]
		}

		for it := xar.iterator(&u.function.instructions); inst in xar.iterate_by_ptr(&it) {
			switch &i in inst {
			case Asm_Inst_Mov:
				replace_operand(&i.src, pseudo_to_stack_table, &current_stack_depth)
				replace_operand(&i.dst, pseudo_to_stack_table, &current_stack_depth)
			case Asm_Inst_Unary:
				replace_operand(&i.operand, pseudo_to_stack_table, &current_stack_depth)
			case Asm_Inst_Allocate_Stack:
			case Asm_Inst_Ret:
			}
		}

		return len(pseudo_to_stack_table) * 4
	}

	fixup_instructions :: proc(u: ^Asm_Unit, largest_stack_offset: int) {
		new_instructions: Asm_Instructions
		xar.init(&new_instructions, asm_allocator(u))

		xar.append(&new_instructions, Asm_Inst_Allocate_Stack(largest_stack_offset))

		for it := xar.iterator(&u.function.instructions); inst in xar.iterate_by_val(&it) {
			switch i in inst {
			case Asm_Inst_Mov:
				src, src_ok := i.src.(Asm_Stack)
				dst, dst_ok := i.dst.(Asm_Stack)
				if src_ok && dst_ok {
					xar.append(
						&new_instructions,
						Asm_Inst_Mov { src = src,              dst = Asm_Register.R10 },
						Asm_Inst_Mov { src = Asm_Register.R10, dst = dst },
					)
				} else {
					xar.append(&new_instructions, i)
				}
			case Asm_Inst_Ret, Asm_Inst_Allocate_Stack, Asm_Inst_Unary:
				xar.append(&new_instructions, i)
			}
		}

		u.function.instructions = new_instructions
	}

	initial_gen(u, out_u)
	largest_stack_offset := replace_pseudo(out_u)
	fixup_instructions(out_u, largest_stack_offset)
}
