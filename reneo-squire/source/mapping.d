module mapping;

import core.sys.windows.windows;

import squire;

NeoKey[6][VK] M;

// Key is mapped to no action
const uint KEYSYM_VOID = 0xFFFFFF;
NeoKey VOID_KEY;

void initMapping() {
    VOID_KEY = mVK("VoidSymbol", 0xFF);

    /*
    ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
    |     VK               |      Layer 1                   |      Layer 2                  |        Layer 3                    |      Layer 4                  |     Layer 5                  |      Layer 6
    ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
    */
    M[VK_OEM_1]         = [mCH("dead_circumflex", '^'),     mCH("dead_caron", '\u02c7'),    mCH("U21BB", '\u21bb'),             mCH("dead_abovedot", '\u02d9'), mCH("dead_hook", '\u02de'),    mCH("dead_belowdot", '.')];
    M['1']              = [mVK("1", '1'),                   mCH("degree", '°'),             mCH("onesuperior", '¹'),            mCH("ordfeminine", 'ª'),        mCH("onesubscript", '₁'),      mCH("notsign", '¬')];
    M['2']              = [mVK("2", '2'),                   mCH("section", '§'),            mCH("twosuperior", '²'),            mCH("masculine", 'º'),          mCH("twosubscript", '₂'),      mCH("logicalor", '∨')];
    M['3']              = [mVK("3", '3'),                   mCH("U2113", 'ℓ'),              mCH("threesuperior", '³'),          mCH("numerosign", '№'),         mCH("threesubscript", '₃'),    mCH("logicaland", '∧')];
    M['4']              = [mVK("4", '4'),                   mCH("guillemotright", '»'),     mCH("U203A", '›'),                  mCH("U22EE", '\u22ee'),         mCH("femalesymbol", '♀'),      mCH("uptack", '⊥')];
    M['5']              = [mVK("5", '5'),                   mCH("guillemotleft", '«'),      mCH("U2039", '‹'),                  mCH("periodcentered", '·'),     mCH("malesymbol", '♂'),        mCH("U2221", '∡')];
    M['6']              = [mVK("6", '6'),                   mCH("dollar", '$'),             mCH("cent", '¢'),                   mCH("sterling", '£'),           mCH("U26A5", '⚥'),             mCH("U2225", '∥')];
    M['7']              = [mVK("7", '7'),                   mCH("EuroSign", '€'),           mCH("yen", '¥'),                    mCH("currency", '¤'),           mCH("U03F0", 'ϰ'),             mCH("rightarrow", '→')];
    M['8']              = [mVK("8", '8'),                   mCH("doublelowquotemark", '„'), mCH("singlelowquotemark", '‚'),     VOID_KEY,                       mCH("leftanglebracket", '⟨'),   mCH("infinity", '∞')];
    M['9']              = [mVK("9", '9'),                   mCH("leftdoublequotemark", '“'),mCH("leftsinglequotemark", '‘'),    mVK("KP_Divide", VK_DIVIDE),    mCH("rightanglebracket", '⟩'),  mCH("variation", '∝')];
    M['0']              = [mVK("0", '0'),                   mCH("rightdoublequotemark", '”'),mCH("rightsinglequotemark", '’'),  mVK("KP_Multiply", VK_MULTIPLY),mCH("zerosubscript", '₀'),     mCH("emptyset", '∅')];
    M[VK_OEM_MINUS]     = [mVK("minus", VK_OEM_MINUS),      mCH("emdash", '—'),             VOID_KEY,                           mVK("minus", VK_OEM_MINUS),     mCH("U2011", '‑'),             mCH("U00AD", '\u00ad')];
    M[VK_OEM_2]         = [mVK("dead_grave", VK_OEM_2),     mCH("dead_cedilla", '\u00b8'),  mCH("dead_abovering", '\u02da'),    mCH("dead_diaeresis", '\u00a8'),mCH("dead_dasia", '\u1ffe'),   mCH("dead_macron", '\u00af')];

    M[VK_TAB]           = [mVK("Tab", VK_TAB),              mVK("Tab", VK_TAB),             mCH("Multi_key", '♫'),          mVK("Tab", VK_TAB),         VOID_KEY,                   VOID_KEY];

    M['E']              = [mVK("e", 'E'),                   mVK("E", 'E'),                  mCH("braceright", '}'),         mVK("Right", VK_RIGHT),     mCH("Greek_epsilon", 'ε'),  mCH("U2203", '∃')];

    M['S']              = [mVK("s", 'S'),                   mVK("S", 'S'),                  mCH("question", '?'),           mCH("questiondown", '¿'),   mCH("Greek_sigma", 'σ'),    mCH("Greek_SIGMA", 'Σ')];

    M[VK_OEM_PERIOD]    = [mVK("period", VK_OEM_PERIOD),    mCH("enfilledcircbullet", '•'), mCH("apostrophe", '\''),        mVK("KP_3", VK_NUMPAD3),    mCH("U03D1", 'ϑ'),          mCH("U21A6", '↦')];
}