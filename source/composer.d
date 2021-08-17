module composer;

import std.stdio;
import std.utf;
import std.regex;
import std.algorithm;
import std.conv;
import std.file;
import std.path;
import std.array;
import std.format;

import std.datetime.stopwatch;

import reneo;


class ComposeParser {
    string line;
    uint pos;
    int chunkStart = -1;

    this(string line) {
        this.line = line;
    }

    char peek() {
        return line[pos];
    }

    void advance() {
        pos++;
    }

    bool match(char[] cs ...) {
        foreach (char c; cs) {
            if (check(c)) {
                advance();
                return true;
            }
        }

        return false;
    }

    bool check(char c) {
        if(atEnd()) {
            return false;
        }
        return peek() == c;
    }

    bool atEnd() {
        return pos >= line.length;
    }

    void consumeWhitespace() {
        while (match(' ', '\t')) {}
    }

    void startChunk() {
        assert(chunkStart == -1);
        chunkStart = pos;
    }

    string endChunk() {
        assert(chunkStart != -1);
        string chunk = line[chunkStart .. pos];
        chunkStart = -1;
        return chunk;
    }

    uint composeSequenceKey() {
        /// parse "<Multi_Key>" into a matching keysym
        assert(match('<'));
        startChunk();
        while (!check('>')) {
            advance();
        }
        string keysym_str = endChunk();
        match('>');
        return parseKeysym(keysym_str);
    }

    string quotedString() {
        assert(match('"'));
        
        string stringContent;

        while (!check('"')) {
            char next = peek();

            if (next == '\\') {
                // For backslash escaped characters, skip the backslash and decide based on the next char
                advance();

                if (check('n')) {
                    stringContent ~= '\n';
                } else if (check('t')) {
                    stringContent ~= '\t';
                } else {
                    stringContent ~= peek();
                }
            } else {
                stringContent ~= next;
            }

            advance();
        }

        match('"');
        return stringContent;
    }

    ComposeFileLine composeEntry() {
        ComposeFileLine entry; // remains empty if line is empty

        consumeWhitespace();
        if (!check('<')) {
            // early return on empty/comment lines
            return entry;
        }

        while (check('<')) {
            entry.keysyms ~= composeSequenceKey();
            consumeWhitespace();
        }

        assert(match(':'));
        consumeWhitespace();
        string resultString = quotedString();
        entry.result = resultString.to!wstring;

        return entry;
    }
}

struct ComposeNode {
    uint keysym;
    ComposeNode *prev;
    ComposeNode *[] next;
    wstring result;
    // Everything after this node is processed by the special mode function
    SpecialComposeFunction specialMode;
}

// Function signature for special compose functions, e.g. for Unicode input
alias SpecialComposeFunction = ComposeResult function(NeoKey) nothrow;

ComposeNode composeRoot;
ComposeNode removeComposeRoot;

bool active;
ComposeNode *currentNode;
dstring currentSequence;
// Function pointer if currently switched to special compose mode
SpecialComposeFunction currentSpecialMode;
uint addedEntries;

// Keysym constants for Unicode input
uint KEYSYM_0;
uint KEYSYM_KP_0;
uint KEYSYM_a;
uint KEYSYM_A;
uint KEYSYM_SPACE;

// Unicode input special mode
string unicodeInput;

// Roman numeral special mode
const ROMAN_DIGITS = [
    [["ⅰ"w, "Ⅰ"w], ["ⅰⅰ"w, "ⅠⅠ"w], ["ⅰⅰⅰ"w, "ⅠⅠⅠ"w], ["ⅰⅴ"w, "ⅠⅤ"w], ["ⅴ"w, "Ⅴ"w], ["ⅴⅰ"w, "ⅤⅠ"w], ["ⅴⅰⅰ"w, "ⅤⅠⅠ"w], ["ⅴⅰⅰⅰ"w, "ⅤⅠⅠⅠ"w], ["ⅰⅹ"w, "ⅠⅩ"w]],
    [["ⅹ"w, "Ⅹ"w], ["ⅹⅹ"w, "ⅩⅩ"w], ["ⅹⅹⅹ"w, "ⅩⅩⅩ"w], ["ⅹⅼ"w, "ⅩⅬ"w], ["ⅼ"w, "Ⅼ"w], ["ⅼⅹ"w, "ⅬⅩ"w], ["ⅼⅹⅹ"w, "ⅬⅩⅩ"w], ["ⅼⅹⅹⅹ"w, "ⅬⅩⅩⅩ"w], ["ⅹⅽ"w, "ⅩⅭ"w]],
    [["ⅽ"w, "Ⅽ"w], ["ⅽⅽ"w, "ⅭⅭ"w], ["ⅽⅽⅽ"w, "ⅭⅭⅭ"w], ["ⅽⅾ"w, "ⅭⅮ"w], ["ⅾ"w, "Ⅾ"w], ["ⅾⅽ"w, "ⅮⅭ"w], ["ⅾⅽⅽ"w, "ⅮⅭⅭ"w], ["ⅾⅽⅽⅽ"w, "ⅮⅭⅭⅭ"w], ["ⅽⅿ"w, "ⅭⅯ"w]],
    [["ⅿ"w, "Ⅿ"w], ["ⅿⅿ"w, "ⅯⅯ"w], ["ⅿⅿⅿ"w, "ⅯⅯⅯ"w]]
];
string romanNumeralInput;

