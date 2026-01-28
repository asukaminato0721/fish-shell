#RUN: %fish %s
#REQUIRES: command -v tmux
#REQUIRES: uname -r | grep -qv Microsoft
#REQUIRES: test -z "$CI"

# Start a clean tmux session running fish and create predictable completion sets.
# Disable autosuggestions to avoid races and keep captures stable.
isolated-tmux-start -C '
    set -g fish_autosuggestion_enabled 0
    rm -rf test_autoshow

    # Dataset for toggle-on/off behavior.
    mkdir -p test_autoshow/dirA test_autoshow/dirB
    for i in (seq 1 160)
        set n (printf "%03d" $i)
        touch test_autoshow/file$n
    end

    # Dataset for backspace/update behavior.
    # Typing ".../ap" should show ap*; backspacing to ".../a" should expand to include aonly*.
    mkdir -p test_autoshow/backspace
    touch test_autoshow/backspace/aonly001 test_autoshow/backspace/aonly002 test_autoshow/backspace/aonly003
    for i in (seq 1 40)
        set n (printf "%03d" $i)
        touch test_autoshow/backspace/ap$n
    end

    # Dataset for "stable filepaths while typing" and "completed directory token shows its contents".
    mkdir -p test_autoshow/stable
    touch test_autoshow/stable/test1.txt
    touch test_autoshow/stable/test2.txt
    touch test_autoshow/stable/test2.md
    for i in (seq 1 40)
        set n (printf "%03d" $i)
        touch test_autoshow/stable/test2suffix$n
    end


    # Dataset for "tab completion ambiguous list" behavior.
    mkdir -p test_autoshow/tab_ambig/collection
    touch test_autoshow/tab_ambig/collection-plan.docx


    # Dataset for "subcommand parser" behavior.
    # Use a completion generator that relies on command substitution.
    function autoshowcmd; end
    function __autoshowcmd_subcmds
        printf "add\ncommit\n"
        for i in (seq 1 40)
            printf "dummy_subcmd%03d\n" $i
        end
    end
    complete -c autoshowcmd -f -n "__fish_use_subcommand" -a "(__autoshowcmd_subcmds)"

    # Seed history so the blocklist-clearing test can take a history-fast path if applicable.
    # (We do not assert autosuggestion text; we only need this to make the codepath possible.)
    history append "blockedcmd test_autoshow/dirA/"
'

tmux-sleep
isolated-tmux send-keys C-l
tmux-sleep

# Helpers (run in the outer test process).
function __pane_tokens
    isolated-tmux capture-pane -p | tr -s " \t" "\n"
end

function __pane_has_token --argument token
    __pane_tokens | grep -Fqx -- $token
end

function __pane_print_token --argument token
    __pane_tokens | grep -Fx -- $token | head -1
end

function __pane_print_first_file
    __pane_tokens | grep -E '^file[0-9]{3}$' | head -1
end

# Test 1, Part 1: Enable autoshow and verify it renders completion candidates
isolated-tmux send-keys C-c
isolated-tmux send-keys 'set -g fish_autocomplete_autoshow 1' Enter
tmux-sleep
isolated-tmux send-keys C-l
tmux-sleep

isolated-tmux send-keys 'cat test_autoshow/'
tmux-sleep
sleep-until '__pane_has_token dirA/'

isolated-tmux capture-pane -p | grep -E '^prompt [0-9]+> cat test_autoshow/' | head -1
# CHECK: prompt {{\d+}}> cat test_autoshow/

__pane_print_token dirA/
# CHECK: dirA/
__pane_print_token dirB/
# CHECK: dirB/

__pane_print_first_file
# CHECK: file{{\d\d\d}}

# Test 1, Part 2: Disable autoshow and verify candidates do NOT appear (without CHECK-NOT)
isolated-tmux send-keys C-c
isolated-tmux send-keys 'set -g fish_autocomplete_autoshow 0' Enter
tmux-sleep
isolated-tmux send-keys C-l
tmux-sleep

isolated-tmux send-keys 'cat test_autoshow/'
tmux-sleep
sleep-until 'isolated-tmux capture-pane -p | grep -Fq "cat test_autoshow/"'

