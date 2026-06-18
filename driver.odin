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
	codegen: bool `usage:"compile the provided c source file"`,

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

	preprocessed_file: ^os.File
	preprocessed_file, err = os.create_temp_file(temp_dir, fmt.aprintf("%s-*.i", filepath.stem(filepath.base(os.name(file))), allocator = temp))
	if err != nil {
		log.fatalf("could not create preprocessed file: %v", err)
		os.exit(1)
	}
	defer {
		os.remove(os.name(preprocessed_file))
		os.close(preprocessed_file)
	}

	desc := os.Process_Desc{
		command = { "gcc", "-E", "-P", "-", "-o", "-" },
		stdout  = preprocessed_file,
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

	os.seek(preprocessed_file, 0, .Start)

	data: []byte
	data, err = os.read_entire_file(preprocessed_file, allocator)

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

main :: proc() {
	context.logger = log.create_console_logger(opt = { .Level, .Terminal_Color }, allocator = context.allocator)

	f: Flags
	temp := TEMP_ALLOCATOR_GUARD()

	flags.parse_or_exit(&f, os.args, .Unix, allocator = temp)

	Stage :: enum {
		None,
		Lex,
		Parse,
		Codegen,
	}

	stage: Stage

	if f.lex {
		stage = .Lex
	}

	if f.parse {
		if stage != .None {
			log.fatalf("multiple stage specifiers found, while only one at the time is supported")
			os.exit(1)
		}
		stage = .Parse
	}

	if f.codegen {
		if stage != .None {
			log.fatalf("multiple stage specifiers found, while only one at the time is supported")
			os.exit(1)
		}
		stage = .Codegen
	}

	if stage == .None {
		stage = .Codegen
	}

	output := preprocess(f.file, temp)

	if stage == .Lex {
		if 0 < lex_full(output, os.to_stream(os.stdout)) {
			os.exit(1)
		}
	}

	if stage == .Parse {
		if 0 < parse_full(output, os.to_stream(os.stdout)) {
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
