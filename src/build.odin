package brainfact;

import "core:io";
import "core:os";
import "core:fmt";
import "core:bufio";

import "core:strings";
import slices "core:slice";

import "core:runtime";
import "core:intrinsics";

_ :: io;
_ :: os;
_ :: fmt;
_ :: bufio;

_ :: slices;
_ :: strings;

_ :: runtime;
_ :: intrinsics;

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

compile_program_as_c :: proc(program: []u8, file_name: string) -> (success: bool) {
	success = false;
	
	c_file_name, c_cat_error := strings.concatenate({file_name, ".c"}, context.temp_allocator);
	_ = c_cat_error; // @Todo: Check error.
	
	handle, open_errno := os.open(c_file_name, os.O_CREATE|os.O_WRONLY);
	if open_errno == 0 {
		success = true;
		
		stream := os.stream_from_handle(handle);
		bufio.writer_init_with_buf(&builder_writer, stream, builder_buffer[:]);
		
		builder_write("#include <stdint.h>\n");
		builder_write("#include <stdio.h>\n");
		builder_write("static uint8_t memory[30000];\n");
		builder_write("int main(void) {\n");
		indent_level += 1;
		
		builder_write("int dp = 0;\n");
		
		/*
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
						fmt.eprintf("[%i] Syntax error: ']' has no corresponding '['\n", ip);
						success = false;
						break program_loop;
					}
				}
				
				// @Incomplete: Error checking for io errors?
				case '.': {
					builder_write("putchar((int)memory[dp]);\n");
				}
				
				case ',': {
					builder_write("memory[dp] = (uint8_t)getchar();\n");
				}
				
				case: ;;
			}
		}
		
		if depth == 0 {
			builder_write("return 0;\n");
			
			indent_level -= 1;
			builder_write("}\n");
			
			bufio.writer_flush(&builder_writer);
		} else {
			fmt.eprintf("Unbalanced stack.\n"); // @Todo: Better error message.
			success = false;
		}
		
		os.close(handle);
		
		if success {
			exe_file_name, exe_cat_error := strings.concatenate({file_name, ".exe"}, context.temp_allocator);
			// @Todo: Error checking
			
			command_line := fmt.aprintf("cl %s /Fe%s /nologo /W4 /WX /O2 /MT /TC /link /incremental:no /opt:ref /WX%c", c_file_name, exe_file_name, rune(0));
			libc.system(strings.unsafe_string_to_cstring(command_line));
			
			obj_file_name, obj_cat_error := strings.concatenate({file_name, ".obj"}, context.temp_allocator);
			errno := os.remove(obj_file_name);
			// @Todo: Error checking
		}
	} else {
		fmt.eprintf("The file '%s' could not be opened or read.\n", file_name);
	}
	
	free_err := runtime.free_all(context.temp_allocator);
	_ = free_err; // @Todo: Error checking
	
	return;
}

builder_buffer: [1024]u8;
builder_writer: bufio.Writer;

import "core:c/libc";
