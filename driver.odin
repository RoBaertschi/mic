#+vet explicit-allocators
package mic

import "core:mem"
import "core:io"
import "core:path/filepath"
import "core:fmt"
import "base:runtime"

import "core:log"
import "core:os"
import "core:flags"
import "core:mem/virtual"

Flags :: struct {
	lex:     bool `usage:"only lex the provided c source file"`,
	parse:   bool `usage:"lex and parse the provided c source file"`,
	tacky:   bool `usage:"only generate the tacky for the provided c source file"`,
	codegen: bool `usage:"compile the provided c source file and print the asm ir"`,
	s:       bool `usage:"compile the provided c source file and print the asm"`,

	file: ^os.File `usage:"the input c source file" args:"required,pos=0"`,
}

preprocess :: proc(file: ^os.File, allocator: mem.Allocator) -> string {
	temp := TEMP_ALLOCATOR_GUARD(allocator)
	temp_dir, err := os.temp_directory(temp)
	if err != nil {
		// NOTE: in theory we could also try to use the current working directory as a temporary direcotry
		log.fatalf("could not get temporary directory: %v", err)
		os.exit(1)
	}

	r_preprocessed, w_preprocessed: ^os.File
	r_preprocessed, w_preprocessed, err = os.pipe()
	if err != nil {
		log.fatalf("could not create preprocessed pipes: %v", err)
		os.exit(1)
	}
	defer {
		os.close(r_preprocessed)
	}

	desc := os.Process_Desc{
		command = { "gcc", "-E", "-P", "-", "-o", "-" },
		stdout  = w_preprocessed,
		stdin   = file,
	}

	process:       os.Process
	process, err = os.process_start(desc)

	if err != nil {
		log.fatalf("could not start process(%v): %v", desc.command, err)
		os.exit(1)
	}

	process_state: os.Process_State
	process_state, err = os.process_wait(process)

	if err != nil {
		log.fatalf("could not wait for process(%v): %v", desc.command, err)
		os.exit(1)
	}

	// NOTE: needs to be closed before we want to read but after all the writes are done
	os.close(w_preprocessed)

	os.seek(r_preprocessed, 0, .Start)

	data: []byte
	data, err = os.read_entire_file(r_preprocessed, allocator)

	if err != nil {
		log.fatalf("could not read output of preprocessor: %v", err)
		os.exit(1)
	}

	return string(data)
}

lex_full :: proc(s: string, w: io.Writer) -> int {
	w := w

	l: Lexer
	l_init(&l, s, proc(w_raw: rawptr, pos: Pos, format: string, args: ..any) {
		w := (^io.Writer)(w_raw)^
		temp := TEMP_ALLOCATOR_GUARD()
		msg := fmt.aprintf(format, ..args, allocator = temp)
		fmt.wprintfln(w, "Error:%d:%d:%v", pos.line, pos.col, msg)
	}, &w)

	for token := l_next_token(&l); token.kind != .EOF; token = l_next_token(&l) {
		token_len := len(token.content)

		if token_len > 1 {
			fmt.wprintfln(
				w,
				"%v:%v-%v(%v-%v):%v:%q",
				token.line,
				token.col,
				token.col + token_len,
				token.idx,
				token.idx + token_len,
				token.kind,
				token.content,
			)
		} else {
			fmt.wprintfln(w, "%v:%v(%v):%v:%q", token.line, token.col, token.idx, token.kind, token.content)
		}
	}

	return l.errors
}

parse_full :: proc(s: string, w: io.Writer) -> int {
	w := w

	l: Lexer
	l_init(&l, s, proc(w_raw: rawptr, p: Pos, format: string, args: ..any) {
		w := (^io.Writer)(w_raw)^

		temp := TEMP_ALLOCATOR_GUARD()
		message := fmt.aprintf(format, ..args, allocator = temp)
		fmt.wprintf(w, "Error:LEXER:%d:%d:%v\n", p.line, p.col, message)
	}, &w)
	u: Unit
	p: Parser
	p_init(&p, &u, &l, proc(w_raw: rawptr, t: Token, format: string, args: ..any) {
		w := (^io.Writer)(w_raw)^

		temp := TEMP_ALLOCATOR_GUARD()
		message := fmt.aprintf(format, ..args, allocator = temp)
		fmt.wprintf(w, "Error:PARSER:%d:%d:%v\n", t.line, t.col, message)
	}, &w)

	p_parse_unit(&p)

	unit_write_human_readable(&u, w)

	return l.errors + p.errors
}

