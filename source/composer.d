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

import reneo;

const auto COMPOSE_REGEX = regex(`^(<[a-zA-Z0-9_]+>(?: <[a-zA-Z0-9_]+>)+)\s*:\s*"(.*)"`);

struct ComposeNode {
    uint keysym;
    ComposeNode *prev;
    ComposeNode *[] next;
    wstring result;
}

ComposeNode composeRoot;

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

void initCompose(string exeDir) {
    debug_writeln("Initializing compose");
    // reset existing compose tree
    composeRoot = ComposeNode();
    string composeDir = buildPath(exeDir, "compose");

    if (!exists(composeDir)) {
        return;
    }

    ComposeFileLine[] combinedComposeEntries;

    // Gather compose entries from all .module files
    foreach (dirEntry; dirEntries(composeDir, "*.module", SpanMode.shallow)) {
        if (dirEntry.isFile) {
            string fname = dirEntry.name;
            debug_writeln("Loading compose module ", fname);
            combinedComposeEntries ~= loadModule(fname);
        }
    }

    // Filter all entries that appear in .remove files
    foreach (dirEntry; dirEntries(composeDir, "*.remove", SpanMode.shallow)) {
        if (dirEntry.isFile) {
            string fname = dirEntry.name;
            debug_writeln("Removing compose module ", fname);
            ComposeFileLine[] entriesToRemove = loadModule(fname);
            combinedComposeEntries = combinedComposeEntries.filter!(e => !entriesToRemove.canFind(e)).array;
        }
    }

    // Build compose tree consisting of all entries
    foreach (entry; combinedComposeEntries) {
        addComposeEntry(entry);
    }
}

ComposeFileLine parseLine(string line) {
    /// Parse compose module line into an entry struct
    /// Throws if the line can't be parsed (e.g. it's empty or a comment)
    if (auto m = matchFirst(line, COMPOSE_REGEX)) {
        try {
            auto keysyms = split(m[1], regex(" ")).map!(s => parseKeysym(s[1 .. s.length-1])).array;
            wstring result = m[2].to!(wstring);

            return ComposeFileLine(keysyms, result);
        } catch (Exception e) {
            debug_writeln("Could not parse line '", line, "', skipping. Error: ", e.msg);
        }
    }
    
    throw new Exception("Line does not contain compose entry");
}

void addComposeEntry(ComposeFileLine entry) {
    auto currentNode = &composeRoot;

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


ComposeFileLine[] loadModule(string fname) {
    ComposeFileLine[] entries;

    /// Load a module file and return all entries
    File f = File(fname, "r");
	while(!f.eof()) {
		string l = f.readln();
        
        try {
            entries ~= parseLine(l);
        } catch (Exception e) {
            // Do nothing, most likely because the line just was a comment
        }
    }

    return entries;
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