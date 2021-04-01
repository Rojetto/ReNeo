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
    string composeDir = buildPath(exeDir, "compose");
    foreach (dirEntry; dirEntries(composeDir, "*.module", SpanMode.shallow)) {
        if (dirEntry.isFile) {
            string fname = dirEntry.name;
            debug_writeln("Loading compose module ", fname);
            loadModule(fname);
        }
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
            next = new ComposeNode(keysym, currentNode, [], ""w);
            currentNode.next ~= next;
        }

        currentNode = next;
    }

    currentNode.result = entry.result;
}

void loadModule(string fname) {
    /// Load a .module file and add all entries to the compose tree
    File f = File(fname, "r");
	while(!f.eof()) {
		string l = f.readln();
        
        try {
            auto entry = parseLine(l);
            addComposeEntry(entry);
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