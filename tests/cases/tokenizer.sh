# shellcheck shell=bash
# __split_argv, tested against real Bash.
#
# This function decides what actually gets executed, so the authority is Bash's
# own word-splitting rather than whatever I assumed. Each case runs the same
# line both ways and requires identical words in identical order.

# --- tokenizer -----------------------------------------------------------
#
# __split_argv decides what actually gets executed, so it is tested against
# real Bash rather than against my expectations. Each case runs the same line
# through Bash's own word-splitting and through Igitari, and requires the same
# words in the same order.
#
# A stub execute_command stands in for the dispatcher so $(...) can be tested
# without touching a repository.

# Run a line through real Bash and print one word per line.
bash_words() {
    local line="$1"
    ( eval "set -- $line"; printf '%s\n' "$@" )
}

# Run a line through __split_argv and print one word per line.
ignore_words() {
    local line="$1"
    local -a out=()
    __split_argv "$line" out
    local w
    for w in "${out[@]}"; do printf '%s\n' "$w"; done
}

assert_same_words() {
    local line="$1" expected="$2" what="$3"
    local got
    got=$(ignore_words "$line" | tr '\n' '|')
    assert_eq "$got" "$expected" "$what"
}

t_split_argv_quoting() {
    local d='$'
    # The dispatcher must answer substitutions without any git side effects.
    execute_command() { printf 'VALUE'; }

    # Plain words.
    assert_same_words "a b c" "a|b|c|" "three words"
    # Double quotes keep a space-containing word whole.
    assert_same_words '"two words.txt"' "two words.txt|" "double-quoted space"
    # Single quotes are literal: no substitution inside them.
    # Built with a variable so the test source itself never expands $(x).
    local d='$'
    assert_same_words "'literal ${d}(x)'" "literal ${d}(x)|" "single quotes are literal"
    # A quoted substitution stays one word, and does not split on its output.
    assert_same_words "\"${d}(x)\"" "VALUE|" "quoted substitution"
    # An unquoted substitution is trimmed of trailing newlines but kept whole
    # here, because the stub returns no whitespace.
    assert_same_words "${d}(x)" "VALUE|" "bare substitution"
    # Adjacent quoting joins into one word.
    assert_same_words 'a"b c"d' "ab cd|" "adjacent quoted join"
}

# An unquoted substitution splits on whitespace, a quoted one does not. This
# is the rule that lets 'untrack $(fzf tracked)' pass several paths at once
# while 'reword "$(fzf message)"' keeps a sentence as one argument.
t_split_argv_substitution_splitting() {
    local d='$'
    execute_command() { printf 'one two three'; }

    local -a unquoted=() quoted=()
    __split_argv "${d}(x)" unquoted
    __split_argv "\"${d}(x)\"" quoted

    assert_eq "${#unquoted[@]}" "3" "unquoted substitution splits"
    assert_eq "${unquoted[0]}" "one" "first piece"
    assert_eq "${unquoted[2]}" "three" "third piece"
    assert_eq "${#quoted[@]}" "1" "quoted substitution stays whole"
    assert_eq "${quoted[0]}" "one two three" "quoted content"
}

# A substitution in the middle of a word glues to its neighbours.
t_split_argv_substitution_glues() {
    local d='$'
    execute_command() { printf 'MID'; }
    local -a out=()
    __split_argv "a${d}(x)b" out
    assert_eq "${#out[@]}" "1" "glued substitution is one word"
    assert_eq "${out[0]}" "aMIDb" "glued content"
}

t_split_argv_leaves_no_quotes() {
    execute_command() { printf 'VALUE'; }
    local -a out=()
    __split_argv '"keep me" plain' out
    assert_eq "${#out[@]}" "2" "word count"
    assert_eq "${out[0]}" "keep me" "quotes are removed"
    assert_eq "${out[1]}" "plain" "second word"
}
