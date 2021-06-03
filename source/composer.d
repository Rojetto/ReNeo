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
}

ComposeNode composeRoot;
ComposeNode removeComposeRoot;

bool active;
ComposeNode *currentNode;

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
}


uint addedEntries;

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
            if (currentNode.result != ""w) {
                // We are creating a compose sequence that is a continuation of an existing one
                debug_writeln("Conflict in compose sequence ", entry.keysyms.map!(k => format("0x%X", k)).join("->"));
                return;
            }

            next = new ComposeNode(keysym, currentNode, [], ""w);
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
        ComposeNode *next;
        bool foundNext;

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
                active = false;
                debug_writeln("Compose finished");
                return ComposeResult(ComposeResultType.FINISH, next.result);
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
            return ComposeResult(ComposeResultType.ABORT, ""w);
        }
    }
    
    return ComposeResult(ComposeResultType.PASS, ""w);
}