parse_ast :: proc(s: string, u: ^Unit, w: io.Writer) -> int {
	w := w

	l: Lexer
	l_init(&l, s, proc(w_raw: rawptr, p: Pos, format: string, args: ..any) {
		w := (^io.Writer)(w_raw)^

		temp := TEMP_ALLOCATOR_GUARD()
		message := fmt.aprintf(format, ..args, allocator = temp)
		fmt.wprintf(w, "Error:LEXER:%d:%d:%v\n", p.line, p.col, message)
	}, &w)
	p: Parser
	p_init(&p, u, &l, proc(w_raw: rawptr, t: Token, format: string, args: ..any) {
		w := (^io.Writer)(w_raw)^

		temp := TEMP_ALLOCATOR_GUARD()
		message := fmt.aprintf(format, ..args, allocator = temp)
		fmt.wprintf(w, "Error:PARSER:%d:%d:%v\n", t.line, t.col, message)
	}, &w)

	p_parse_unit(&p)

	total_errors := l.errors + p.errors

	return total_errors
}


tacky_gen_full :: proc(s: string, w: io.Writer) -> int {
	w := w

	u: Unit
	total_errors := parse_ast(s, &u, w)
	if 0 < total_errors {
		return total_errors
	}

	tacky_u: Tacky_Unit
	tacky_gen(&u, &tacky_u)

	tacky_unit_write_human_readable(&tacky_u, w)
	return 0
}

codegen_full :: proc(s: string, w: io.Writer) -> int {
	w := w

	u: Unit
	total_errors := parse_ast(s, &u, w)
	if 0 < total_errors {
		return total_errors
	}

	tacky_u: Tacky_Unit
	tacky_gen(&u, &tacky_u)

	asm_u: Asm_Unit
	codegen(&tacky_u, &asm_u)

	asm_unit_write_human_readable(&asm_u, w)

	return 0
}

emit_full :: proc(s: string, w: io.Writer) -> int {
	w := w

	l: Lexer
	l_init(&l, s, proc(w_raw: rawptr, p: Pos, format: string, args: ..any) {
		w := (^io.Writer)(w_raw)^

		temp := TEMP_ALLOCATOR_GUARD()
		message := fmt.aprintf(format, ..args, allocator = temp)
		fmt.wprintf(w, "Error:LEXER:%d:%d:%v\n", p.line, p.col, message)
	}, &w)
	u: Unit
	p: Parser
	p_init(&p, &u, &l, proc(w_raw: rawptr, t: Token, format: string, args: ..any) {
		w := (^io.Writer)(w_raw)^

		temp := TEMP_ALLOCATOR_GUARD()
		message := fmt.aprintf(format, ..args, allocator = temp)
		fmt.wprintf(w, "Error:PARSER:%d:%d:%v\n", t.line, t.col, message)
	}, &w)

	p_parse_unit(&p)

	total_errors := l.errors + p.errors

	if total_errors > 0 {
		return total_errors
	}

	tacky_u: Tacky_Unit
	tacky_gen(&u, &tacky_u)

	asm_u: Asm_Unit
	codegen(&tacky_u, &asm_u)

	asm_write(&asm_u, w)

	return 0
}

