package mic_tests_lex

import "../../"

import "core:os"
tests := []string{
	"invalid_identifier",
}

main :: proc() {
	for test_file in tests {
		content, err := os.read_entire_file(test_file, context.allocator)
		ensure(err == nil)
		defer delete(content)

		mic.lex_full()
	}
}