enum ComposeResultType {
    PASS,
    EAT,
    FINISH,
    ABORT
}

struct ComposeResult {
    ComposeResultType type;
    wstring result;
}

struct ComposeFileLine {
    /** 
    * One line in a compose file, consisting of the required keysyms and the resulting string
    * This is only used while parsing, the actual compose data structure is a tree (see ComposeNode)
    **/
    uint [] keysyms;
    wstring result;
    // Minor abuse of this type, as actual .module files can't specify special modes
    SpecialComposeFunction specialMode;
}


void initCompose(string exeDir) {
    debug_writeln("Initializing compose");

    debug {
        auto sw = StopWatch();
        sw.start();
    }
    // reset existing compose tree
    composeRoot = ComposeNode();
    string composeDir = buildPath(exeDir, "compose");

    if (!exists(composeDir)) {
        return;
    }

    // Gather all entries that appear in .remove files
    foreach (dirEntry; dirEntries(composeDir, "*.remove", SpanMode.shallow)) {
        if (dirEntry.isFile) {
            string fname = dirEntry.name;
            debug_writeln("Removing compose module ", fname);
            loadRemoveModule(fname);
        }
    }

    // Gather compose entries from all .module files
    foreach (dirEntry; dirEntries(composeDir, "*.module", SpanMode.shallow)) {
        if (dirEntry.isFile) {
            string fname = dirEntry.name;
            debug_writeln("Loading compose module ", fname);
            loadModule(fname);
        }
    }

    debug {
        debug_writeln("Time spent reading and parsing module files: ", sw.peek().total!"msecs", " ms");
        sw.reset();
    }

    debug_writeln("Loaded ", addedEntries, " compose sequences.");

    // Register unicode input special mode with prefix "♫uu"
    addComposeEntry(ComposeFileLine([parseKeysym("Multi_key"), parseKeysym("u"), parseKeysym("u")], ""w, &composeUnicode), composeRoot);

    // Register lower case roman numeral special mode with prefix "♫rn"
    addComposeEntry(ComposeFileLine([parseKeysym("Multi_key"), parseKeysym("r"), parseKeysym("n")], ""w, &composeLowerRoman), composeRoot);
    
    // Register upper case roman numeral special mode with prefix "♫RN"
    addComposeEntry(ComposeFileLine([parseKeysym("Multi_key"), parseKeysym("R"), parseKeysym("N")], ""w, &composeUpperRoman), composeRoot);

    // For unicode input
    KEYSYM_SPACE = parseKeysym("space");
    KEYSYM_0 = parseKeysym("0");
    KEYSYM_KP_0 = parseKeysym("KP_0");
    KEYSYM_a = parseKeysym("a");
    KEYSYM_A = parseKeysym("A");
}

ComposeFileLine parseLine(string line) {
    /// Parse compose module line into an entry struct
    /// Throws if the line can't be parsed (e.g. it's empty or a comment)
    auto parser = new ComposeParser(line);
    auto entry = parser.composeEntry();
    if (entry.result == ""w) {
        throw new Exception("Line does not contain compose entry");
    }

    return entry;
}

bool isEntryInComposeTree(ComposeFileLine entry, ref ComposeNode nodeRoot) {
    auto currentNode = &nodeRoot;

    foreach (keysym; entry.keysyms) {
        ComposeNode *next;
        bool foundNext;

        foreach (nextIter; currentNode.next) {
            if (nextIter.keysym == keysym) {
                foundNext = true;
                next = nextIter;
                break;
            }
        }
        if (!foundNext) break;
        currentNode = next;
    }

    return (currentNode.result == entry.result);
}

