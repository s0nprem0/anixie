setopt autocd              # change directory just by typing its name
setopt extendedglob        # extended globbing. Allows regular expressions with *
setopt interactivecomments # allow comments in interactive mode
setopt magicequalsubst     # filename expansion for args of the form =expression
setopt nonomatch           # hide error message if there is no match for the pattern
setopt notify              # report the status of background jobs immediately
setopt numericglobsort     # sort filenames numerically when it makes sense
setopt promptsubst         # enable command substitution in prompt
setopt no_beep             # never beep on errors

WORDCHARS=${WORDCHARS//\/}

# Show a visible mark when a program's output is missing its trailing
# newline (empty string used to hide it, merging output into the prompt)
PROMPT_EOL_MARK='%{%F{yellow}%}⏎%{%f%}'

export KEYTIMEOUT=1