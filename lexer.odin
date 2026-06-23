#+vet explicit-allocators
package mic

import "core:unicode/utf8"

Token_Kind :: enum {
	Invalid,
	EOF,

	Open_Paren,          // (
	Close_Paren,         // )
	Open_Brace,          // {
	Close_Brace,         // }
	Semicolon,           // ;
	Tilde,               // ~
	Hyphen,              // -
	Two_Hyphen,          // --
	Plus,                // +
	Asterisk,            // *
	Forward_Slash,       // /
	Precent,             // %
	Ampersand,           // &
	Pipe,                // |
	Caret,               // ^
	Double_Less_Than,    // <<
	Double_Greater_Than, // >>
	Exclamation,         // !
	Double_Ampersand,    // &&
	Double_Pipe,         // ||
	Double_Equal,        // ==
	Exclamation_Equal,   // !=
	Less_Than,           // <
	Greater_Than,        // >
	Less_Than_Equal,     // <=
	Greater_Than_Equal,  // >=

	Identifier,
	Constant,

	// Keywords
	Int,
	Void,
	Return,
}

Token :: struct {
	using pos: Pos,
	content:   string,
	kind:      Token_Kind,
}

Pos :: struct {
	line, col, idx: int
}

L_Error_Proc :: #type proc(data: rawptr, pos: Pos, format: string, args: ..any)

Lexer :: struct {
	input: string,

	ch:     rune,
	ch_len: int,

	using pos: Pos,

	errors:     int,
	error_proc: L_Error_Proc,
	error_data: rawptr,
}

l_init :: proc(l: ^Lexer, input: string, error_proc: L_Error_Proc, error_data: rawptr = nil) {
	l^ = { input = input, error_proc = error_proc, error_data = error_data, line = 1 }
	l_next_ch(l)
}

l_error :: proc(l: ^Lexer, format: string, args: ..any) {
	l.errors += 1
	if l.error_proc != nil {
		l.error_proc(l.error_data, l.pos, format, ..args)
	}
}

l_next_ch :: proc(l: ^Lexer) {
	l.idx += l.ch_len

	if l.idx < len(l.input) {
		if l.ch == '\n' {
			l.line += 1
			l.col   = 1
		} else {
			l.col += 1
		}

		l.ch, l.ch_len = utf8.decode_rune(l.input[l.idx:])
		if l.ch == utf8.RUNE_ERROR {
			if l.ch_len <= 0 {
				l.ch_len = 1
			}

			l_error(l, "invalid character at %v", l.idx)
		}
	} else {
		l.ch, l.ch_len = utf8.RUNE_EOF, 0
	}
}

l_peek_ch :: proc(l: ^Lexer) -> rune {
	if l.idx + l.ch_len >= len(l.input) {
		return utf8.RUNE_EOF
	}
	r, _ := utf8.decode_rune(l.input[l.idx+l.ch_len:])
	return r
}

l_is_digit :: proc(ch: rune) -> bool {
	return '0' <= ch && ch <= '9'
}

l_is_ident_start_letter :: proc(ch: rune) -> bool {
	return ('a' <= ch && ch <= 'z') || ('A' <= ch && ch <= 'Z') || ch == '_'
}

l_is_ident_letter :: proc(ch: rune) -> bool {
	return l_is_ident_start_letter(ch) || l_is_digit(ch)
}

l_is_whitespace :: proc(ch: rune) -> bool {
	return ch == ' ' || ch == '\n' || ch == '\r' || ch == '\t'
}

l_skip_whitespace :: proc(l: ^Lexer) {
	for l_is_whitespace(l.ch) {
		l_next_ch(l)
	}
}

l_read_identifier :: proc(l: ^Lexer) -> (t: Token) {
	t.pos  = l.pos
	t.kind = .Identifier

	for l_is_ident_letter(l.ch) {
		l_next_ch(l)
	}

	t.content = l.input[t.idx:l.idx]

	switch t.content {
	case "int":    t.kind = .Int
	case "void":   t.kind = .Void
	case "return": t.kind = .Return
	}

	return t
}

l_read_constant :: proc(l: ^Lexer) -> (t: Token) {
	t.pos  = l.pos
	t.kind = .Constant

	for l_is_digit(l.ch) {
		l_next_ch(l)
	}

	if l_is_ident_letter(l.ch) {
		// TODO: support constant suffixes
		l_error(l, "constant suffixes not supported")
		t.kind = .Invalid
	}

	t.content = l.input[t.idx:l.idx]
	return t
}

l_next_token :: proc(l: ^Lexer) -> (t: Token) {
	l_skip_whitespace(l)

	t = Token{pos = l.pos}

	switch {
	case l_is_ident_start_letter(l.ch):
		return l_read_identifier(l)
	case l_is_digit(l.ch):
		return l_read_constant(l)
	}

	switch l.ch {
	case '(':           t.kind = .Open_Paren
	case ')':           t.kind = .Close_Paren
	case '{':           t.kind = .Open_Brace
	case '}':           t.kind = .Close_Brace
	case ';':           t.kind = .Semicolon
	case '~':           t.kind = .Tilde
	case '+':           t.kind = .Plus
	case '*':           t.kind = .Asterisk
	case '/':           t.kind = .Forward_Slash
	case '%':           t.kind = .Precent
	case '^':           t.kind = .Caret
	case utf8.RUNE_EOF: t.kind = .EOF

	case '&':
		if l_peek_ch(l) == '&' {
			t.kind = .Double_Ampersand
			l_next_ch(l)
		} else {
			t.kind = .Ampersand
		}
	case '|':
		if l_peek_ch(l) == '|' {
			t.kind = .Double_Pipe
			l_next_ch(l)
		} else {
			t.kind = .Pipe
		}
	case '<':
		switch l_peek_ch(l) {
		case '<': t.kind = .Double_Less_Than; l_next_ch(l)
		case '=': t.kind = .Less_Than_Equal;  l_next_ch(l)
		case:     t.kind = .Less_Than
		}
	case '>':
		switch l_peek_ch(l) {
		case '>': t.kind = .Double_Greater_Than; l_next_ch(l)
		case '=': t.kind = .Greater_Than_Equal;  l_next_ch(l)
		case:     t.kind = .Greater_Than
		}
	case '-':
		if l_peek_ch(l) == '-' {
			t.kind = .Two_Hyphen
			l_next_ch(l)
		} else {
			t.kind = .Hyphen
		}
	case '!':
		if l_peek_ch(l) == '=' {
			t.kind = .Exclamation_Equal
			l_next_ch(l)
		} else {
			t.kind = .Exclamation
		}
	case '=':
		if l_peek_ch(l) == '=' {
			t.kind = .Double_Equal
			l_next_ch(l)
		}
	
	case:
		l_error(l, "unexpected character %q", l.ch)
	}

	l_next_ch(l)
	t.content = l.input[t.idx:l.idx]

	return t
}
