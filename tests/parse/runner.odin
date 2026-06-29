#+vet explicit-allocators
package mic_tests_parse

import "core:path/filepath"
import "core:fmt"
import "core:strings"
import "../../"

import "core:os"
tests := []string{
	"simple_function",
}

SPLIT :: "\n---\n"
TESTS_DIR :: "./tests/parse"

main :: proc() {
	for test_file in tests {
		actual_file, _ := filepath.join({TESTS_DIR, test_file})
		content_bytes, err := os.read_entire_file(actual_file, context.allocator)
		ensure(err == nil)
		defer delete(content_bytes)

		content := string(content_bytes)

		split_pos := strings.index(content, SPLIT)
		code := content[:split_pos]
		result := strings.trim_space(content[split_pos+len(SPLIT):])

		b: strings.Builder
		defer strings.builder_destroy(&b)
		mic.parse_full(code, strings.to_stream(&b))
		new_result := strings.trim_space(strings.to_string(b))

		if result != new_result {
			fmt.printfln("expected:\n%v", result)
			fmt.printfln("got:\n%v", new_result)
			os.exit(1)
		}
	}
}