if __pane_has_token dirA/
    echo 'autoshow-off: FAIL (dirA present)'
else
    echo 'autoshow-off: OK'
end
# CHECK: autoshow-off: OK

# Test 1, Part 3: Re-enable autoshow and confirm it renders again
isolated-tmux send-keys C-c
isolated-tmux send-keys 'set -g fish_autocomplete_autoshow 1' Enter
tmux-sleep
isolated-tmux send-keys C-l
tmux-sleep

isolated-tmux send-keys 'cat test_autoshow/'
tmux-sleep
sleep-until '__pane_has_token dirB/'

isolated-tmux capture-pane -p | grep -E '^prompt [0-9]+> cat test_autoshow/' | head -1
# CHECK: prompt {{\d+}}> cat test_autoshow/

__pane_print_token dirA/
# CHECK: dirA/
__pane_print_token dirB/
# CHECK: dirB/

__pane_print_first_file
# CHECK: file{{\d\d\d}}

# Test 2: Backspacing during autoshow updates the shown candidates
# Start with a narrower prefix (ap) then backspace to a broader prefix (a) and
# verify the newly-eligible candidates (aonly*) appear
isolated-tmux send-keys C-c
isolated-tmux send-keys C-u
isolated-tmux send-keys C-l
tmux-sleep

isolated-tmux send-keys 'cat test_autoshow/backspace/ap'
tmux-sleep
sleep-until '__pane_has_token ap001'

__pane_print_token ap001
# CHECK: ap001

# Backspace deletes the 'p' -> now completing for ".../a"
isolated-tmux send-keys BSpace
tmux-sleep
sleep-until '__pane_has_token aonly001'

__pane_print_token aonly001
# CHECK: aonly001

# Test 3: Showing stable filepaths while typing (typed text + suggested suffix)
# The candidate must remain "test2.txt" as the user types more of the prefix.
isolated-tmux send-keys C-c
isolated-tmux send-keys C-u
isolated-tmux send-keys C-l
tmux-sleep

isolated-tmux send-keys 'cat test_autoshow/stable/'
tmux-sleep
sleep-until '__pane_has_token test2.txt'

isolated-tmux capture-pane -p | grep -E '^prompt [0-9]+> cat test_autoshow/stable/' | head -1
# CHECK: prompt {{\d+}}> cat test_autoshow/stable/

__pane_print_token test2.txt
# CHECK: test2.txt

# Type a prefix that still matches test2.txt.
isolated-tmux send-keys 'te'
tmux-sleep
sleep-until '__pane_has_token test2.txt'

isolated-tmux capture-pane -p | grep -E '^prompt [0-9]+> cat test_autoshow/stable/te' | head -1
# CHECK: prompt {{\d+}}> cat test_autoshow/stable/te

__pane_print_token test2.txt
# CHECK: test2.txt

# Type more characters; the displayed candidate should still be whole.
isolated-tmux send-keys 'st2'
tmux-sleep
sleep-until '__pane_has_token test2.txt'

isolated-tmux capture-pane -p | grep -E '^prompt [0-9]+> cat test_autoshow/stable/test2' | head -1
# CHECK: prompt {{\d+}}> cat test_autoshow/stable/test2

__pane_print_token test2.txt
# CHECK: test2.txt

# Test 4: Tab completion ambiguous list owns the pager (autoshow must not overwrite it)
isolated-tmux send-keys C-c
isolated-tmux send-keys C-u
isolated-tmux send-keys C-l
tmux-sleep

# Enter a directory where a directory and file share a prefix.
isolated-tmux send-keys 'cd test_autoshow/tab_ambig' Enter
tmux-sleep
isolated-tmux send-keys C-l
tmux-sleep

# Press Tab on an ambiguous prefix. Fish inserts the directory completion but keeps the full list visible.
isolated-tmux send-keys 'ls colle' Tab
tmux-sleep
sleep-until 'isolated-tmux capture-pane -p | grep -Eq "^prompt [0-9]+> ls collection/?"'
sleep-until '__pane_has_token collection/'
sleep-until '__pane_has_token collection-plan.docx'