void addComposeEntry(ComposeFileLine entry, ref ComposeNode nodeRoot) {
    auto currentNode = &nodeRoot;

    foreach (keysym; entry.keysyms) {
        ComposeNode *next;
        bool foundNext;

        foreach (nextIter; currentNode.next) {
            if (nextIter.keysym == keysym) {
                foundNext = true;
                next = nextIter;
                break;
            }
        }

        if (!foundNext) {
            if (currentNode.result != ""w || currentNode.specialMode) {
                // We are creating a compose sequence that is a continuation of an existing one
                debug_writeln("Conflict in compose sequence ", entry.keysyms.map!(k => format("0x%X", k)).join("->"));
                return;
            }

            next = new ComposeNode(keysym, currentNode, [], ""w, null);
            currentNode.next ~= next;
        }

        currentNode = next;
    }

    if (currentNode.next.length > 0) {
        // This sequence is a premature end for an already existing one and will be skipped
        debug_writeln("Conflict in compose sequence ", entry.keysyms.map!(k => format("0x%X", k)).join("->"));
        return;
    } 
    currentNode.result = entry.result;
    currentNode.specialMode = entry.specialMode;
}

void loadModule(string fname) {
    /// Load a module file and add all entries, if they are not in the remove-tree
    string content = cast(string) std.file.read(fname);
    string[] lines = split(content, "\n");
    foreach(l; lines) {
        try {
            auto entry = parseLine(l);
            if (!isEntryInComposeTree(entry, removeComposeRoot)) {
                addComposeEntry(entry, composeRoot);
                addedEntries += 1;
            }
        } catch (Exception e) {
            // Do nothing, most likely because the line just was a comment
        }
    }
}

void loadRemoveModule(string fname) {
    /// Load a module file and add all entries to the remove-tree
    string content = cast(string) std.file.read(fname);
    string[] lines = split(content, "\n");
    foreach(l; lines) {
        try {
            auto entry = parseLine(l);
            addComposeEntry(entry, removeComposeRoot);
        } catch (Exception e) {
            // Do nothing, most likely because the line just was a comment
        }
    }
}

ComposeResult compose(NeoKey nk) nothrow {
    if (!active) {
        foreach (startNode; composeRoot.next) {
            if (startNode.keysym == nk.keysym) {
                active = true;
                // Clear compose sequence at the beginning
                currentSequence = "";
                currentNode = &composeRoot;
                break;
            }
        }

        if (!active) {
            return ComposeResult(ComposeResultType.PASS, ""w);
        } else {
            debug_writeln("Starting compose sequence");
        }
    }

    if (active) {
        if (currentSpecialMode) {
            auto specialResult = currentSpecialMode(nk);
            if (specialResult.type == ComposeResultType.ABORT || specialResult.type == ComposeResultType.FINISH) {
                // Special mode has finished, reset compose to normal state
                active = false;
                currentSpecialMode = null;
                debug_writeln("Special compose sequence finished");
            }
            return specialResult;
        } else {
            ComposeNode *next;
            bool foundNext;

            // Add keysym to compose sequence, if it has a Unicode representation
            dchar sequenceChar = 0;
            if (nk.keysym in codepoints_by_keysym) {
                sequenceChar = dchar(codepoints_by_keysym[nk.keysym]);
            } else if (nk.keysym > KEYSYM_CODEPOINT_OFFSET) {
                sequenceChar = dchar(nk.keysym - KEYSYM_CODEPOINT_OFFSET);
            } else if (nk.keytype == NeoKeyType.CHAR) {
                sequenceChar = nk.char_code;
            }
            if (sequenceChar) {
                debug_writeln("Added char to compose abort sequence: ", sequenceChar);
                currentSequence ~= sequenceChar;
            }

            foreach (nextIter; currentNode.next) {
                if (nextIter.keysym == nk.keysym) {
                    foundNext = true;
                    next = nextIter;
                    break;
                }
            }

            if (foundNext) {
                if (next.next.length == 0) {
                    // this was the final key
                    if (next.specialMode) {
                        // user entered the leader sequence for a special mode
                        // the following key presses will be handled by the associated special mode function
                        debug_writeln("Starting special compose sequence");
                        currentSpecialMode = next.specialMode;
                        return ComposeResult(ComposeResultType.EAT, ""w);
                    } else {
                        // normal compose sequence end
                        active = false;
                        debug_writeln("Compose finished");
                        return ComposeResult(ComposeResultType.FINISH, next.result);
                    }
                } else {
                    currentNode = next;
                    try {
                        debug_writeln("Next: ", currentNode.next.map!(n => format("0x%X", n.keysym)).join(", "));
                    } catch (Exception e) {
                        // Doesn't matter
                    }
                    return ComposeResult(ComposeResultType.EAT, ""w);
                }
            } else {
                active = false;
                debug_writeln("Compose aborted");
                // Return and output typed compose sequence, except if the last pressed key is Escape
                if (nk.keysym == keysyms_by_name["Escape"]) {
                    return ComposeResult(ComposeResultType.ABORT, ""w);
                } else {
                    return ComposeResult(ComposeResultType.ABORT, toUTF16(currentSequence));
                }
            }
        }
    }
    
    return ComposeResult(ComposeResultType.PASS, ""w);
}