main :: proc() {
	context.logger = log.create_console_logger(opt = { .Level, .Terminal_Color }, allocator = context.allocator)

	f: Flags
	temp := TEMP_ALLOCATOR_GUARD()

	flags.parse_or_exit(&f, os.args, .Unix, allocator = temp)

	Stage :: enum {
		Emit,
		Lex,
		Parse,
		Tacky_Gen,
		Codegen,
		Asm_Source,
	}

	stage: Stage

	if f.lex {
		stage = .Lex
	}

	if f.parse {
		if stage != .Emit {
			log.fatalf("multiple stage specifiers found, while only one at the time is supported")
			os.exit(1)
		}
		stage = .Parse
	}

	if f.tacky {
		if stage != .Emit {
			log.fatalf("multiple stage specifiers found, while only one at the time is supported")
			os.exit(1)
		}
		stage = .Tacky_Gen
	}

	if f.codegen {
		if stage != .Emit {
			log.fatalf("multiple stage specifiers found, while only one at the time is supported")
			os.exit(1)
		}
		stage = .Codegen
	}

	if f.s {
		if stage != .Emit {
			log.fatalf("multiple stage specifiers found, while only one at the time is supported")
			os.exit(1)
		}
		stage = .Asm_Source
	}

	output := preprocess(f.file, temp)

	switch stage {
	case .Lex:
		if 0 < lex_full(output, os.to_stream(os.stdout)) {
			os.exit(1)
		}
	case .Parse:
		if 0 < parse_full(output, os.to_stream(os.stdout)) {
			os.exit(1)
		}
	case .Tacky_Gen:
		if 0 < tacky_gen_full(output, os.to_stream(os.stdout)) {
			os.exit(1)
		}
	case .Codegen:
		if 0 < codegen_full(output, os.to_stream(os.stdout)) {
			os.exit(1)
		}
	case .Asm_Source:
		if 0 < emit_full(output, os.to_stream(os.stdout)) {
			os.exit(1)
		}
	case .Emit:
		info, err := os.fstat(f.file, temp)
		if err != nil {
			log.fatalf("could not stat input file: %v", err)
			os.exit(1)
		}

		program_name, _ := filepath.join({ filepath.dir(info.fullpath), filepath.stem(info.fullpath) }, allocator = temp)

		r_asm, w_asm: ^os.File
		r_asm, w_asm, err = os.pipe()
		if err != nil {
			log.fatalf("could not create pipe: %v", err)
			os.exit(1)
		}

		process_desc := os.Process_Desc{
			command = { "gcc", "-xassembler", "-", "-o", program_name },
			stdin   = r_asm,
			stdout  = os.stdout,
			stderr  = os.stderr,
		}

		process: os.Process
		process, err = os.process_start(process_desc)

		if err != nil {
			log.fatalf("could not create process: %v", err)
			os.exit(1)
		}

		// NOTE: needs to be closed before we want to read but after all the writes are done
		os.close(r_asm)


		if 0 < emit_full(output, os.to_stream(w_asm)) {
			os.exit(1)
		}

		// NOTE: needs to be closed before we want to read but after all the writes are done
		os.close(w_asm)

		process_state: os.Process_State
		process_state, err = os.process_wait(process)

		if err != nil {
			log.fatalf("could not wait for process: %v", err)
			os.exit(1)
		}
	}
}

@(private="file")
MAX_TEMP_ARENA_COUNT :: 2
@(private="file")
MAX_TEMP_ARENA_COLLISIONS :: MAX_TEMP_ARENA_COUNT - 1
@(private="file", thread_local)
global_default_temp_allocator_arenas: [MAX_TEMP_ARENA_COUNT]virtual.Arena

@(fini, private)
temp_allocator_fini :: proc "contextless" () {
	context = runtime.default_context()

	for &arena in global_default_temp_allocator_arenas {
		virtual.arena_destroy(&arena)
	}
	global_default_temp_allocator_arenas = {}
}

Temp_Allocator :: struct {
	using arena: ^virtual.Arena,
	using allocator: mem.Allocator,
	tmp: virtual.Arena_Temp,
	loc: runtime.Source_Code_Location,
}

TEMP_ALLOCATOR_GUARD_END :: proc(temp: Temp_Allocator) {
	virtual.arena_temp_end(temp.tmp, temp.loc)
}

@(deferred_out=TEMP_ALLOCATOR_GUARD_END)
TEMP_ALLOCATOR_GUARD :: #force_inline proc(collisions: ..mem.Allocator, loc := #caller_location) -> Temp_Allocator {
	assert(len(collisions) <= MAX_TEMP_ARENA_COLLISIONS, "Maximum collision count exceeded. MAX_TEMP_ARENA_COUNT must be increased!")
	good_arena: ^virtual.Arena
	for i in 0..<MAX_TEMP_ARENA_COUNT {
		good_arena = &global_default_temp_allocator_arenas[i]
		for c in collisions {
			if good_arena == c.data {
				good_arena = nil
			}
		}
		if good_arena != nil {
			break
		}
	}
	assert(good_arena != nil)
	tmp := virtual.arena_temp_begin(good_arena, loc)
	return { good_arena, virtual.arena_allocator(good_arena), tmp, loc }
}

temp_allocator_begin :: virtual.arena_temp_begin
	temp_allocator_end :: virtual.arena_temp_end
@(deferred_out=_temp_allocator_end)
temp_allocator_scope :: proc(tmp: Temp_Allocator) -> (virtual.Arena_Temp) {
	return temp_allocator_begin(tmp.arena)
}
@(private="file")
_temp_allocator_end :: proc(tmp: virtual.Arena_Temp) {
	temp_allocator_end(tmp)
}

@(init, private)
init_thread_local_cleaner :: proc "contextless" () {
	runtime.add_thread_local_cleaner(temp_allocator_fini)
}
