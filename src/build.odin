package brainfact;

import "core:io";
import "core:os";
import "core:fmt";
import "core:bufio";

// @Cleanup: The only "errors" left to handle in this file are i/o errors (both for the compiler
// and the generated program).
// Understand if there's a standard way of handling/preventing/anticipating them,
// and if not put an explanatory comment.
// @Note: I don't know if print-like functions do dynamic allocations, but ideally that should have
// already been handled by the startup code in main(). If we get here, I assume that all memory
// allocations were successful and that we have enough memory to print those short messages.

builder_write :: proc(s: string) -> (err: io.Error) {
	// Assumes the builder_writer has already been initialized.
	
	for _ in 0..<indent_spaces_per_level * indent_level {
		err = bufio.writer_write_byte(&builder_writer, ' ');
		if err != .None do break;
	}
	
	if err == .None {
		_, err = bufio.writer_write_string(&builder_writer, s);
	}
	
	return;
}

indent_spaces_per_level: int = 4;
indent_level: int;

// Here we have custom i/o procedures in place of getchar/putchar because we want to compile without
// relying on the C standard library.

builder_write_platform_declarations :: proc() -> (err: io.Error) {
	err |= builder_write("\n");
	err |= builder_write("#if defined(_WIN32)\n");
	err |= builder_write("#define STD_INPUT_HANDLE ((uint32_t)-10)\n");
	err |= builder_write("#define STD_OUTPUT_HANDLE ((uint32_t)-11)\n");
	err |= builder_write("__declspec(dllimport) void *__stdcall GetStdHandle(uint32_t);\n");
	err |= builder_write("__declspec(dllimport) int __stdcall ReadConsoleA(void *, void *, uint32_t, uint32_t *, void *);\n");
	err |= builder_write("__declspec(dllimport) int __stdcall WriteConsoleA(void *, const void *, uint32_t, uint32_t *, void *);\n");
	err |= builder_write("#endif\n");
	err |= builder_write("\n");
	return;
}

builder_write_putbyte_definition :: proc() -> (err: io.Error) {
	err |= builder_write("\n");
	err |= builder_write("static bool putbyte(uint8_t byte) {\n");
	err |= builder_write("#if defined(_WIN32)\n");
	indent_level += 1;
	
	err |= builder_write("void *stdout_handle = GetStdHandle(STD_OUTPUT_HANDLE);\n");
	err |= builder_write("uint32_t bytes_written;\n");
	err |= builder_write("bool success = WriteConsoleA(stdout_handle, &byte, 1, &bytes_written, 0) && bytes_written == 1;\n");
	
	indent_level -= 1;
	err |= builder_write("#else\n");
	err |= builder_write("# error Not implemented for this platform.\n");
	err |= builder_write("#endif\n");
	indent_level += 1;
	
	err |= builder_write("return success;\n");
	
	indent_level -= 1;
	err |= builder_write("}\n");
	err |= builder_write("\n");
	return;
}

builder_write_getbyte_definition :: proc() -> (err: io.Error) {
	err |= builder_write("\n");
	err |= builder_write("static uint8_t getbyte(void) {\n");
	err |= builder_write("#if defined(_WIN32)\n");
	indent_level += 1;
	
	err |= builder_write("void *stdin_handle = GetStdHandle(STD_INPUT_HANDLE);\n");
	err |= builder_write("uint32_t bytes_read;\n");
	err |= builder_write("uint8_t byte;\n");
	err |= builder_write("bool success = ReadConsoleA(stdin_handle, &byte, 1, &bytes_read, 0) && bytes_read == 1;\n");
	err |= builder_write("if (!success) { byte = 0; }\n");
	
	indent_level -= 1;
	err |= builder_write("#else\n");
	err |= builder_write("# error Not implemented for this platform.\n");
	err |= builder_write("#endif\n");
	indent_level += 1;
	
	err |= builder_write("return byte;\n");
	
	indent_level -= 1;
	err |= builder_write("}\n");
	err |= builder_write("\n");
	return;
}

transpile_program_to_c :: proc(program: []u8, file_name: string) -> (success: bool) {
	success = false;
	
	// We need to first remove the file because O_CREATE does not always create the file, but only if it doesn't
	// exist already.
	remove_errno: os.Errno = 0;
	if os.exists(file_name) {
		remove_errno = os.remove(file_name);
	}
	if remove_errno == 0 {
		handle, open_errno := os.open(file_name, os.O_CREATE|os.O_WRONLY);
		if open_errno == 0 {
			success = true;
			
			stream := os.stream_from_handle(handle);
			bufio.writer_init_with_buf(&builder_writer, stream, builder_buffer[:]);
			
			builder_write("#include <stdbool.h>\n");
			builder_write("#include <stdint.h>\n");
			builder_write_platform_declarations();
			builder_write_getbyte_definition();
			builder_write_putbyte_definition();
			builder_write("static uint8_t memory[30000];\n");
			builder_write("int main(void) {\n");
			indent_level += 1;
			
			builder_write("int dp = 0;\n");
			
			/* How brainfuck commands translate to C:
	>	++ptr;
	<	--ptr;
	+	++(*ptr);
	-	--(*ptr);
	.	putchar(*ptr);
	,	*ptr = getchar();
	[	while (*ptr) {
	]	}
	*/
			
			depth := 0;
			program_loop: for instr, ip in program {
				switch instr {
					case '>': {
						builder_write("dp += 1;\n");
						builder_write("if (dp > sizeof(memory) - 1) { dp = 0; }\n");
					}
					
					case '<': {
						builder_write("dp -= 1;\n");
						builder_write("if (dp < 0) { dp = sizeof(memory) - 1; }\n");
					}
					
					case '+': {
						builder_write("memory[dp] += 1;\n");
					}
					
					case '-': {
						builder_write("memory[dp] -= 1;\n");
					}
					
					case '[': {
						builder_write("while (memory[dp]) {\n");
						indent_level += 1;
						
						depth += 1;
					}
					
					case ']': {
						indent_level -= 1;
						builder_write("}\n");
						
						depth -= 1;
						if depth < 0 {
							_ = fmt.eprintf("[%i] Syntax error: ']' has no corresponding '['\n", ip);
							success = false;
							break program_loop;
						}
					}
					
					case '.': {
						builder_write("putbyte(memory[dp]);\n");
					}
					
					case ',': {
						builder_write("memory[dp] = getbyte();\n");
					}
					
					case: ;;
				}
			}
			
			if depth == 0 {
				builder_write("return 0;\n");
				
				indent_level -= 1;
				builder_write("}\n");
				
				_ = bufio.writer_flush(&builder_writer);
			} else {
				_ = fmt.eprintf("Unbalanced stack.\n"); // @Improvement: Better error message.
				success = false;
			}
			
			os.close(handle);
		} else {
			_ = fmt.eprintf("The file '%s' could not be opened or read.\n", file_name);
		}
	} else {
		_ = fmt.eprintf("The file '%s' already exists and could not be overwritten.\n", file_name);
	}
	
	return;
}

builder_buffer: [1024]u8;
builder_writer: bufio.Writer;
