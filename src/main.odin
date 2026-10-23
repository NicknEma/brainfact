package brainfact

import "core:os"
import "core:fmt"
import "core:bufio"
import "core:strings"
import "core:path/filepath"

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
			fmt.eprintfln("Could not open or read file '%s': %v.", file, os_error_string(error));
		}
	}
	
	case .Build: {
		// Select backend and target.
		supported_backends: bit_set[Backend];
		supported_targets:  bit_set[Target];
		
		when ODIN_OS == .Windows {
			DEFAULT_BACKEND :: Backend.Visual_Studio;
			DEFAULT_TARGET  :: Target.Windows;
			
			supported_backends += { .Visual_Studio, .Clang };
			supported_targets  += { .Windows };
		} else when ODIN_OS == .Linux {
			DEFAULT_BACKEND :: Backend.Clang;
			DEFAULT_TARGET  :: Target.Linux;
			
			supported_backends += { .Clang };
			supported_targets  += { .Linux };
		} else {
			DEFAULT_BACKEND :: Backend.None;
			DEFAULT_TARGET  :: Target.None;
		}
		
		assert(DEFAULT_BACKEND == .None || DEFAULT_BACKEND in supported_backends);
		assert(DEFAULT_TARGET  == .None || DEFAULT_TARGET  in supported_targets);
		
		backend := DEFAULT_BACKEND;
		target  := DEFAULT_TARGET;
		
		// If in the future we want the ability to override the chosen backend and/or target
		// with a command line flag, we could do it here.
		// If the backend changes, the list of supported targets changes too.
		
		if backend not_in supported_backends {
			// @Todo: Error: backend is not supported by this version of the compiler. Supported backends are ..
			break;
		}
		
		if target not_in supported_targets {
			// @Todo: Error: target is not supported by this version of the compiler and this backend. Supported targets for the selected backend are ..
			break;
		}
		
		program, read_error := os.read_entire_file(file, context.temp_allocator);
		if read_error != nil {
			fmt.eprintfln("Could not open or read file '%s': %v.", file, os_error_string(read_error));
			break;
		}
		
		// @Temp: renaming
		source_file := file;
		
		// Try to match Visual Studio's behaviour, which seems to be:
		// - If an output path is supplied:
		//   - Trim any trailing '.' from it
		//   - If it doesn't contain any '.', append '.exe' to it
		// - Else
		//   - Trim the short extension from the source
		//   - Append '.exe' to it (it doesn't matter if it already ends in '.exe')
		//
		// In our case, we treat the source path as always containing brainfuck code.
		// We trim the short extension if it has one, it doesn't matter
		// which one it is.
		
		source_file_stem := filepath.stem(source_file);
		
		// Define useful file paths.
		// @Todo: error check
		// @Todo: factor these branches
		temp_c_file, temp_o_file, target_file: string;
		temp_o_file, _ = strings.concatenate({source_file_stem, ".obj"}, context.temp_allocator); // @Todo: choose this based on the backend (.obj, .o), or pass it to the backend
		if dest != "" {
			target_file = strings.trim_right(dest, ".");
			if !strings.contains(target_file, ".") {
				temp_c_file, _ = strings.concatenate({dest, ".c"}, context.temp_allocator);
				target_file, _ = strings.concatenate({dest, ".exe"}, context.temp_allocator); // @Todo: same as below
			} else {
				temp_c_file, _ = strings.concatenate({target_file, ".c"}, context.temp_allocator);
			}
		} else {
			temp_c_file, _ = strings.concatenate({source_file_stem, ".c"}, context.temp_allocator);
			target_file, _ = strings.concatenate({source_file_stem, ".exe"}, context.temp_allocator); // @Todo: this or nothing depending on the target?
		}
		
		// Transpile to C.
		transpile_success: bool;
		handle, open_error := os.open(temp_c_file, {.Write, .Create, .Trunc});
		if open_error == nil {
			target_buffer: [1024]u8;
			target_writer: bufio.Writer;
			
			bufio.writer_init_with_buf(&target_writer, os.to_stream(handle), target_buffer[:]);
			
			transpile_success = transpile_program_to_c(program, target_writer, backend, target);
			os.close(handle);
		} else {
			fmt.eprintfln("Could not open or create file '%s': %v.", temp_c_file, os_error_string(open_error));
		}
		
		// Invoke the backend.
		if transpile_success {
			process_desc: os.Process_Desc;
			
			switch backend {
			case .Visual_Studio: {
				target_flag := strings.concatenate({ "/Fe", target_file }, context.temp_allocator) or_else "";
				process_desc.command = { "cl", temp_c_file, target_flag, "/nologo", "/W4", "/WX", "/O1", "/MT", "/TC", "/link", "/incremental:no", "/opt:ref", "/entry:mainCRTStartup", "/subsystem:console", "kernel32.lib"};
			}
			case .Clang: {
				process_desc.command = { "clang", temp_c_file, "-o", target_file, "-Wall", "-Wextra", "-pedantic", "-O1"};
			}
			case .None: panic("Invalid backend");
			}
			
			process_state, stdout_capture, stderr_capture, exec_error := os.process_exec(process_desc, context.temp_allocator);
			if exec_error == nil {
				assert(process_state.exited);
				if process_state.exit_code != 0 {
					if stdout_capture != nil {
						fmt.eprintln(transmute(string)stdout_capture);
					}
					if stderr_capture != nil {
						fmt.eprintln(transmute(string)stderr_capture);
					}
					fmt.eprintfln("Internal error: backend did not succeed, C generation was wrong.");
				}
			} else {
				fmt.eprintfln("Could not invoke backend: %v", os_error_string(exec_error));
			}
			
			_ = os.remove(temp_o_file); // @Todo: Should we print a message on failure? If it doesn't exist, maybe try to find other matches?
		}
		
		if open_error == nil {
			// @Todo: Remove C by default, -keep-c flag
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
				else if arg[0] == '-'      do fmt.eprintfln("The option '%s' was not recognized and will be ignored.", arg);
				else if file   == ""       do file = arg;
				else if dest   == ""       do dest = arg;
				else                       do fmt.eprintfln("The file '%s' will be ignored because both the source ('%s') and the destination ('%s') were already supplied.", arg, file, dest);
			}
		} else {
			mode = .Print_Help;
		}
		
		return;
	}
	
	Mode :: enum { Run, Build, Print_Help };
}

os_error_string :: proc(err: os.Error) -> string {
	str: string = ---
	if _, ok := os.is_platform_error(err); ok {
		str = "unknown error"
	} else {
		str = os.error_string(err)
	}
	return str
}

Backend :: enum { None, Visual_Studio, Clang };
Target  :: enum { None, Windows, Linux };

HELP_TEXT :: `Usage: bf <file> [-build <dest>] [-help]

Options:
	-build	Compiles the input file down to an executable instead of interpreting it.
	-help	Displays this text.

Examples:
	bf  in.bf                	Runs 'in.bf'.
	bf  in.bf -build out.exe 	Builds 'in.bf' as 'out.bf'.
	bf  -help                	Displays this text.`;
