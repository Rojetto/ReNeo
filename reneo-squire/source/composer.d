module composer;

import std.stdio;
import std.utf;
import std.regex;
import std.algorithm;
import std.conv;

import squire;

const auto COMPOSE_REGEX = regex(`^(<[a-zA-Z0-9_]+>(?: <[a-zA-Z0-9_]+>)+)\s*:\s*"(.*)"`);

struct ComposeNode {
    uint keysym;
    ComposeNode *prev;
    ComposeNode *[] next;
    wstring result;
}

ComposeNode composeRoot;

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

void initCompose() {
    loadModule("compose/math.module");
}

void loadModule(string fname) {
    File f = File(fname, "r");
	while(!f.eof()) {
		string l = f.readln();
        if (auto m = matchFirst(l, COMPOSE_REGEX)) {
            auto keysyms = split(m[1], regex(" ")).map!(s => parseKeysym(s[1 .. s.length-1]));
            string result = m[2];

            auto currentNode = &composeRoot;

            foreach (keysym; keysyms) {
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

            currentNode.result = to!(wstring)(result);
        }
    }
}

ComposeResult compose(NeoKey nk) nothrow {
    return ComposeResult(ComposeResultType.PASS, ""w);
}