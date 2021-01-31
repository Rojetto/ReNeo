module mapping;

import core.sys.windows.windows;

import squire;

NeoKey[6][VK] M;

// Key is mapped to no action
const uint KEYSYM_VOID = 0xFFFFFF;
NeoKey VOID_KEY;

void initMapping() {
    VOID_KEY = mVK("VoidSymbol", 0xFF);

    M[VK_OEM_PERIOD] = [mVK("period", VK_OEM_PERIOD), mCH("enfilledcircbullet", '•'),
                              mCH("apostrophe", '\''), mVK("KP_3", VK_NUMPAD3),
                              mCH("U03D1", 'ϑ'), mCH("U21A6", '↦')];
    M['S'] = [mVK("s", 'S'), mVK("S", 'S'),
                    mCH("question", '?'), mCH("questiondown", '¿'),
                    mCH("Greek_sigma", 'σ'), mCH("Greek_SIGMA", 'Σ')];
    M['E'] = [mVK("e", 'E'), mVK("E", 'E'),
                    mCH("braceright", '}'), mVK("Right", VK_RIGHT),
                    mCH("Greek_epsilon", 'ε'), mCH("U2203", '∃')];
    M[VK_OEM_1] = [mCH("dead_circumflex", '^'), mCH("dead_caron", 'ˇ'),
                         mCH("U21BB", '↻'), mCH("dead_abovedot", '˙'),
                         mCH("dead_hook", '˞'), mCH("dead_belowdot", '.')];
    M[VK_TAB] = [mVK("Tab", VK_TAB), mVK("Tab", VK_TAB),
                       mCH("Multi_key", '♫'), mVK("Tab", VK_TAB),
                       mVK("VoidSymbol", 0xFF), mVK("VoidSymbol", 0xFF)];   
}