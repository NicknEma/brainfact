package brainfact

import "base:runtime"

import "core:io"
import "core:fmt"
import "core:bufio"

// @Cleanup: The only "errors" left to handle in this file are i/o errors (both for the compiler
// and the generated program).
// Understand if there's a standard way of handling/preventing/anticipating them,
// and if not put an explanatory comment.

@require_results
transpile_program_to_c :: proc(program: []u8, writer: bufio.Writer, backend: Backend, target: Target) -> (success: bool) {
	write_context_: Write_Context = { indent_spaces_per_level = 1, writer = writer };
	write_context := &write_context_;
	success = true;
	
	context.allocator = runtime.panic_allocator();
	context.temp_allocator = runtime.panic_allocator();
	
	_ = builder_write_platform_declarations(write_context, backend, target);
	_ = builder_write_getbyte_definition(write_context, backend, target);
	_ = builder_write_putbyte_definition(write_context, backend, target);
	
	_ = builder_write(write_context, "static uint8_t memory[30000];\n");
	_ = builder_write(write_context, "\n");
	_ = builder_write_entry_point(write_context, backend, target);
	write_context.indent_level += 1;
	
	_ = builder_write(write_context, "uint_fast16_t dp = 0;\n");
	
	/* How brainfuck commands translate to C:
	 * >    ++ptr;
	 * <    --ptr;
	 * +    ++(*ptr);
	 * -    --(*ptr);
	 * .    putchar(*ptr);
	 * ,    *ptr = getchar();
	 * [    while (*ptr) {
	 * ]    }
	 * */
	
	depth := 0;
	program_loop: for instr, ip in program {
		switch instr {
		case '>':
			_ = builder_write(write_context, "++dp; if (dp >= sizeof(memory)/sizeof(memory[0])) dp = 0;\n");
		case '<':
			_ = builder_write(write_context, "if (dp <= 0) dp = sizeof(memory)/sizeof(memory[0]); --dp;\n");
		case '+':
			_ = builder_write(write_context, "++memory[dp];\n");
		case '-':
			_ = builder_write(write_context, "--memory[dp];\n");
		
		case '[': {
			_ = builder_write(write_context, "while (memory[dp]) {\n");
			write_context.indent_level += 1;
			
			depth += 1;
		}
		case ']': {
			write_context.indent_level -= 1;
			_ = builder_write(write_context, "}\n");
			
			depth -= 1;
			if depth < 0 {
				fmt.eprintfln("[%i] Syntax error: ']' has no corresponding '['.", ip);
				success = false;
				break program_loop;
			}
		}
		
		case '.':
			_ = builder_write(write_context, "putbyte(memory[dp]);\n");
		case ',':
			_ = builder_write(write_context, "memory[dp] = getbyte();\n");
		
		case: ;;
		}
	}
	
	if depth == 0 {
		_ = builder_write(write_context, "return 0;\n");
		
		write_context.indent_level -= 1;
		_ = builder_write(write_context, "}\n");
		
		_ = bufio.writer_flush(&write_context.writer);
	} else if depth > 0 {
		fmt.eprintfln("[%i] Syntax error: '[' has no corresponding ']'.", len(program));
		success = false;
	} else {
		assert(!success);
	}
	
	return;
}

@require_results
builder_write_platform_declarations :: proc(write_context: ^Write_Context, backend: Backend, target: Target) -> (err: io.Error) {
	// We assume that, _if the supported targets are a subset of the targets that *this compiler* runs on_,
	// since those targets support exact-width types (as this compiler uses those types), then the
	// current target must also support exact-width types and so any standard C99 compiler
	// must provide a <stdint.h> header and said header must provide definitions for exact-width types.
	//
	// This saves us the hassle of having to statically check for the existence of <stdint.h> (and its contents)
	// through non-standard preprocessor extensions, or statically asserting that the size of 'unsigned char'
	// is what we expect, or replacing all '+= 1' with 'wrap_add()' or whatever, with the risk of
	// invoking undefined behaviour.
	//
	// Is this analysis overkill? Probabily. But I have trust issues so don't hit me with the usual "it's fine,
	// don't worry about it".
	//     - Ema, 22/10/2026
	err |= builder_write(write_context, "#include <stdint.h>\n");
	err |= builder_write(write_context, "\n");
	switch target {
	case .Windows: {
		err |= builder_write(write_context, "#define  STD_INPUT_HANDLE ((uint32_t)-10)\n");
		err |= builder_write(write_context, "#define STD_OUTPUT_HANDLE ((uint32_t)-11)\n");
		err |= builder_write(write_context, "__declspec(dllimport) void *__stdcall  GetStdHandle(uint32_t);\n");
		err |= builder_write(write_context, "__declspec(dllimport) int   __stdcall  ReadConsoleA(void *,       void *, uint32_t, uint32_t *, void *);\n");
		err |= builder_write(write_context, "__declspec(dllimport) int   __stdcall WriteConsoleA(void *, const void *, uint32_t, uint32_t *, void *);\n");
	}
	case .Linux: {
		err |= builder_write(write_context, "#define  STDIN_FILENO 0\n");
		err |= builder_write(write_context, "#define STDOUT_FILENO 1\n");
		err |= builder_write(write_context, "ssize_t  read(int,       void *, size_t);\n");
		err |= builder_write(write_context, "ssize_t write(int, const void *, size_t);\n");
	}
	case .None: panic("Invalid target");
	}
	err |= builder_write(write_context, "\n");
	return;
}