isolated-tmux capture-pane -p | grep -E '^prompt [0-9]+> ls collection' | head -1
# CHECK: prompt {{\d+}}> ls collection

__pane_print_token collection/
# CHECK: collection/
__pane_print_token collection-plan.docx
# CHECK: collection-plan.docx

# Return to test root.
isolated-tmux send-keys C-c
isolated-tmux send-keys 'cd ../..' Enter
tmux-sleep


# Test 5 (Missing Test #8): Completing a directory token causes autoshow to list that directory's contents
isolated-tmux send-keys C-c
isolated-tmux send-keys C-u
isolated-tmux send-keys C-l
tmux-sleep

isolated-tmux send-keys 'cat test_autoshow/sta' Tab
tmux-sleep

sleep-until 'isolated-tmux capture-pane -p | grep -Fq "cat test_autoshow/stable/"'
sleep-until '__pane_has_token test1.txt'
sleep-until '__pane_has_token test2.txt'

isolated-tmux capture-pane -p | grep -E '^prompt [0-9]+> cat test_autoshow/stable/' | head -1
# CHECK: prompt {{\d+}}> cat test_autoshow/stable/

__pane_print_token test1.txt
# CHECK: test1.txt
__pane_print_token test2.txt
# CHECK: test2.txt
__pane_print_token test2.md
# CHECK: test2.md

# Test 6 (Missing Test #6): Autoshow parser for subcommands renders command-substitution subcommand completions
# The completion list for the subcommand position should include both literal and generated candidates.
isolated-tmux send-keys C-c
isolated-tmux send-keys C-u
isolated-tmux send-keys C-l
tmux-sleep

isolated-tmux send-keys 'autoshowcmd '
tmux-sleep
sleep-until '__pane_has_token add'
sleep-until '__pane_has_token commit'
sleep-until '__pane_has_token dummy_subcmd001'

# Wait until the commandline is visible in the captured pane.
sleep-until 'isolated-tmux capture-pane -p | grep -Eq "^prompt [0-9]+> autoshowcmd"'

isolated-tmux capture-pane -p | grep -E '^prompt [0-9]+> autoshowcmd' | head -1
# CHECK: prompt {{\d+}}> autoshowcmd{{.*}}

__pane_print_token add
# CHECK: add
__pane_print_token commit
# CHECK: commit
__pane_print_token dummy_subcmd001
# CHECK: dummy_subcmd001

# Test 7: Blocklist clears an already-visible autoshow pager (stale candidates must disappear)
#
# This is specifically meant to catch the case where autoshow stops producing updates (e.g. returns early
# via history) but the pager is not explicitly cleared and stale candidates remain on screen.
#
# Approach:
#  - Show autoshow candidates for a normal commandline ("cat test_autoshow/"), ensuring the pager is visible.
#  - With the same screen content (no C-l), edit ONLY the command token to a blocklisted command ("blockedcmd"),
#    keeping the rest of the line intact.
#  - Verify that a token that was visible only because of the pager (dirA/) is no longer present on the screen.
isolated-tmux send-keys C-c
isolated-tmux send-keys 'set -g fish_autoshow_blocklist blockedcmd' Enter
tmux-sleep
isolated-tmux send-keys C-u
isolated-tmux send-keys C-l
tmux-sleep

# First show autoshow candidates (pager visible).
isolated-tmux send-keys 'cat test_autoshow/'
tmux-sleep
sleep-until '__pane_has_token dirA/'

# Now, without clearing the screen, change "cat" -> "blockedcmd" in-place.
# We do this by deleting the three characters "cat" at the start, then inserting "blockedcmd".
isolated-tmux send-keys C-a DC DC DC blockedcmd
tmux-sleep

# Ensure the edited commandline is visible.
sleep-until 'isolated-tmux capture-pane -p | grep -Eq "^prompt [0-9]+> blockedcmd test_autoshow/"'

# If autoshow correctly clears on blocklist, the old pager tokens should disappear from the visible pane.
if __pane_has_token dirA/
    echo 'autoshow-blocklist-clears: FAIL (stale pager token present)'
else
    echo 'autoshow-blocklist-clears: OK'
end
# CHECK: autoshow-blocklist-clears: OK
