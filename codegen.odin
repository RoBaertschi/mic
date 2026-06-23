#+vet explicit-allocators
package mic

import "core:fmt"
import "core:container/xar"

codegen :: proc(u: ^Tacky_Unit, out_u: ^Asm_Unit) {
	mov :: proc(src, dst: Asm_Operand) -> Asm_Inst_Mov {
		return Asm_Inst_Mov {
			src = src,
			dst = dst,
		}
	}

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
				function.pseudo_count = max(function.pseudo_count, int(pseudo)+1)
				return pseudo
			}
			fmt.panicf("invalid operand %v", operand)
		}

		convert_label :: proc(label: Tacky_Label) -> Asm_Label {
			return Asm_Label(label)
		}

		for it := xar.iterator(&u.function.instructions); inst in xar.iterate_by_val(&it) {
			switch i in inst {
			case Tacky_Inst_Return:
				insts(
					function,
					mov(convert_value_to_operand(function, Tacky_Value(i)), .AX),
					Asm_Inst_Plain.Ret,
				)
			case Tacky_Inst_Unary:
				dst := convert_value_to_operand(function, i.dst)
				src := convert_value_to_operand(function, i.src)

				switch i.operator {
				case .Complement, .Negate:
					insts(
						function,
						mov(src, dst),
						Asm_Inst_Unary {
							operand  = dst,
							operator = tacky_unary_operator_to_asm_unary_operator(i.operator),
						},
					)

				case .Not:
					insts(
						function,
						Asm_Inst_Cmp {
							lhs = Asm_Immediate(0),
							rhs = src,
						},
						mov(Asm_Immediate(0), dst),
						Asm_Inst_Set_CC {
							code    = .E,
							operand = dst,
						},
					)
				}
			case Tacky_Inst_Binary:
				dst := convert_value_to_operand(function, i.dst)
				lhs := convert_value_to_operand(function, i.lhs)
				rhs := convert_value_to_operand(function, i.rhs)

				switch i.operator {
				case .Multiply, .Add, .Subtract, .Bitwise_And,
					 .Bitwise_Or, .Bitwise_Xor, .Left_Shift, .Right_Shift:
					insts(
						function,
						mov(lhs, dst),
						Asm_Inst_Binary {
							operator = tacky_binary_operator_to_asm_unary_operator(i.operator),
							dst      = dst,
							src      = rhs,
						},
					)
				case .Divide, .Remainder:
					insts(
						function,
						mov(lhs, .AX),
						.Cdq,
						Asm_Inst_Idiv {
							operand = rhs,
						},
						mov(
							.AX if i.operator == .Divide else .DX,
							dst,
						),
					)
				case .Equal,
					 .Not_Equal,
					 .Less_Than,
					 .Less_Or_Equal,
					 .Greater_Than,
					 .Greater_Or_Equal:

					condition_code_mapped := #partial [Tacky_Binary_Operator]Asm_Condition_Code {
						.Equal            = .E,
						.Not_Equal        = .NE,
						.Less_Than        = .L,
						.Less_Or_Equal    = .LE,
						.Greater_Than     = .G,
						.Greater_Or_Equal = .GE,
					}


					insts(
						function,
						Asm_Inst_Cmp {
							lhs = rhs, // NOTE: intentionally switched
							rhs = lhs,
						},
						mov(Asm_Immediate(0), dst),
						Asm_Inst_Set_CC {
							code    = condition_code_mapped[i.operator],
							operand = dst,
						},
					)
				}
			case Tacky_Inst_Copy:
				insts(
					function,
					mov(
						convert_value_to_operand(function, i.src),
						convert_value_to_operand(function, i.dst),
					),
				)
			case Tacky_Inst_Jump:
				insts(
					function,
					Asm_Inst_Jmp {
						target = convert_label(i.target),
					},
				)
			case Tacky_Inst_Jump_If_Zero:
				insts(
					function,
					Asm_Inst_Cmp {
						lhs = Asm_Immediate(0),
						rhs = convert_value_to_operand(function, i.condition),
					},
					Asm_Inst_Jmp_CC {
						code   = .E,
						target = convert_label(i.target),
					},
				)
			case Tacky_Inst_Jump_If_Not_Zero:
				insts(
					function,
					Asm_Inst_Cmp {
						lhs = Asm_Immediate(0),
						rhs = convert_value_to_operand(function, i.condition),
					},
					Asm_Inst_Jmp_CC {
						code   = .NE,
						target = convert_label(i.target),
					},
				)

			case Tacky_Inst_Label:
				insts(
					function,
					convert_label(i),
				)
			}
		}
	}

	replace_pseudo :: proc(u: ^Asm_Unit) -> int {
		temp := TEMP_ALLOCATOR_GUARD()
		pseudo_to_stack_table := make_slice([]Asm_Stack, u.function.pseudo_count, allocator = temp)

		for i in 0..<u.function.pseudo_count {
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
			case Asm_Inst_Binary:
				replace_operand(&i.src, pseudo_to_stack_table, &current_stack_depth)
				replace_operand(&i.dst, pseudo_to_stack_table, &current_stack_depth)
			case Asm_Inst_Idiv:
				replace_operand(&i.operand, pseudo_to_stack_table, &current_stack_depth)
			case Asm_Inst_Cmp:
				replace_operand(&i.lhs, pseudo_to_stack_table, &current_stack_depth)
				replace_operand(&i.rhs, pseudo_to_stack_table, &current_stack_depth)
			case Asm_Inst_Set_CC:
				replace_operand(&i.operand, pseudo_to_stack_table, &current_stack_depth)
			case Asm_Inst_Allocate_Stack,
				 Asm_Inst_Plain,
				 Asm_Inst_Label,
				 Asm_Inst_Jmp,
				 Asm_Inst_Jmp_CC: // NOTE: deliberately left empty
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
						mov(src, .R10),
						mov(.R10, dst),
					)
				} else {
					xar.append(&new_instructions, i)
				}
			case Asm_Inst_Cmp:
				lhs, lhs_ok := i.lhs.(Asm_Stack)

				#partial switch rhs in i.rhs {
				case Asm_Immediate:
					xar.append(
						&new_instructions,
						mov(rhs, .R11),
						Asm_Inst_Cmp {
							lhs = i.lhs,
							rhs = .R11,
						},
					)
				case Asm_Stack:
					if lhs_ok {
						xar.append(
							&new_instructions,
							mov(lhs, .R10),
							Asm_Inst_Cmp {
								lhs = Asm_Register.R10,
								rhs = rhs,
							},
						)
					} else {
						xar.append(&new_instructions, i)
					}
				case:
					xar.append(&new_instructions, i)
				}

			case Asm_Inst_Binary:
				#partial switch i.operator {
				case .Mult:
					dst, dst_ok := i.dst.(Asm_Stack)
					if dst_ok {
						xar.append(
							&new_instructions,
							mov(dst, .R11),
							Asm_Inst_Binary {
								operator = i.operator,
								src = i.src,
								dst = .R11,
							},
							mov(.R11, dst),
						)
					} else {
						xar.append(&new_instructions, i)
					}
				case .Sal, .Sar:
					src, src_ok := i.src.(Asm_Stack)
					dst, dst_ok := i.dst.(Asm_Stack)
					if src_ok && dst_ok {
						xar.append(
							&new_instructions,
							mov(.CX, .R10),
							mov(src, .CX),
							Asm_Inst_Binary {
								operator = i.operator,
								src      = .CX,
								dst      = dst,
							},
							mov(.R10, .CX),
						)
					} else {
						xar.append(&new_instructions, i)
					}
				case:
					src, src_ok := i.src.(Asm_Stack)
					dst, dst_ok := i.dst.(Asm_Stack)
					if src_ok && dst_ok {
						xar.append(
							&new_instructions,
							mov(src, .R10),
							Asm_Inst_Binary {
								operator = i.operator,
								src      = Asm_Register.R10,
								dst      = dst,
							},
						)
					} else {
						xar.append(&new_instructions, i)
					}
				}
			case Asm_Inst_Idiv:
				operand, operand_ok := i.operand.(Asm_Immediate)
				if operand_ok {
					xar.append(
						&new_instructions,
						mov(operand, .R10),
						Asm_Inst_Idiv {
							operand = .R10,
						},
					)
				} else {
					xar.append(&new_instructions, i)
				}
			case Asm_Inst_Plain,
				 Asm_Inst_Allocate_Stack,
				 Asm_Inst_Unary,
				 Asm_Inst_Jmp,
				 Asm_Inst_Jmp_CC,
				 Asm_Inst_Set_CC,
				 Asm_Inst_Label:
				xar.append(&new_instructions, i)
			}
		}

		u.function.instructions = new_instructions
	}

	initial_gen(u, out_u)
	largest_stack_offset := replace_pseudo(out_u)
	fixup_instructions(out_u, largest_stack_offset)
}