@require_results
builder_write_putbyte_definition :: proc(write_context: ^Write_Context, backend: Backend, target: Target) -> (err: io.Error) {
	err |= builder_write(write_context, "static int putbyte(uint8_t byte) {\n");
	write_context.indent_level += 1;
	
	switch target {
	case .Windows: {
		err |= builder_write(write_context, "void *stdout_handle = GetStdHandle(STD_OUTPUT_HANDLE);\n");
		err |= builder_write(write_context, "uint32_t bytes_written;\n");
		err |= builder_write(write_context, "int success = WriteConsoleA(stdout_handle, &byte, 1, &bytes_written, 0) && bytes_written == 1;\n");
	}
	case .Linux: {
		err |= builder_write(write_context, "int success = write(STDOUT_FILENO, &byte, 1) == 1;\n");
	}
	case .None: panic("Invalid target");
	}
	
	err |= builder_write(write_context, "return success;\n");
	
	write_context.indent_level -= 1;
	err |= builder_write(write_context, "}\n");
	err |= builder_write(write_context, "\n");
	return;
}

@require_results
builder_write_getbyte_definition :: proc(write_context: ^Write_Context, backend: Backend, target: Target) -> (err: io.Error) {
	err |= builder_write(write_context, "static uint8_t getbyte(void) {\n");
	write_context.indent_level += 1;
	
	switch target {
	case .Windows: {
		err |= builder_write(write_context, "void *stdin_handle = GetStdHandle(STD_INPUT_HANDLE);\n");
		err |= builder_write(write_context, "uint32_t bytes_read;\n");
		err |= builder_write(write_context, "uint8_t  byte;\n");
		err |= builder_write(write_context, "int success = ReadConsoleA(stdin_handle, &byte, 1, &bytes_read, 0) && bytes_read == 1;\n");
		err |= builder_write(write_context, "if (!success) byte = 0;\n");
	}
	case .Linux: {
		err |= builder_write(write_context, "uint8_t byte;\n");
		err |= builder_write(write_context, "int success = read(STDIN_FILENO, &byte, 1) == 1;\n");
		err |= builder_write(write_context, "if (!success) byte = 0;\n");
	}
	case .None: panic("Invalid target");
	}
	
	err |= builder_write(write_context, "return byte;\n");
	
	write_context.indent_level -= 1;
	err |= builder_write(write_context, "}\n");
	err |= builder_write(write_context, "\n");
	return;
}

@require_results
builder_write_entry_point :: proc(write_context: ^Write_Context, backend: Backend, target: Target) -> (err: io.Error) {
	switch target {
	case .Windows: {
		if backend == .Visual_Studio {
			_ = builder_write(write_context, "int mainCRTStartup(void) {\n");
		} else {
			_ = builder_write(write_context, "int main(void) {\n");
		}
	}
	case .Linux: {
		_ = builder_write(write_context, "int main(void) {\n");
	}
	case .None: panic("Invalid target");
	}
	return;
}

Write_Context :: struct {
	indent_spaces_per_level: int,
	indent_level: int,
	writer: bufio.Writer,
}

@require_results
builder_write :: proc(write_context: ^Write_Context, s: string) -> (err: io.Error) {
	for _ in 0..<write_context.indent_spaces_per_level * write_context.indent_level {
		err = bufio.writer_write_byte(&write_context.writer, '\t');
		if err != .None do break;
	}
	
	if err == .None {
		_, err = bufio.writer_write_string(&write_context.writer, s);
	}
	
	return;
}
