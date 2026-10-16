package brainfact

import "base:runtime"
import "base:intrinsics"

import "core:os"
import "core:fmt"
import "core:bufio"
import "core:strings"
import "core:path/filepath"

import "core:c/libc"

main :: proc() {
	mode, file, dest := parse_arguments();
	
	switch mode {
	case .Run: {
		if program, error := os.read_entire_file(file, context.temp_allocator); error == nil {
			reader_buffer: [    1]u8; // @Note: I don't understand why it gets all weird when we increase the size of this.
			writer_buffer: [ 1024]u8;
			target_memory: [30000]u8;
			
			target_reader: bufio.Reader;
			target_writer: bufio.Writer;
			
			bufio.reader_init_with_buf(&target_reader, os.to_stream(os.stdin ), reader_buffer[:]);
			bufio.writer_init_with_buf(&target_writer, os.to_stream(os.stdout), writer_buffer[:]);
			
			run_program(program, target_memory[:], target_reader, target_writer);
		} else {
			fmt.eprintfln("Could not open or read file '%s': %v.", file, error);
		}
	}
	
	case .Build: {
		if program, read_error := os.read_entire_file(file, context.temp_allocator); read_error == nil {
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
				when ODIN_DEBUG {
					_ = fmt.println(command_line);
				}
				libc.system(strings.unsafe_string_to_cstring(command_line));
				
				dest_obj, cat_error_obj := strings.concatenate({dest_no_extension, ".obj"}, context.temp_allocator);
				remove_errno := os.remove(dest_obj);
				_, _ = remove_errno, cat_error_obj;
				// @Todo: Error checking
			}
		} else {
			_ = fmt.eprintfln("Could not open or read file '%s': %v.", file, read_error);
		}
	}
	
	case .Print_Help: {
		_ = fmt.println(HELP_TEXT);
	}
	}
	
	parse_arguments :: proc() -> (mode: Mode, file, dest: string) {
		mode = Mode.Run;
		file = "";
		dest = "";
		
		// Any argument starting in '-' is considered a flag. Everything else is viewed as a path,
		// either source or destination.
		// The '-help' option will ignore everything else, while unrecognized build options will
		// just be ignored. Only one source file and one destination file are allowed. Any
		// extra files will be ignored.
		if len(os.args) > 1 {
			#no_bounds_check parse_loop: for arg_index in 1..<len(os.args) {
				arg := os.args[arg_index];
				
				if      arg    == "-help"   { mode = .Print_Help; break; }
				else if arg    == "-build" do mode = .Build;
				else if arg[0] == '-'      do _ = fmt.eprintfln("The option '%s' was not recognized and will be ignored.", arg);
				else if file   == ""       do file = arg;
				else if dest   == ""       do dest = arg;
				else                       do _ = fmt.eprintfln("The file '%s' will be ignored because both the source ('%s') and the destination ('%s') were already supplied.", arg, file, dest);
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
	-build	Compiles the input file down to an executable instead of interpreting it.
	-help	Displays this text.

Examples:
	bf  in.bf                	Runs 'in.bf'.
	bf  in.bf -build out.exe 	Builds 'in.bf' as 'out.bf'.
	bf  -help                	Displays this text.`;
