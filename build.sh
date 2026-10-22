if [ ! -d debug ]; then
	mkdir debug
fi
odin build src -debug -o:none -out:debug/bf_debug -vet -warnings-as-errors