ComposeResult composeUnicode(NeoKey nk) nothrow {
    // Starts processing keys after "uu", then accepts up to six hex digits, terminated by "space"
    // If complete, return matching Unicode char, otherwise abort
    if (unicodeInput.length < 6 && nk.keysym >= KEYSYM_0 && nk.keysym <= KEYSYM_0 + 9) {
        unicodeInput ~= '0' + (nk.keysym - KEYSYM_0);
        return ComposeResult(ComposeResultType.EAT, ""w);
    } else if (unicodeInput.length < 6 && nk.keysym >= KEYSYM_KP_0 && nk.keysym <= KEYSYM_KP_0 + 9) {
        unicodeInput ~= '0' + (nk.keysym - KEYSYM_KP_0);
        return ComposeResult(ComposeResultType.EAT, ""w);
    } else if (unicodeInput.length < 6 && nk.keysym >= KEYSYM_a && nk.keysym <= KEYSYM_a + 5) {
        unicodeInput ~= 'a' + (nk.keysym - KEYSYM_a);
        return ComposeResult(ComposeResultType.EAT, ""w);
    } else if (unicodeInput.length < 6 && nk.keysym >= KEYSYM_A && nk.keysym <= KEYSYM_A + 5) {
        unicodeInput ~= 'a' + (nk.keysym - KEYSYM_A);
        return ComposeResult(ComposeResultType.EAT, ""w);
    } else if (unicodeInput.length >= 2 && nk.keysym == KEYSYM_SPACE) {
        ComposeResult result;

        try {
            uint codepoint = to!uint(unicodeInput, 16);
            if (codepoint >= 0x20 && codepoint <= 0x10FFFF) { // 0x20 ≙ space
                result.type = ComposeResultType.FINISH;
                // There might be a simpler way to do this...
                // uint codepoint (32 bit) -> UTF-16 string
                result.result = codepoint.to!dchar.to!dstring.to!wstring;
            } else {
                result.type = ComposeResultType.ABORT;
            }
        } catch (Exception e) {
            result.type = ComposeResultType.ABORT;
        }
        unicodeInput = "";  // Important: reset stored codepoint string on finish
        return result;
    } else {
        unicodeInput = "";
        return ComposeResult(ComposeResultType.ABORT, ""w);
    }
}

ComposeResult composeRoman(NeoKey nk, bool upper) nothrow {
    // Accepts 1 to 4 decimal digits (1 to 3999), terminated by "space"
    if (romanNumeralInput.length < 4 && nk.keysym >= KEYSYM_0 && nk.keysym <= KEYSYM_0 + 9) {
        romanNumeralInput ~= '0' + (nk.keysym - KEYSYM_0);
        return ComposeResult(ComposeResultType.EAT, ""w);
    } else if (romanNumeralInput.length < 4 && nk.keysym >= KEYSYM_KP_0 && nk.keysym <= KEYSYM_KP_0 + 9) {
        romanNumeralInput ~= '0' + (nk.keysym - KEYSYM_KP_0);
        return ComposeResult(ComposeResultType.EAT, ""w);
    } else if (romanNumeralInput.length >= 1 && nk.keysym == KEYSYM_SPACE) {
        ComposeResult result;

        try {
            uint number = to!uint(romanNumeralInput);
            if (1 <= number && number <= 3999) {
                uint caseIndex = upper ? 1 : 0;

                if (uint thousands = number / 1000) {
                    result.result ~= ROMAN_DIGITS[3][thousands - 1][caseIndex];
                }
                if (uint hundreds = (number / 100) % 10) {
                    result.result ~= ROMAN_DIGITS[2][hundreds - 1][caseIndex];
                }
                if (uint tens = (number / 10) % 10) {
                    result.result ~= ROMAN_DIGITS[1][tens - 1][caseIndex];
                }
                if (uint units = number % 10) {
                    result.result ~= ROMAN_DIGITS[0][units - 1][caseIndex];
                }

                result.type = ComposeResultType.FINISH;
            } else {
                result.type = ComposeResultType.ABORT;
            }
        } catch (Exception e) {
            result.type = ComposeResultType.ABORT;
        }

        romanNumeralInput = "";  // Important: reset stored number string on finish
        return result;
    } else {
        romanNumeralInput = "";
        return ComposeResult(ComposeResultType.ABORT, ""w);
    }
}

ComposeResult composeLowerRoman(NeoKey nk) nothrow {
    return composeRoman(nk, false);
}

ComposeResult composeUpperRoman(NeoKey nk) nothrow {
    return composeRoman(nk, true);
}
