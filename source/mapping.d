module mapping;

import core.sys.windows.windows;

import std.traits;

import reneo;

alias NeoMap = NeoKey[6][VK];

enum LayoutName {
    NEO,
    BONE,
    NEOQWERTZ
}

NeoMap[LayoutName] MAPS;

// Key is mapped to no action
const uint KEYSYM_VOID = 0xFFFFFF;
NeoKey VOID_KEY;

VK[VK] NumpadVKMap;

void initMapping() {
    VOID_KEY = mVK("VoidSymbol", 0xFF);

    foreach (LayoutName mn; [EnumMembers!LayoutName]) {
        NeoMap M;

/*
---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
|     VK               |      Layer 1                   |      Layer 2                  |        Layer 3                    |      Layer 4                      |     Layer 5                  |      Layer 6
---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
*/
// ***** Universal mappings *****
// TODO: check unicode symbols
M[VK_OEM_1]         = [mCH("dead_circumflex", '^'),     mCH("dead_caron", '\u02c7'),    mCH("U21BB", '\u21bb'),             mCH("dead_abovedot", '\u02d9'),     mCH("U02DE", '\u02de'),    mCH("dead_belowdot", '.')];
// TODO: check correctness
M[VK_OEM_2]         = [mCH("dead_grave", '\u02cb'),     mCH("dead_cedilla", '\u00b8'),  mCH("dead_abovering", '\u02da'),    mCH("dead_diaeresis", '\u00a8'),    mCH("dead_dasia", '\u1ffe'),   mCH("dead_macron", '\u00af')];
// TODO: check correctness
M[VK_OEM_4]         = [mCH("dead_acute", '\u02ca'),     mCH("dead_tilde", '\u02dc'),    mCH("dead_stroke", '\u002f'),       mCH("dead_doubleacute", '\u02dd'),  mCH("dead_psili", '\u1fbf'),    mCH("dead_breve", '\u02d8')];

M['1']              = [mVK("1", '1'),                   mCH("degree", '°'),             mCH("onesuperior", '¹'),            mCH("ordfeminine", 'ª'),            mCH("onesubscript", '₁'),      mCH("notsign", '¬')];
M['2']              = [mVK("2", '2'),                   mCH("section", '§'),            mCH("twosuperior", '²'),            mCH("masculine", 'º'),              mCH("twosubscript", '₂'),      mCH("logicalor", '∨')];
M['3']              = [mVK("3", '3'),                   mCH("U2113", 'ℓ'),              mCH("threesuperior", '³'),          mCH("numerosign", '№'),             mCH("threesubscript", '₃'),    mCH("logicaland", '∧')];
M['4']              = [mVK("4", '4'),                   mCH("guillemotright", '»'),     mCH("U203A", '›'),                  VOID_KEY,                           mCH("femalesymbol", '♀'),      mCH("uptack", '⊥')];
M['5']              = [mVK("5", '5'),                   mCH("guillemotleft", '«'),      mCH("U2039", '‹'),                  mCH("periodcentered", '·'),         mCH("malesymbol", '♂'),        mCH("U2221", '∡')];
M['6']              = [mVK("6", '6'),                   mCH("dollar", '$'),             mCH("cent", '¢'),                   mCH("sterling", '£'),               mCH("U26A5", '⚥'),             mCH("U2225", '∥')];
M['7']              = [mVK("7", '7'),                   mCH("EuroSign", '€'),           mCH("yen", '¥'),                    mCH("currency", '¤'),               mCH("U03F0", 'ϰ'),             mCH("rightarrow", '→')];
M['8']              = [mVK("8", '8'),                   mCH("doublelowquotemark", '„'), mCH("singlelowquotemark", '‚'),     mVK("Tab", VK_TAB),                 mCH("leftanglebracket", '⟨'),   mCH("infinity", '∞')];
M['9']              = [mVK("9", '9'),                   mCH("leftdoublequotemark", '“'),mCH("leftsinglequotemark", '‘'),    mVK("KP_Divide", VK_DIVIDE),        mCH("rightanglebracket", '⟩'),  mCH("variation", '∝')];
M['0']              = [mVK("0", '0'),                   mCH("rightdoublequotemark", '”'),mCH("rightsinglequotemark", '’'),  mVK("KP_Multiply", VK_MULTIPLY),    mCH("zerosubscript", '₀'),     mCH("emptyset", '∅')];

// We need to map Return so that compose knows about it
M[VK_RETURN]        = [mVK("Return", VK_RETURN),        mVK("Return", VK_RETURN),       mVK("Return", VK_RETURN),           mVK("Return", VK_RETURN),           mVK("Return", VK_RETURN),       mVK("Return", VK_RETURN)];
M[VK_TAB]           = [mVK("Tab", VK_TAB),              mVK("Tab", VK_TAB),             mCH("Multi_key", '♫'),              mVK("Tab", VK_TAB),                 VOID_KEY,                       VOID_KEY];
M[VK_SPACE]         = [mVK("space", VK_SPACE),          mVK("space", VK_SPACE),         mVK("space", VK_SPACE),             mVK("KP_0", VK_NUMPAD0),            mCH("nobreakspace", '\u00a0'),  mCH("U202F", '\u202f')];

M[VK_NUMLOCK]       = [mVK("Tab", VK_TAB),              mVK("Tab", VK_TAB),             mCH("equal", '='),                  mCH("notequal", '≠'),               mCH("U2248", '≈'),              mCH("identical", '≡')];
M[VK_DIVIDE]        = [mVK("KP_Divide", VK_DIVIDE),     mVK("KP_Divide", VK_DIVIDE),    mCH("division", '÷'),               mCH("U2044", '⁄'),                  mCH("U2300", '⌀'),              mCH("U2223", '∣')];
M[VK_MULTIPLY]      = [mVK("KP_Multiply", VK_MULTIPLY), mVK("KP_Multiply", VK_MULTIPLY),mCH("U22C5", '\u22c5'),             mCH("multiply", '×'),               mCH("U2299", '\u2299'),         mCH("U2297", '\u2297')];
M[VK_SUBTRACT]      = [mVK("KP_Subtract", VK_SUBTRACT), mVK("KP_Subtract", VK_SUBTRACT),mCH("U2212", '−'),                  mCH("U2216", '∖'),                  mCH("U2296", '\u2296'),         mCH("U2238", '\u2238')];
M[VK_ADD]           = [mVK("KP_Add", VK_ADD),           mVK("KP_Add", VK_ADD),          mCH("plusminus", '±'),              mCH("U2213", '∓'),                  mCH("U2295", '\u2295'),         mCH("U2214", '∔')];

M[VK_NUMPAD7]       = [mVK("KP_7", VK_NUMPAD7),         mCH("U2714", '\u2714'),         mCH("U2195", '↕'),                  mVK("KP_Home", VK_HOME),            mCH("U226A", '\u226a'),         mCH("upstile", '⌈')];
M[VK_NUMPAD8]       = [mVK("KP_8", VK_NUMPAD8),         mCH("U2718", '\u2718'),         mCH("uparrow", '↑'),                mVK("KP_Up", VK_UP),                mCH("intersection", '∩'),       mCH("U22C2", '⋂')];
M[VK_NUMPAD9]       = [mVK("KP_9", VK_NUMPAD9),         mCH("dagger", '†'),             mCH("U20D7", '\u20d7'),             mVK("KP_Page_Up", VK_PRIOR),        mCH("U226B", '\u226b'),         mCH("U2309", '⌉')];

M[VK_NUMPAD4]       = [mVK("KP_4", VK_NUMPAD4),         mCH("club", '♣'),               mCH("leftarrow", '←'),              mVK("KP_Left", VK_LEFT),            mCH("leftshoe", '⊂'),          mCH("U2286", '⊆')];
// TODO: KP 5 layer 4 should be a keyboard simulated left mouse click ‽
M[VK_NUMPAD5]       = [mVK("KP_5", VK_NUMPAD5),         mCH("EuroSign", '€'),           mCH("colon", ':'),                  VOID_KEY,                           mCH("U22B6", '⊶'),             mCH("U22B7", '⊷')];
M[VK_NUMPAD6]       = [mVK("KP_6", VK_NUMPAD6),         mCH("U2023", '\u2023'),         mCH("rightarrow", '→'),             mVK("KP_Right", VK_RIGHT),          mCH("rightshoe", '⊃'),         mCH("U2287", '⊇')];

M[VK_NUMPAD1]       = [mVK("KP_1", VK_NUMPAD1),         mCH("diamond", '♦'),            mCH("U2194", '↔'),                  mVK("KP_End", VK_END),              mCH("lessthanequal", '≤'),      mCH("downstile", '⌊')];
M[VK_NUMPAD2]       = [mVK("KP_2", VK_NUMPAD2),         mCH("heart", '♥'),              mCH("downarrow", '↓'),              mVK("KP_Down", VK_DOWN),            mCH("downshoe", '∪'),           mCH("U22C3", '\u22c3')];
M[VK_NUMPAD3]       = [mVK("KP_3", VK_NUMPAD3),         mCH("U2660", '♠'),              mCH("U21CC", '\u21cc'),             mVK("KP_Page_Down", VK_NEXT),       mCH("greaterthanequal", '≥'),   mCH("U230B", '⌋')];

M[VK_NUMPAD0]       = [mVK("KP_0", VK_NUMPAD0),         mCH("signifblank", '␣'),        mCH("percent", '%'),                mVK("KP_Insert", VK_INSERT),        mCH("permille", '‰'),           mCH("U25A1", '□')];
M[VK_SEPARATOR]     = [mVK("KP_Separator", VK_SEPARATOR),mVK("KP_Decimal", VK_DECIMAL), mCH("comma", ','),                  mVK("KP_Delete", VK_DELETE),        mCH("minutes", '′'),            mCH("seconds", '″')];


// ***** Layout specific mappings *****
switch (mn) {
// Layer 4 on 'D' is weird. According to spec it should send KP_Separator which allegedly corresponds to a comma. However, the Windows equivalent VK_SEPARATOR doesn't generate any character.
// Instead, VK_DECIMAL generates a comma, whereas I would have expected it to generate a period. So for compose purposes we label this KP_Separator, but actually send a VK_DECIMAL which results in a comma.
case LayoutName.NEO:
M[VK_OEM_MINUS]     = [mVK("minus", VK_OEM_MINUS),      mCH("emdash", '—'),             VOID_KEY,                           mVK("KP_Subtract", VK_SUBTRACT),    mCH("U2011", '‑'),                 mCH("U00AD", '\u00ad')];

M['X']              = [mVK("x", 'X'),                   mVK("X", 'X'),                  mCH("ellipsis", '…'),               mVK("Page_Up", VK_PRIOR),           mCH("Greek_xi", 'ξ'),              mCH("Greek_XI", 'Ξ')];
M['V']              = [mVK("v", 'V'),                   mVK("V", 'V'),                  mCH("underbar", '_'),               mVK("BackSpace", VK_BACK),          VOID_KEY,                          mCH("radical", '√')];
M['L']              = [mVK("l", 'L'),                   mVK("L", 'L'),                  mCH("bracketleft", '['),            mVK("Up", VK_UP),                   mCH("Greek_lamda", 'λ'),           mCH("Greek_LAMDA", 'Λ')];
M['C']              = [mVK("c", 'C'),                   mVK("C", 'C'),                  mCH("bracketright", ']'),           mVK("Delete", VK_DELETE),           mCH("Greek_chi", 'χ'),             mCH("U2102", 'ℂ')];
M['W']              = [mVK("w", 'W'),                   mVK("W", 'W'),                  mCH("asciicircum", '^'),            mVK("Page_Down", VK_NEXT),          mCH("Greek_omega", 'ω'),           mCH("Greek_OMEGA", 'Ω')];
M['K']              = [mVK("k", 'K'),                   mVK("K", 'K'),                  mCH("exclam", '!'),                 mCH("exclamdown", '¡'),             mCH("Greek_kappa", 'κ'),           mCH("multiply", '×')];
M['H']              = [mVK("h", 'H'),                   mVK("H", 'H'),                  mCH("less", '<'),                   mVK("KP_7", VK_NUMPAD7),            mCH("Greek_psi", 'ψ'),             mCH("Greek_PSI", 'Ψ')];
M['G']              = [mVK("g", 'G'),                   mVK("G", 'G'),                  mCH("greater", '>'),                mVK("KP_8", VK_NUMPAD8),            mCH("Greek_gamma", 'γ'),           mCH("Greek_GAMMA", 'Γ')];
M['F']              = [mVK("f", 'F'),                   mVK("F", 'F'),                  mCH("equal", '='),                  mVK("KP_9", VK_NUMPAD9),            mCH("Greek_phi", 'φ'),             mCH("Greek_PHI", 'Φ')];
M['Q']              = [mVK("q", 'Q'),                   mVK("Q", 'Q'),                  mCH("ampersand", '&'),              mVK("KP_Add", VK_ADD),              mCH("U03D5", 'ϕ'),                 mCH("U211A", 'ℚ')];
M[VK_OEM_3]         = [mVK("ssharp", VK_OEM_3),         mVK("U1E9E", VK_OEM_3),         mCH("U017F", 'ſ'),                  mCH("U2212", '−'),                  mCH("Greek_finalsmallsigma", 'ς'), mCH("jot", '∘')];

M['U']              = [mVK("u", 'U'),                   mVK("U", 'U'),                  mCH("backslash", '\\'),             mVK("Home", VK_HOME),               VOID_KEY,                          mCH("leftshoe", '⊂')];
M['I']              = [mVK("i", 'I'),                   mVK("I", 'I'),                  mCH("slash", '/'),                  mVK("Left", VK_LEFT),               mCH("Greek_iota", 'ι'),            mCH("integral", '∫')];
M['A']              = [mVK("a", 'A'),                   mVK("A", 'A'),                  mCH("braceleft", '{'),              mVK("Down", VK_DOWN),               mCH("Greek_alpha", 'α'),           mCH("U2200", '∀')];
M['E']              = [mVK("e", 'E'),                   mVK("E", 'E'),                  mCH("braceright", '}'),             mVK("Right", VK_RIGHT),             mCH("Greek_epsilon", 'ε'),         mCH("U2203", '∃')];
M['O']              = [mVK("o", 'O'),                   mVK("O", 'O'),                  mCH("asterisk", '*'),               mVK("End", VK_END),                 mCH("Greek_omicron", 'ο'),         mCH("elementof", '∈')];
M['S']              = [mVK("s", 'S'),                   mVK("S", 'S'),                  mCH("question", '?'),               mCH("questiondown", '¿'),           mCH("Greek_sigma", 'σ'),           mCH("Greek_SIGMA", 'Σ')];
M['N']              = [mVK("n", 'N'),                   mVK("N", 'N'),                  mCH("parenleft", '('),              mVK("KP_4", VK_NUMPAD4),            mCH("Greek_nu", 'ν'),              mCH("U2115", 'ℕ')];
M['R']              = [mVK("r", 'R'),                   mVK("R", 'R'),                  mCH("parenright", ')'),             mVK("KP_5", VK_NUMPAD5),            mCH("Greek_rho", 'ρ'),             mCH("U211D", 'ℝ')];
M['T']              = [mVK("t", 'T'),                   mVK("T", 'T'),                  mCH("minus", '-'),                  mVK("KP_6", VK_NUMPAD6),            mCH("Greek_tau", 'τ'),             mCH("partdifferential", '∂')];
M['D']              = [mVK("d", 'D'),                   mVK("D", 'D'),                  mCH("colon", ':'),                  mVK("KP_Separator", VK_DECIMAL),    mCH("Greek_delta", 'δ'),           mCH("Greek_DELTA", 'Δ')];
M['Y']              = [mVK("y", 'Y'),                   mVK("Y", 'Y'),                  mCH("at", '@'),                     mCH("period", '.'),                 mCH("Greek_upsilon", 'υ'),         mCH("nabla", '∇')];

M[VK_OEM_5]         = [mVK("udiaeresis", VK_OEM_5),     mVK("Udiaeresis", VK_OEM_5),    mCH("numbersign", '#'),             mVK("Escape", VK_ESCAPE),           VOID_KEY,                          mCH("downshoe", '∪')];
M[VK_OEM_6]         = [mVK("odiaeresis", VK_OEM_6),     mVK("Odiaeresis", VK_OEM_6),    mCH("dollar", '$'),                 mVK("Tab", VK_TAB),                 mCH("U03F5", 'ϵ'),                 mCH("intersection", '∩')];
M[VK_OEM_7]         = [mVK("adiaeresis", VK_OEM_7),     mVK("Adiaeresis", VK_OEM_7),    mCH("bar", '|'),                    mVK("Insert", VK_INSERT),           mCH("Greek_eta", 'η'),             mCH("U2135", 'ℵ')];
M['P']              = [mVK("p", 'P'),                   mVK("P", 'P'),                  mCH("asciitilde", '~'),             mVK("Return", VK_RETURN),           mCH("Greek_pi", 'π'),              mCH("Greek_PI", 'Π')];
M['Z']              = [mVK("z", 'Z'),                   mVK("Z", 'Z'),                  mCH("grave", '`'),                  VOID_KEY,                           mCH("Greek_zeta", 'ζ'),            mCH("U2124", 'ℤ')];
M['B']              = [mVK("b", 'B'),                   mVK("B", 'B'),                  mCH("plus", '+'),                   mCH("colon", ':'),                  mCH("Greek_beta", 'β'),            mCH("U21D0", '⇐')];
M['M']              = [mVK("m", 'M'),                   mVK("M", 'M'),                  mCH("percent", '%'),                mVK("KP_1", VK_NUMPAD1),            mCH("Greek_mu", 'μ'),              mCH("ifonlyif", '⇔')];
M[VK_OEM_COMMA]     = [mVK("comma", VK_OEM_COMMA),      mVK("endash", '–'),             mCH("quotedbl", '"'),               mVK("KP_2", VK_NUMPAD2),            mCH("U03F1", 'ϱ'),                 mCH("implies", '⇒')];
M[VK_OEM_PERIOD]    = [mVK("period", VK_OEM_PERIOD),    mCH("enfilledcircbullet", '•'), mCH("apostrophe", '\''),            mVK("KP_3", VK_NUMPAD3),            mCH("U03D1", 'ϑ'),                 mCH("U21A6", '↦')];
M['J']              = [mVK("j", 'J'),                   mVK("J", 'J'),                  mCH("semicolon", ';'),              mCH("semicolon", ';'),              mCH("Greek_theta", 'θ'),           mCH("Greek_THETA", 'Θ')];
break;

case LayoutName.BONE:
M[VK_OEM_MINUS]     = [mVK("minus", VK_OEM_MINUS),      mCH("emdash", '—'),             VOID_KEY,                           mVK("KP_Subtract", VK_SUBTRACT),    mCH("U2011", '‑'),                 mCH("U00AD", '\u00ad')];

M['J']              = [mVK("j", 'J'),                   mVK("J", 'J'),                  mCH("ellipsis", '…'),               mVK("Page_Up", VK_PRIOR),           mCH("Greek_theta", 'θ'),           mCH("Greek_THETA", 'Θ')];
M['D']              = [mVK("d", 'D'),                   mVK("D", 'D'),                  mCH("underbar", '_'),               mVK("BackSpace", VK_BACK),          mCH("Greek_delta", 'δ'),           mCH("Greek_DELTA", 'Δ')];
M['U']              = [mVK("u", 'U'),                   mVK("U", 'U'),                  mCH("bracketleft", '['),            mVK("Up", VK_UP),                   VOID_KEY,                          mCH("leftshoe", '⊂')];
M['A']              = [mVK("a", 'A'),                   mVK("A", 'A'),                  mCH("bracketright", ']'),           mVK("Delete", VK_DELETE),           mCH("Greek_alpha", 'α'),           mCH("U2200", '∀')];
M['X']              = [mVK("x", 'X'),                   mVK("X", 'X'),                  mCH("asciicircum", '^'),            mVK("Page_Down", VK_NEXT),          mCH("Greek_xi", 'ξ'),              mCH("Greek_XI", 'Ξ')];
M['P']              = [mVK("p", 'P'),                   mVK("P", 'P'),                  mCH("exclam", '!'),                 mCH("exclamdown", '¡'),             mCH("Greek_pi", 'π'),              mCH("Greek_PI", 'Π')];
M['H']              = [mVK("h", 'H'),                   mVK("H", 'H'),                  mCH("less", '<'),                   mVK("KP_7", VK_NUMPAD7),            mCH("Greek_psi", 'ψ'),             mCH("Greek_PSI", 'Ψ')];
M['L']              = [mVK("l", 'L'),                   mVK("L", 'L'),                  mCH("greater", '>'),                mVK("KP_8", VK_NUMPAD8),            mCH("Greek_lamda", 'λ'),           mCH("Greek_LAMDA", 'Λ')];
M['M']              = [mVK("m", 'M'),                   mVK("M", 'M'),                  mCH("equal", '='),                  mVK("KP_9", VK_NUMPAD9),            mCH("Greek_mu", 'μ'),              mCH("ifonlyif", '⇔')];
M['W']              = [mVK("w", 'W'),                   mVK("W", 'W'),                  mCH("ampersand", '&'),              mVK("KP_Add", VK_ADD),              mCH("Greek_omega", 'ω'),           mCH("Greek_OMEGA", 'Ω')];
M[VK_OEM_3]         = [mVK("ssharp", VK_OEM_3),         mVK("U1E9E", VK_OEM_3),         mCH("U017F", 'ſ'),                  mCH("U2212", '−'),                  mCH("Greek_finalsmallsigma", 'ς'), mCH("jot", '∘')];

M['C']              = [mVK("c", 'C'),                   mVK("C", 'C'),                  mCH("backslash", '\\'),             mVK("Home", VK_HOME),               mCH("Greek_chi", 'χ'),             mCH("U2102", 'ℂ')];
M['T']              = [mVK("t", 'T'),                   mVK("T", 'T'),                  mCH("slash", '/'),                  mVK("Left", VK_LEFT),               mCH("Greek_tau", 'τ'),             mCH("partdifferential", '∂')];
M['I']              = [mVK("i", 'I'),                   mVK("I", 'I'),                  mCH("braceleft", '{'),              mVK("Down", VK_DOWN),               mCH("Greek_iota", 'ι'),            mCH("integral", '∫')];
M['E']              = [mVK("e", 'E'),                   mVK("E", 'E'),                  mCH("braceright", '}'),             mVK("Right", VK_RIGHT),             mCH("Greek_epsilon", 'ε'),         mCH("U2203", '∃')];
M['O']              = [mVK("o", 'O'),                   mVK("O", 'O'),                  mCH("asterisk", '*'),               mVK("End", VK_END),                 mCH("Greek_omicron", 'ο'),         mCH("elementof", '∈')];
M['B']              = [mVK("b", 'B'),                   mVK("B", 'B'),                  mCH("question", '?'),               mCH("questiondown", '¿'),           mCH("Greek_beta", 'β'),            mCH("U21D0", '⇐')];
M['N']              = [mVK("n", 'N'),                   mVK("N", 'N'),                  mCH("parenleft", '('),              mVK("KP_4", VK_NUMPAD4),            mCH("Greek_nu", 'ν'),              mCH("U2115", 'ℕ')];
M['R']              = [mVK("r", 'R'),                   mVK("R", 'R'),                  mCH("parenright", ')'),             mVK("KP_5", VK_NUMPAD5),            mCH("Greek_rho", 'ρ'),             mCH("U211D", 'ℝ')];
M['S']              = [mVK("s", 'S'),                   mVK("S", 'S'),                  mCH("minus", '-'),                  mVK("KP_6", VK_NUMPAD6),            mCH("Greek_sigma", 'σ'),           mCH("Greek_SIGMA", 'Σ')];
M['G']              = [mVK("g", 'G'),                   mVK("G", 'G'),                  mCH("colon", ':'),                  mVK("KP_Separator", VK_DECIMAL),    mCH("Greek_gamma", 'γ'),           mCH("Greek_GAMMA", 'Γ')];
M['Q']              = [mVK("q", 'Q'),                   mVK("Q", 'Q'),                  mCH("at", '@'),                     mCH("period", '.'),                 mCH("U03D5", 'ϕ'),                 mCH("U211A", 'ℚ')];

M['F']              = [mVK("f", 'F'),                   mVK("F", 'F'),                  mCH("numbersign", '#'),             mVK("Escape", VK_ESCAPE),           mCH("Greek_phi", 'φ'),             mCH("Greek_PHI", 'Φ')];
M['V']              = [mVK("v", 'V'),                   mVK("V", 'V'),                  mCH("dollar", '$'),                 mVK("Tab", VK_TAB),                 VOID_KEY,                          mCH("radical", '√')];
M[VK_OEM_5]         = [mVK("udiaeresis", VK_OEM_5),     mVK("Udiaeresis", VK_OEM_5),    mCH("bar", '|'),                    mVK("Insert", VK_INSERT),           VOID_KEY,                          mCH("downshoe", '∪')];
M[VK_OEM_7]         = [mVK("adiaeresis", VK_OEM_7),     mVK("Adiaeresis", VK_OEM_7),    mCH("asciitilde", '~'),             mVK("Return", VK_RETURN),           mCH("Greek_eta", 'η'),             mCH("U2135", 'ℵ')];
M[VK_OEM_6]         = [mVK("odiaeresis", VK_OEM_6),     mVK("Odiaeresis", VK_OEM_6),    mCH("grave", '`'),                  VOID_KEY,                           mCH("U03F5", 'ϵ'),                 mCH("intersection", '∩')];
M['Y']              = [mVK("y", 'Y'),                   mVK("Y", 'Y'),                  mCH("plus", '+'),                   mCH("colon", ':'),                  mCH("Greek_upsilon", 'υ'),         mCH("nabla", '∇')];
M['Z']              = [mVK("z", 'Z'),                   mVK("Z", 'Z'),                  mCH("percent", '%'),                mVK("KP_1", VK_NUMPAD1),            mCH("Greek_zeta", 'ζ'),            mCH("U2124", 'ℤ')];
M[VK_OEM_COMMA]     = [mVK("comma", VK_OEM_COMMA),      mVK("endash", '–'),             mCH("quotedbl", '"'),               mVK("KP_2", VK_NUMPAD2),            mCH("U03F1", 'ϱ'),                 mCH("implies", '⇒')];
M[VK_OEM_PERIOD]    = [mVK("period", VK_OEM_PERIOD),    mCH("enfilledcircbullet", '•'), mCH("apostrophe", '\''),            mVK("KP_3", VK_NUMPAD3),            mCH("U03D1", 'ϑ'),                 mCH("U21A6", '↦')];
M['K']              = [mVK("k", 'K'),                   mVK("K", 'K'),                  mCH("semicolon", ';'),              mCH("semicolon", ';'),              mCH("Greek_kappa", 'κ'),           mCH("multiply", '×')];
break;

case LayoutName.NEOQWERTZ:
M[VK_OEM_3]         = [mVK("ssharp", VK_OEM_3),         mVK("U1E9E", VK_OEM_3),         VOID_KEY,                           mVK("KP_Subtract", VK_SUBTRACT),    mCH("Greek_finalsmallsigma", 'ς'), mCH("jot", '∘')];

M['Q']              = [mVK("q", 'Q'),                   mVK("Q", 'Q'),                  mCH("ellipsis", '…'),               mVK("Page_Up", VK_PRIOR),           mCH("U03D5", 'ϕ'),                 mCH("U211A", 'ℚ')];
M['W']              = [mVK("w", 'W'),                   mVK("W", 'W'),                  mCH("underbar", '_'),               mVK("BackSpace", VK_BACK),          mCH("Greek_omega", 'ω'),           mCH("Greek_OMEGA", 'Ω')];
M['E']              = [mVK("e", 'E'),                   mVK("E", 'E'),                  mCH("bracketleft", '['),            mVK("Up", VK_UP),                   mCH("Greek_epsilon", 'ε'),         mCH("U2203", '∃')];
M['R']              = [mVK("r", 'R'),                   mVK("R", 'R'),                  mCH("bracketright", ']'),           mVK("Delete", VK_DELETE),           mCH("Greek_rho", 'ρ'),             mCH("U211D", 'ℝ')];
M['T']              = [mVK("t", 'T'),                   mVK("T", 'T'),                  mCH("asciicircum", '^'),            mVK("Page_Down", VK_NEXT),          mCH("Greek_tau", 'τ'),             mCH("partdifferential", '∂')];
M['Z']              = [mVK("z", 'Z'),                   mVK("Z", 'Z'),                  mCH("exclam", '!'),                 mCH("exclamdown", '¡'),             mCH("Greek_zeta", 'ζ'),            mCH("U2124", 'ℤ')];
M['U']              = [mVK("u", 'U'),                   mVK("U", 'U'),                  mCH("less", '<'),                   mVK("KP_7", VK_NUMPAD7),            VOID_KEY,                          mCH("leftshoe", '⊂')];
M['I']              = [mVK("i", 'I'),                   mVK("I", 'I'),                  mCH("greater", '>'),                mVK("KP_8", VK_NUMPAD8),            mCH("Greek_iota", 'ι'),            mCH("integral", '∫')];
M['O']              = [mVK("o", 'O'),                   mVK("O", 'O'),                  mCH("equal", '='),                  mVK("KP_9", VK_NUMPAD9),            mCH("Greek_omicron", 'ο'),         mCH("elementof", '∈')];
M['P']              = [mVK("p", 'P'),                   mVK("P", 'P'),                  mCH("ampersand", '&'),              mVK("KP_Add", VK_ADD),              mCH("Greek_pi", 'π'),              mCH("Greek_PI", 'Π')];
M[VK_OEM_5]         = [mVK("udiaeresis", VK_OEM_5),     mVK("Udiaeresis", VK_OEM_5),    mCH("U017F", 'ſ'),                  mCH("U2212", '−'),                  VOID_KEY,                          mCH("downshoe", '∪')];

M['A']              = [mVK("a", 'A'),                   mVK("A", 'A'),                  mCH("backslash", '\\'),             mVK("Home", VK_HOME),               mCH("Greek_alpha", 'α'),           mCH("U2200", '∀')];
M['S']              = [mVK("s", 'S'),                   mVK("S", 'S'),                  mCH("slash", '/'),                  mVK("Left", VK_LEFT),               mCH("Greek_sigma", 'σ'),           mCH("Greek_SIGMA", 'Σ')];
M['D']              = [mVK("d", 'D'),                   mVK("D", 'D'),                  mCH("braceleft", '{'),              mVK("Down", VK_DOWN),               mCH("Greek_delta", 'δ'),           mCH("Greek_DELTA", 'Δ')];
M['F']              = [mVK("f", 'F'),                   mVK("F", 'F'),                  mCH("braceright", '}'),             mVK("Right", VK_RIGHT),             mCH("Greek_phi", 'φ'),             mCH("Greek_PHI", 'Φ')];
M['G']              = [mVK("g", 'G'),                   mVK("G", 'G'),                  mCH("asterisk", '*'),               mVK("End", VK_END),                 mCH("Greek_gamma", 'γ'),           mCH("Greek_GAMMA", 'Γ')];
M['H']              = [mVK("h", 'H'),                   mVK("H", 'H'),                  mCH("question", '?'),               mCH("questiondown", '¿'),           mCH("Greek_psi", 'ψ'),             mCH("Greek_PSI", 'Ψ')];
M['J']              = [mVK("j", 'J'),                   mVK("J", 'J'),                  mCH("parenleft", '('),              mVK("KP_4", VK_NUMPAD4),            mCH("Greek_theta", 'θ'),           mCH("Greek_THETA", 'Θ')];
M['K']              = [mVK("k", 'K'),                   mVK("K", 'K'),                  mCH("parenright", ')'),             mVK("KP_5", VK_NUMPAD5),            mCH("Greek_kappa", 'κ'),           mCH("multiply", '×')];
M['L']              = [mVK("l", 'L'),                   mVK("L", 'L'),                  mCH("minus", '-'),                  mVK("KP_6", VK_NUMPAD6),            mCH("Greek_lamda", 'λ'),           mCH("Greek_LAMDA", 'Λ')];
M[VK_OEM_6]         = [mVK("odiaeresis", VK_OEM_6),     mVK("Odiaeresis", VK_OEM_6),    mCH("colon", ':'),                  mVK("KP_Separator", VK_DECIMAL),    mCH("U03F5", 'ϵ'),                 mCH("intersection", '∩')];
M[VK_OEM_7]         = [mVK("adiaeresis", VK_OEM_7),     mVK("Adiaeresis", VK_OEM_7),    mCH("at", '@'),                     mCH("period", '.'),                 mCH("Greek_eta", 'η'),             mCH("U2135", 'ℵ')];

M['Y']              = [mVK("y", 'Y'),                   mVK("Y", 'Y'),                  mCH("numbersign", '#'),             mVK("Escape", VK_ESCAPE),           mCH("Greek_upsilon", 'υ'),         mCH("nabla", '∇')];
M['X']              = [mVK("x", 'X'),                   mVK("X", 'X'),                  mCH("dollar", '$'),                 mVK("Tab", VK_TAB),                 mCH("Greek_xi", 'ξ'),              mCH("Greek_XI", 'Ξ')];
M['C']              = [mVK("c", 'C'),                   mVK("C", 'C'),                  mCH("bar", '|'),                    mVK("Insert", VK_INSERT),           mCH("Greek_chi", 'χ'),             mCH("U2102", 'ℂ')];
M['V']              = [mVK("v", 'V'),                   mVK("V", 'V'),                  mCH("asciitilde", '~'),             mVK("Return", VK_RETURN),           VOID_KEY,                          mCH("radical", '√')];
M['B']              = [mVK("b", 'B'),                   mVK("B", 'B'),                  mCH("grave", '`'),                  VOID_KEY,                           mCH("Greek_beta", 'β'),            mCH("U21D0", '⇐')];
M['N']              = [mVK("n", 'N'),                   mVK("N", 'N'),                  mCH("plus", '+'),                   mCH("colon", ':'),                  mCH("Greek_nu", 'ν'),              mCH("U2115", 'ℕ')];
M['M']              = [mVK("m", 'M'),                   mVK("M", 'M'),                  mCH("percent", '%'),                mVK("KP_1", VK_NUMPAD1),            mCH("Greek_mu", 'μ'),              mCH("ifonlyif", '⇔')];
M[VK_OEM_COMMA]     = [mVK("comma", VK_OEM_COMMA),      mVK("endash", '–'),             mCH("quotedbl", '"'),               mVK("KP_2", VK_NUMPAD2),            mCH("U03F1", 'ϱ'),                 mCH("implies", '⇒')];
M[VK_OEM_PERIOD]    = [mVK("period", VK_OEM_PERIOD),    mCH("enfilledcircbullet", '•'), mCH("apostrophe", '\''),            mVK("KP_3", VK_NUMPAD3),            mCH("U03D1", 'ϑ'),                 mCH("U21A6", '↦')];
M[VK_OEM_MINUS]     = [mVK("minus", VK_OEM_MINUS),      mCH("emdash", '—'),             mCH("semicolon", ';'),              mCH("semicolon", ';'),              mCH("U2011", '‑'),                 mCH("U00AD", '\u00ad')];
break;

default:
debug_writeln("No mapping for ", mn);
break;
        }

        MAPS[mn] = M;
    }

    // initialize translation map for dual-state Numpad keys
    NumpadVKMap[VK_INSERT] = VK_NUMPAD0;
    NumpadVKMap[VK_END]    = VK_NUMPAD1;
    NumpadVKMap[VK_DOWN]   = VK_NUMPAD2;
    NumpadVKMap[VK_NEXT]   = VK_NUMPAD3;
    NumpadVKMap[VK_LEFT]   = VK_NUMPAD4;
    NumpadVKMap[VK_CLEAR]  = VK_NUMPAD5;
    NumpadVKMap[VK_RIGHT]  = VK_NUMPAD6;
    NumpadVKMap[VK_HOME]   = VK_NUMPAD7;
    NumpadVKMap[VK_UP]     = VK_NUMPAD8;
    NumpadVKMap[VK_PRIOR]  = VK_NUMPAD9;
    NumpadVKMap[VK_DELETE] = VK_SEPARATOR;
}