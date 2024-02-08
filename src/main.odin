package brainfact;

import "core:io";
import "core:os";
import "core:fmt";
import "core:bufio";

import "core:strings";
import "core:path/filepath";
import slices "core:slice";

import "core:c/libc";
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

program_memory: [30000]u8;

program_reader: bufio.Reader;
program_writer: bufio.Writer;

reader_buffer: [   1]u8; // @Note: I don't understand why it gets all weird when we increase the size of this.
writer_buffer: [1024]u8;

// Usage:
// bf.exe <file> [-build]

main :: proc() {
	mode, file, dest := parse_arguments();
	
	switch mode {
		case .Run: {
			program_string, read_success := os.read_entire_file(file);
			if read_success {
				
				stdin_stream  := os.stream_from_handle(os.stdin);
				stdout_stream := os.stream_from_handle(os.stdout);
				
				bufio.reader_init_with_buf(&program_reader, stdin_stream,  reader_buffer[:]);
				bufio.writer_init_with_buf(&program_writer, stdout_stream, writer_buffer[:]);
				
				program := transmute([]u8)program_string;
				
				run_program(program, program_memory[:]);
			} else {
				fmt.eprintf("The file '%s' could not be opened or read.\n", file);
			}
		}
		
		case .Build: {
			program_string, read_success := os.read_entire_file(file);
			if read_success {
				program := transmute([]u8)program_string;
				
				dest_no_extension: string;
				if dest == "" {
					dest = filepath.stem(file);
					dest_no_extension = dest;
					cat_error_exe: runtime.Allocator_Error;
					dest, cat_error_exe = strings.concatenate({dest, ".exe"});
					// @Todo: Error checking
				} else {
					dest_no_extension = filepath.stem(dest);
				}
				
				dest_c, cat_error_c := strings.concatenate({dest_no_extension, ".c"}, context.temp_allocator);
				_ = cat_error_c; // @Todo: Check error.
				
				transpile_success := transpile_program_to_c(program, dest_c);
				
				if transpile_success {
					// @Todo: Error checking
					command_line := fmt.aprintf("cl %s /Fe%s /nologo /W4 /WX /O2 /MT /TC /link /incremental:no /opt:ref /WX%c", dest_c, dest, rune(0));
					logln(command_line);
					libc.system(strings.unsafe_string_to_cstring(command_line));
					
					dest_obj, cat_error_obj := strings.concatenate({dest_no_extension, ".obj"}, context.temp_allocator);
					remove_errno := os.remove(dest_obj);
					// @Todo: Error checking
				}
			} else {
				fmt.eprintf("The file '%s' could not be opened or read.\n", file);
			}
		}
		
		case .Print_Help: {
			fmt.println(HELP_TEXT);
		}
	}
	
	parse_arguments :: proc() -> (mode: Mode, file, dest: string) {
		mode = Mode.Run;
		file = "";
		dest = "";
		
		// Any argument starting in '-' is considered as an option. Everything else is viewed as a path, either
		// source or destination.
		// The '-help' option will ignore everything else, while unrecognized build options will just be ignored.
		// Only one source file and one destination file are allowed. Any extra files will be ignored.
		if len(os.args) > 1 {
			#no_bounds_check parse_loop: for arg_index in 1..<len(os.args) {
				arg := os.args[arg_index];
				
				if      arg    == "-help"   { mode = .Print_Help; break; }
				else if arg    == "-build" do mode = .Build;
				else if arg[0] == '-'      do fmt.eprintf("The option '%s' was not recognized and will be ignored.\n", arg);
				else if file   == ""       do file = arg;
				else if dest   == ""       do dest = arg;
				else                       do fmt.eprintf("The file '%s' will be ignored because both the source ('%s') and the destination ('%s') were already supplied.\n", arg, file, dest);
			}
		} else {
			mode = .Print_Help;
		}
		
		return;
	}
	
	Mode :: enum { Run, Build, Print_Help };
}

HELP_TEXT :: `Usage: bf <file> [-build <dest>] [-help]

Options:
-build   Compiles the input file down to an executable instead of interpreting it.
-help    Displays this text.`;

logln :: proc(args: ..any) {
	when ODIN_DEBUG {
		fmt.println(..args);
	} else { _ = args; }
}
