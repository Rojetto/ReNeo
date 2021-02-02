/****************************************************************************\
* Module Name: KBDRENEO.C
* Deutsches ergonomisches Layout Neo 2.0 (ReNEO Treiber)
\****************************************************************************/

#include <windows.h>
#include "kbd.h"
#include "kbd_mod.h"
#include "keysym4utf16.h"
#include "kbdreneo.h"

#if defined(_M_IA64)
#pragma section(".data")
#define ALLOC_SECTION_LDATA __declspec(allocate(".data"))
#else
#pragma data_seg(".data")
#define ALLOC_SECTION_LDATA
#endif


/* **************************************************************************************************************\
* ausVK[] - Virtual Scan Code to Virtual Key
* 
*       +---+ +---------------+ +---------------+ +---------------+   +--------------+                       
*       |T01| |F1 ¦F2 ¦F3 ¦F4 | |F5 ¦F6 ¦F7 ¦F8 | |F9 ¦F10¦F11¦F12|   |Druk¦Roll¦Paus|                       
*       +---+ +---------------+ +---------------+ +---------------+   +--------------+                       
*       +---------------------------------------------------------+   +--------------+   +---------------+   
*       |T29¦T02¦T03¦T04¦T05¦T06¦T07¦T08¦T09¦T0A¦T0B¦T0C¦T0D¦ T0E |   |Einf¦Pos1¦PgUp|   ¦Num¦ / ¦ * ¦ - ¦   
*       |---------------------------------------------------------|   |--------------|   +---+---+---+---¦   
*       |T0F¦T10¦T11¦T12¦T13¦T14¦T15¦T16¦T17¦T18¦T19¦T1A¦T1B¦ Ret |   |Entf¦Ende¦PgDn|   ¦ 7 ¦ 8 ¦ 9 ¦   ¦   
*       |-----------------------------------------------------+   |   +--------------+   +---+---+---¦   ¦   
*       | T3A ¦T1E¦T1F¦T20¦T21¦T22¦T23¦T24¦T25¦T26¦T27¦T28¦T2B¦   |                      ¦ 4 ¦ 5 ¦ 6 ¦ + ¦   
*       |---------------------------------------------------------|        +----+        +---+---+---+---¦   
*       |T2A ¦T56¦T2C¦T2D¦T2E¦T2F¦T30¦T31¦T32¦T33¦T34¦T35¦ T36    |        | Up |        ¦ 1 ¦ 2 ¦ 3 ¦   ¦   
*       |---------------------------------------------------------|   +----+----+----+   +-------+---¦   ¦   
*       | Str ¦ Fe ¦ Al ¦     Leerzeichen    ¦X38 ¦ Fe ¦ Me ¦ Str |   |Left¦Down¦ Re.¦   ¦ 0     ¦ , ¦Ent¦   
*       +---------------------------------------------------------+   +--------------+   +---------------+   
* 
* 
*       +---+ +---------------+ +---------------+ +---------------+   +--------------+                       
*       |Esc| |F1 ¦F2 ¦F3 ¦F4 | |F5 ¦F6 ¦F7 ¦F8 | |F9 ¦F10¦F11¦F12|   |Druk¦Roll¦Paus|                       
*       +---+ +---------------+ +---------------+ +---------------+   +--------------+                       
*       +---------------------------------------------------------+   +--------------+   +---------------+   
*       |T1 ¦1  ¦2  ¦3  ¦4  ¦5  ¦6  ¦7  ¦8  ¦9  ¦0  ¦-  ¦T2 ¦Back |   |Einf¦Pos1¦PgUp|   ¦Num¦ / ¦ * ¦ - ¦   
*       |---------------------------------------------------------|   |--------------|   +---+---+---+---¦   
*       |Tab¦x  ¦v  ¦l  ¦c  ¦w  ¦k  ¦h  ¦g  ¦f  ¦q  ¦ß  ¦T3 ¦ Ret |   |Entf¦Ende¦PgDn|   ¦ 7 ¦ 8 ¦ 9 ¦   ¦   
*       |-----------------------------------------------------+   |   +--------------+   +---+---+---¦   ¦   
*       | M3  ¦u  ¦i  ¦a  ¦e  ¦o  ¦s  ¦n  ¦r  ¦t  ¦d  ¦y  ¦M3 ¦   |                      ¦ 4 ¦ 5 ¦ 6 ¦ + ¦   
*       |---------------------------------------------------------|        +----+        +---+---+---+---¦   
*       |Ums ¦M4 ¦ü  ¦ö  ¦ä  ¦p  ¦z  ¦b  ¦m  ¦,  ¦.  ¦j  ¦ Umsch  |        | Up |        ¦ 1 ¦ 2 ¦ 3 ¦   ¦   
*       |---------------------------------------------------------|   +----+----+----+   +-------+---¦   ¦   
*       | Str ¦ Fe ¦ Al ¦     Leerzeichen    ¦ M4 ¦ Fe ¦ Me ¦ Str |   |Left¦Down¦ Re.¦   ¦ 0     ¦ , ¦Ent¦   
*       +---------------------------------------------------------+   +--------------+   +---------------+  
* 
\************************************************************************************************************** */


static ALLOC_SECTION_LDATA USHORT ausVK[] = {
    // ------------- 00 - 0F
    T00, T01, T02, T03, T04, T05, T06, T07,
    T08, T09, T0A, T0B, T0C, T0D, T0E, T0F,
    // ------------- 10 - 1F
    T10, T11, T12, T13, T14, T15, T16, T17,
    T18, T19, T1A, T1B, T1C, T1D, T1E, T1F,
    // ------------- 20 - 2F
    T20, T21, T22, T23, T24, T25, T26, T27,
    T28, T29, T2A, T2B, T2C, T2D, T2E, T2F,
    // ------------- 30 - 3F
    T30, T31, T32, T33, T34, T35,


// Rechtes Shift muss KBDEXT bit haben

    T36 | KBDEXT,

    T37 | KBDMULTIVK,               // numpad_* + Shift/Alt -> SnapShot

    T38, T39, T3A, T3B, T3C, T3D, T3E, T3F,
    // ------------- 40 - 4F
    T40, T41, T42, T43, T44,

	
    /* NumLock Key:
     *     KBDEXT     - VK_NUMLOCK ist Extended key
     *     KBDMULTIVK - VK_NUMLOCK oder VK_PAUSE (mit oder ohne STRG) */

	 T45 | KBDEXT | KBDMULTIVK,

    T46 | KBDMULTIVK,

	
    /*
     * Number Pad keys:
     *     KBDNUMPAD  - digits 0-9 and decimal point.
     *     KBDSPECIAL - require special processing by Windows
     */
    
	T47 | KBDNUMPAD | KBDSPECIAL,   // Numpad 7 (Home)
    T48 | KBDNUMPAD | KBDSPECIAL,   // Numpad 8 (Up),
    T49 | KBDNUMPAD | KBDSPECIAL,   // Numpad 9 (PgUp),
    T4A,
    T4B | KBDNUMPAD | KBDSPECIAL,   // Numpad 4 (Left),
    T4C | KBDNUMPAD | KBDSPECIAL,   // Numpad 5 (Clear),
    T4D | KBDNUMPAD | KBDSPECIAL,   // Numpad 6 (Right),
    T4E,
    T4F | KBDNUMPAD | KBDSPECIAL,   // Numpad 1 (End),

    // ------------- 50 - 5F
    T50 | KBDNUMPAD | KBDSPECIAL,   // Numpad 2 (Down),
    T51 | KBDNUMPAD | KBDSPECIAL,   // Numpad 3 (PgDn),
    T52 | KBDNUMPAD | KBDSPECIAL,   // Numpad 0 (Ins),
    T53 | KBDNUMPAD | KBDSPECIAL,   // Numpad . (Del),

    T54, T55, T56, T57, T58, T59, T5A, T5B,
    T5C, T5D, T5E, T5F,
    // ------------- 60 - 6F
    T60, T61, T62, T63, T64, T65, T66, T67,
    T68, T69, T6A, T6B, T6C, T6D, T6E, T6F,
    // ------------- 70 - 7F
    T70, T71, T72, T73, T74, T75, T76, T77,
    T78, T79, T7A, T7B, T7C, T7D, T7E

};


static ALLOC_SECTION_LDATA VSC_VK aE0VscToVk[] = {
        { 0x10, X10 | KBDEXT              },  // Speedracer: Previous Track
        { 0x19, X19 | KBDEXT              },  // Speedracer: Next Track
        { 0x1D, X1D | KBDEXT              },  // RControl
        { 0x20, X20 | KBDEXT              },  // Speedracer: Volume Mute
        { 0x21, X21 | KBDEXT              },  // Speedracer: Launch App 2
        { 0x22, X22 | KBDEXT              },  // Speedracer: Media Play/Pause
        { 0x24, X24 | KBDEXT              },  // Speedracer: Media Stop
        { 0x2E, X2E | KBDEXT              },  // Speedracer: Volume Down
        { 0x30, X30 | KBDEXT              },  // Speedracer: Volume Up
        { 0x32, X32 | KBDEXT              },  // Speedracer: Browser Home
        { 0x35, X35 | KBDEXT              },  // Numpad Divide
        { 0x37, X37 | KBDEXT              },  // Snapshot
        { 0x38, X38 | KBDEXT              },  // RMenu
        { 0x47, X47 | KBDEXT              },  // Home
        { 0x48, X48 | KBDEXT              },  // Up
        { 0x49, X49 | KBDEXT              },  // Prior
        { 0x4B, X4B | KBDEXT              },  // Left
        { 0x4D, X4D | KBDEXT              },  // Right
        { 0x4F, X4F | KBDEXT              },  // End
        { 0x50, X50 | KBDEXT              },  // Down
        { 0x51, X51 | KBDEXT              },  // Next
        { 0x52, X52 | KBDEXT              },  // Insert
        { 0x53, X53 | KBDEXT              },  // Delete
        { 0x5B, X5B | KBDEXT              },  // Left Win
        { 0x5C, X5C | KBDEXT              },  // Right Win
        { 0x5D, X5D | KBDEXT              },  // Application
        { 0x5F, X5F | KBDEXT              },  // Speedracer: Sleep
        { 0x65, X65 | KBDEXT              },  // Speedracer: Browser Search
        { 0x66, X66 | KBDEXT              },  // Speedracer: Browser Favorites
        { 0x67, X67 | KBDEXT              },  // Speedracer: Browser Refresh
        { 0x68, X68 | KBDEXT              },  // Speedracer: Browser Stop
        { 0x69, X69 | KBDEXT              },  // Speedracer: Browser Forward
        { 0x6A, X6A | KBDEXT              },  // Speedracer: Browser Back
        { 0x6B, X6B | KBDEXT              },  // Speedracer: Launch App 1
        { 0x6C, X6C | KBDEXT              },  // Speedracer: Launch Mail
        { 0x6D, X6D | KBDEXT              },  // Speedracer: Launch Media Selector
        { 0x1C, X1C | KBDEXT              },  // Numpad Enter
        { 0x46, X46 | KBDEXT              },  // Break (Ctrl + Pause)
        { 0,      0                       }
};


static ALLOC_SECTION_LDATA VSC_VK aE1VscToVk[] = {
        { 0x1D, Y1D                       },  // Pause
        { 0   ,   0                       }
};


/* **************************************************************************\
* aVkToBits[]  - map Virtual Keys to Modifier Bits
*
* Siehe kbd.h für mehr Infos
\************************************************************************** */

// Es wird nicht zwischen linken und/oder rechtem Modifier unterschieden

static ALLOC_SECTION_LDATA VK_TO_BIT aVkToBits[] = {
    { VK_SHIFT		,	KBDSHIFT	},
    { VK_CONTROL	,	KBDCTRL		},    
    { VK_MENU		,	KBDALT		},
    { 0				,	0			}
};


/* **************************************************************************\
* aModification[]  - map character modifier bits to modification number
*
* Siehe kbd.h für mehr Infos
\************************************************************************** */

static ALLOC_SECTION_LDATA MODIFIERS CharModifiers = {
	&aVkToBits[0],
	1, // Maximaler Wert, den die Modifier-Bitmaske annehmen kann
	{
	//  Modifier NEO 
	//  Ebene 0 - nix
	//  Ebene 1 - Shift
	//  
	//  Modification#	// Keys Pressed
	//  ===============	//=======================================
						//	Shift
		0,				//	0
		1				//	1
	}
};


/* **************************************************************************\
* Spezielle Werte für den VK (Spalte 1)
*     0xff          - Tote Zeichen für obige Zeile
*     0             - Beendet die gesamte Liste
*
* Spezielle Werte für Attributes (Spalte 2)
*     CAPLOK    - CAPS-LOCK wirkt auf diese Taste wie SHIFT
*
* Spezielle Werte für wch[*]
*     WCH_NONE      - Keine Belegung
*     WCH_DEAD      - Totes Zeichen
*     WCH_LGTR      - Ligatur
\************************************************************************** */


// Numpad-Belegung muss zum Schluss kommen
// Entgegen der neo20.txt vorgesehene Belegung 1,2,3,4,5,6 ist hier 1,4,3,2 umgesetzt, Num ist nicht belegt:
static ALLOC_SECTION_LDATA VK_TO_WCHARS4 aVkToWch2[] = {
//				| CapsLock	|			|	 SHIFT		|
//				|===========|===========|===============|
{VK_OEM_1		,0			,WCH_DEAD	,WCH_DEAD				},	//Tote Taste 1
{0xff			,0			,'^'		,caron					},
{'1'			,0			,'1'		,degree					},
{'2'			,0			,'2'		,section                },
{'3'			,0			,'3'		,litersign				},
{'4'			,0			,'4'		,guillemotright			},
{'5'			,0			,'5'		,guillemotleft			},
{'6'			,0			,'6'		,dollar                 },
{'7'			,0			,'7'		,EuroSign				},
{'8'			,0			,'8'		,doublelowquotemark		},
{'9'			,0			,'9'		,leftdoublequotemark	},
{'0'			,0			,'0'		,rightdoublequotemark	},
{VK_OEM_MINUS	,0			,'-'		,emdash					},
{VK_OEM_2		,0			,WCH_DEAD	,WCH_DEAD				},	//Tote Taste 2
{0xff			,0	    	,grave		,cedilla				},
{VK_TAB			,0			,'\t'		,'\t'					},
//{0xff			,0			,WCH_NONE	,WCH_NONE				,Multi_key				,WCH_NONE		,WCH_NONE			,WCH_NONE			},
{'X'			,CAPLOK     ,'x'		,'X'					},
{'V'			,CAPLOK     ,'v'		,'V'					},
{'L'			,CAPLOK 	,'l'		,'L'					},
{'C'			,CAPLOK 	,'c'		,'C'					},
{'W'			,CAPLOK 	,'w'		,'W'					},
{'K'			,CAPLOK 	,'k'		,'K'					},
{'H'			,CAPLOK 	,'h'		,'H'					},
{'G'			,CAPLOK 	,'g'		,'G'					},
{'F'			,CAPLOK 	,'f'		,'F'					},
{'Q'			,CAPLOK 	,'q'		,'Q'					},
{VK_OEM_3		,CAPLOK 	,ssharp		,Ssharp                 },
{VK_OEM_4		,0			,WCH_DEAD	,WCH_DEAD	            },	//Tote Taste 3
{0xff			,0			,acute		,'~'		            },
{'U'			,CAPLOK 	,'u'		,'U'					},
{'I'			,CAPLOK 	,'i'		,'I'					},
{'A'			,CAPLOK 	,'a'		,'A'					},
{'E'			,CAPLOK 	,'e'		,'E'					},
{'O'			,CAPLOK 	,'o'		,'O'					},
{'S'			,CAPLOK 	,'s'		,'S'					},
{'N'			,CAPLOK 	,'n'		,'N'					},
{'R'			,CAPLOK 	,'r'		,'R'					},
{'T'			,CAPLOK 	,'t'		,'T'					},
{'D'			,CAPLOK 	,'d'		,'D'					},
{'Y'			,CAPLOK 	,'y'		,'Y'                    },
{VK_OEM_5		,CAPLOK 	,udiaeresis	,Udiaeresis				}, 
{VK_OEM_6		,CAPLOK 	,odiaeresis	,Odiaeresis				},
{VK_OEM_7		,CAPLOK 	,adiaeresis	,Adiaeresis				},
{'P'			,CAPLOK 	,'p'		,'P'					},
{'Z'			,CAPLOK 	,'z'		,'Z'					}, 
{'B'			,CAPLOK 	,'b'		,'B'					},
{'M'			,CAPLOK 	,'m'		,'M'					},
{VK_OEM_COMMA	,0			,','		,endash					},
{VK_OEM_PERIOD	,0          ,'.'		,enfilledcircbullet		},
{'J'			,CAPLOK     ,'j'		,'J'                    },
{VK_ADD			,0			,'+'		,minusorplus	},
{VK_DIVIDE		,0			,'/'		,fractionslash	},
{VK_MULTIPLY	,0			,'*'		,multiply		},
{VK_SUBTRACT	,0			,'-'		,setminus		},
{VK_DECIMAL		,0			,','		,','			},
{VK_NUMPAD0		,0			,'0'		,'0'			},
{VK_NUMPAD1		,0			,'1'		,'1'			},
{VK_NUMPAD2		,0			,'2'		,'2'			},
{VK_NUMPAD3		,0			,'3'		,'3'			},
{VK_NUMPAD4		,0			,'4'		,'4'			},
{VK_NUMPAD5		,0			,'5'		,'5'			},
{VK_NUMPAD6		,0			,'6'		,'6'			},
{VK_NUMPAD7		,0			,'7'		,'7'			},
{VK_NUMPAD8		,0			,'8'		,'8'			},
{VK_NUMPAD9		,0			,'9'		,'9'			},
{VK_SPACE		,0			,space		,space          },
{VK_BACK		,0			,'\b'		,'\b'		    },
{VK_ESCAPE		,0			,escape		,escape		    },
{VK_RETURN		,0			,'\r'		,'\r'		    },
{VK_CANCEL		,0			,endoftext	,endoftext	    },
{0				,0			,0			,0				}
};


// Hier müssen die verwendeten WChar_Tables vorkommen; Numpad MUSS letzte Zeile sein.
static ALLOC_SECTION_LDATA VK_TO_WCHAR_TABLE aVkToWcharTable[] = {
    {  (PVK_TO_WCHARS1)aVkToWch2, 2, sizeof(aVkToWch2[0]) },
    {                       NULL, 0, 0                    },
};


/* **************************************************************************\
* aKeyNames[], aKeyNamesExt[]  - Virtual Scancode to Key Name tables
*
* Table attributes: Ordered Scan (by scancode), null-terminated
*
* Nur für Tasten, die keine Zeichen erzeugen, Tasten die Zeichen erzeugen
* werden danach benannt
\************************************************************************** */

static ALLOC_SECTION_LDATA VSC_LPWSTR aKeyNames[] = {
    0x01,    L"ESC",
    0x0e,    L"R\x00DC" L"CKTASTE",
    0x0f,    L"TABULATOR",
    0x1c,    L"EINGABE",
    0x1d,    L"STRG",
    0x2a,    L"UMSCHALT",
    0x2b,    L"MOD 3 RECHTS",
    0x36,    L"UMSCHALT RECHTS",
    0x37,    L"* (ZEHNERTASTATUR)",
    0x38,    L"ALT",
    0x39,    L"LEER",
    0x3a,    L"MOD 3 LINKS",
    0x3b,    L"F1",
    0x3c,    L"F2",
    0x3d,    L"F3",
    0x3e,    L"F4",
    0x3f,    L"F5",
    0x40,    L"F6",
    0x41,    L"F7",
    0x42,    L"F8",
    0x43,    L"F9",
    0x44,    L"F10",
    0x45,    L"PAUSE",
    0x46,    L"ROLLEN-FESTSTELL",
    0x47,    L"7 (ZEHNERTASTATUR)",
    0x48,    L"8 (ZEHNERTASTATUR)",
    0x49,    L"9 (ZEHNERTASTATUR)",
    0x4a,    L"- (ZEHNERTASTATUR)",
    0x4b,    L"4 (ZEHNERTASTATUR)",
    0x4c,    L"5 (ZEHNERTASTATUR)",
    0x4d,    L"6 (ZEHNERTASTATUR)",
    0x4e,    L"+ (ZEHNERTASTATUR)",
    0x4f,    L"1 (ZEHNERTASTATUR)",
    0x50,    L"2 (ZEHNERTASTATUR)",
    0x51,    L"3 (ZEHNERTASTATUR)",
    0x52,    L"0 (ZEHNERTASTATUR)",
    0x53,    L"KOMMA (ZEHNERTASTATUR)",
    0x56,    L"MOD 4 LINKS",
    0x57,    L"F11",
    0x58,    L"F12",
    0   ,    NULL
};


static ALLOC_SECTION_LDATA VSC_LPWSTR aKeyNamesExt[] = {
    0x1c,    L"EINGABE (ZEHNERTASTATUR)",
    0x1d,    L"STRG-RECHTS",
    0x35,    L"/ (ZEHNERTASTATUR)",
    0x37,    L"DRUCK",
    0x38,    L"MOD 4 RECHTS",
    0x45,    L"NUM-FESTSTELL",
    0x46,    L"UNTBR",
    0x47,    L"POS1",
    0x48,    L"NACH-OBEN",
    0x49,    L"BILD-NACH-OBEN",
    0x4b,    L"NACH-LINKS",
    0x4d,    L"NACH-RECHTS",
    0x4f,    L"ENDE",
    0x50,    L"NACH-UNTEN",
    0x51,    L"BILD-NACH-UNTEN",
    0x52,    L"EINFG",
    0x53,    L"ENTF",
    0x54,    L"<00>",
    0x56,    L"HILFE",
    0x5b,    L"LINKE WINDOWS",
    0x5c,    L"RECHTE WINDOWS",
    0x5d,    L"ANWENDUNG",
    0   ,    NULL
};


static ALLOC_SECTION_LDATA DEADKEY_LPWSTR aKeyNamesDead[] = {
//Tottaste 1 (links neben 1)
	L"^"         L"ZIRKUMFLEX",
    L"\x02C7"    L"HATSCHEK",
    L"\x21bb"    L"DREHEN",	
	L"\x02d9"    L"PUNKT_DARUEBER",	
	L"\x02de"    L"RHOTIC_HOOK",	
    L"\x002E"    L"PUNKT_DARUNTER",

//Tottaste 2 (links neben Rücktaste)
    L"\x0060"    L"GRAVIS",
    L"\x00B8"    L"CEDILLE",
    L"\x02DA"    L"RING",
    L"\x00A8"    L"TREMA",
    L"\x1ffe"    L"SPIRITUS_ASPER",
    L"\x00AF"    L"MAKRON",

//Tottaste 3 (rechts neben „ß“)
    L"\x00B4"    L"AKUT",
    L"\x007E"    L"TILDE",
    L"\x002D"    L"QUERSTRICH",
    L"\x02DD"    L"DOPPEL_AKUT", 
    L"\x1fbf"    L"SPIRITUS_LENIS",
    L"\x02D8"    L"BREVE",	   
    NULL
};


static ALLOC_SECTION_LDATA DEADKEY aDeadKey[] = {
// Schema:
//    Deadtrans( Name oder Unicode der normalen Taste,    Name oder Unicode der toten Taste,    Name oder Unicode der zu bildenden Taste,    0x0000 für  sichtbar, 0x0001 für tot)
//    0, 0    terminiert komplette Liste
//    
//    Bei Doppelbelegungen wird erster Treffer genommen
//
//
//Deadkeys
// Nachfolgend Tafeln für die diakritschen Zeichen
// Kombinationen mit einem Diakritika und Compose mit 2 Zeichen. Der Rest ist im Deuschen selten 
// und lässt sich über das Combiningzeichen (nachgestellt) bilden
// Mehrfachfunktionen siehe: http://wiki.neo-layout.org/wiki/Diakritika#DoppelfunktionToterTasten
//
// =========================================================================
// TASTE 1: ZIRKUMFLEX, HATSCHEK, DREHEN, PUNKT DRÜBER, HAKEN, PUNKT DRUNTER
// Zirkumflex und Superscript (ferfig für en_US.UTF-8 und lang.module)
DEADTRANS(L'^'   , space   , L'^'   , 0x0000), //Zirkumflex
DEADTRANS(L'^'   , L'^'   , 0x0302 , 0x0000), //2x für Combining
DEADTRANS(L'^'   , L'A'   , 0x00c2 , 0x0000),
DEADTRANS(L'^'   , L'a'   , 0x00e2 , 0x0000),
DEADTRANS(L'^'   , L'C'   , 0x0108 , 0x0000),
DEADTRANS(L'^'   , L'c'   , 0x0109 , 0x0000),
DEADTRANS(L'^'   , L'E'   , 0x00ca , 0x0000),
DEADTRANS(L'^'   , L'e'   , 0x00ea , 0x0000),
DEADTRANS(L'^'   , L'G'   , 0x011c , 0x0000),
DEADTRANS(L'^'   , L'g'   , 0x011d , 0x0000),
DEADTRANS(L'^'   , L'H'   , 0x0124 , 0x0000),
DEADTRANS(L'^'   , L'h'   , 0x0125 , 0x0000),
DEADTRANS(L'^'   , L'I'   , 0x00ce , 0x0000),
DEADTRANS(L'^'   , L'i'   , 0x00ee , 0x0000),
DEADTRANS(L'^'   , L'J'   , 0x0134 , 0x0000),
DEADTRANS(L'^'   , L'j'   , 0x0135 , 0x0000),
DEADTRANS(L'^'   , L'O'   , 0x00d4 , 0x0000),
DEADTRANS(L'^'   , L'o'   , 0x00f4 , 0x0000),
DEADTRANS(L'^'   , L'S'   , 0x015c , 0x0000),
DEADTRANS(L'^'   , L's'   , 0x015d , 0x0000),
DEADTRANS(L'^'   , L'U'   , 0x00db , 0x0000),
DEADTRANS(L'^'   , L'u'   , 0x00fb , 0x0000),
DEADTRANS(L'^'   , L'W'   , 0x0174 , 0x0000),
DEADTRANS(L'^'   , L'w'   , 0x0175 , 0x0000),
DEADTRANS(L'^'   , L'Y'   , 0x0176 , 0x0000),
DEADTRANS(L'^'   , L'y'   , 0x0177 , 0x0000),
DEADTRANS(L'^'   , L'Z'   , 0x1e90 , 0x0000),
DEADTRANS(L'^'   , L'z'   , 0x1e91 , 0x0000),
DEADTRANS(L'^'   , L'?'   , 0x02c0 , 0x0000), // ab hier lang.module 
DEADTRANS(L'^'   , multiply , 0x02c0 , 0x0000),
DEADTRANS(L'^'   , Greek_alpha , 0x1d45 , 0x0000), //Greek_alpha  
DEADTRANS(L'^'   , Greek_epsilon , 0x1d4b , 0x0000), //Greek_epsilon
DEADTRANS(L'^'   , Greek_upsilon , 0x1db7 , 0x0000), //Greek_upsilon
DEADTRANS(L'^'   , scriptphi , 0x1db2 , 0x0000), // Ende lang.module
DEADTRANS(L'^'   , L'1'   , onesuperior , 0x0000), //ab hier hochgestelltes
DEADTRANS(L'^'   , L'2'   , twosuperior , 0x0000),
DEADTRANS(L'^'   , L'3'   , threesuperior , 0x0000),
DEADTRANS(L'^'   , L'4'   , 0x2074 , 0x0000),
DEADTRANS(L'^'   , L'5'   , 0x2075 , 0x0000),
DEADTRANS(L'^'   , L'6'   , 0x2076 , 0x0000),
DEADTRANS(L'^'   , L'7'   , 0x2077 , 0x0000),
DEADTRANS(L'^'   , L'8'   , 0x2078 , 0x0000),
DEADTRANS(L'^'   , L'9'   , 0x2079 , 0x0000),
DEADTRANS(L'^'   , L'0'   , 0x2070 , 0x0000),
DEADTRANS(L'^'   , L'+'   , 0x207a , 0x0000),
DEADTRANS(L'^'   , L'-'   , 0x207b , 0x0000),
DEADTRANS(L'^'   , L'='   , 0x207c , 0x0000),
DEADTRANS(L'^'   , L'('   , 0x207d , 0x0000),
DEADTRANS(L'^'   , L')'   , 0x207e , 0x0000),
DEADTRANS(L'^'   , L'n'   , 0x207f , 0x0000),

//Caron (ferfig für en_US.UTF-8 und lang.module)
DEADTRANS(caron , space   , caron , 0x0000), //Caron 
DEADTRANS(caron , caron , 0x030C , 0x0000), //2x für Combining
DEADTRANS(caron , L'A'   , 0x01CD , 0x0000),
DEADTRANS(caron , L'a'   , 0x01CE , 0x0000),
DEADTRANS(caron , L'C'   , 0x010c , 0x0000),
DEADTRANS(caron , L'c'   , 0x010d , 0x0000),
DEADTRANS(caron , L'D'   , 0x010e , 0x0000),
DEADTRANS(caron , L'd'   , 0x010f , 0x0000),
DEADTRANS(caron , L'E'   , 0x011a , 0x0000),
DEADTRANS(caron , L'e'   , 0x011b , 0x0000),
DEADTRANS(caron , L'G'   , 0x01e6 , 0x0000),
DEADTRANS(caron , L'g'   , 0x01e7 , 0x0000),
DEADTRANS(caron , L'H'   , 0x021e , 0x0000),
DEADTRANS(caron , L'h'   , 0x021f , 0x0000),
DEADTRANS(caron , L'I'   , 0x01cf , 0x0000),
DEADTRANS(caron , L'i'   , 0x01d0 , 0x0000),
DEADTRANS(caron , L'j'   , 0x01f0 , 0x0000),
DEADTRANS(caron , L'K'   , 0x01e8 , 0x0000),
DEADTRANS(caron , L'k'   , 0x01e9 , 0x0000),
DEADTRANS(caron , L'L'   , 0x013d , 0x0000),
DEADTRANS(caron , L'l'   , 0x013e , 0x0000),
DEADTRANS(caron , L'N'   , 0x0147 , 0x0000),
DEADTRANS(caron , L'n'   , 0x0148 , 0x0000),
DEADTRANS(caron , L'O'   , 0x01d1 , 0x0000),
DEADTRANS(caron , L'o'   , 0x01d2 , 0x0000),
DEADTRANS(caron , L'R'   , 0x0158 , 0x0000),
DEADTRANS(caron , L'r'   , 0x0159 , 0x0000),
DEADTRANS(caron , L'S'   , 0x0160 , 0x0000),
DEADTRANS(caron , L's'   , 0x0161 , 0x0000),
DEADTRANS(caron , L'T'   , 0x0164 , 0x0000),
DEADTRANS(caron , L't'   , 0x0165 , 0x0000),
DEADTRANS(caron , L'U'   , 0x01d3 , 0x0000),
DEADTRANS(caron , L'u'   , 0x01d4 , 0x0000),
DEADTRANS(caron , udiaeresis , 0x01da , 0x0000), // Ü
DEADTRANS(caron , Udiaeresis , 0x01d9 , 0x0000), // ü
DEADTRANS(caron , L'Z'   , 0x017d , 0x0000),
DEADTRANS(caron , L'z'   , 0x017e , 0x0000),
DEADTRANS(caron , L'1'   , onesubscript , 0x0000), // tiefgestellt
DEADTRANS(caron , L'2'   , twosubscript , 0x0000),
DEADTRANS(caron , L'3'   , threesubscript , 0x0000),
DEADTRANS(caron , L'4'   , 0x2084 , 0x0000),
DEADTRANS(caron , L'5'   , 0x2085 , 0x0000),
DEADTRANS(caron , L'6'   , 0x2086 , 0x0000),
DEADTRANS(caron , L'7'   , 0x2087 , 0x0000),
DEADTRANS(caron , L'8'   , 0x2088 , 0x0000),
DEADTRANS(caron , L'9'   , 0x2089 , 0x0000),
DEADTRANS(caron , L'0'   , zerosubscript , 0x0000),
DEADTRANS(caron , L'+'   , 0x208a , 0x0000),
DEADTRANS(caron , L'-'   , 0x208b , 0x0000),
DEADTRANS(caron , L'='   , 0x208c , 0x0000),
DEADTRANS(caron , L'('   , 0x208d , 0x0000),
DEADTRANS(caron , L')'   , 0x208e , 0x0000),
DEADTRANS(caron , L'x'   , 0x2093 , 0x0000), // Ende tiefgestellt
// ENDE TASTE 1
// =====================================================================
// =====================================================================
// TASTE 2: GRAVIS, CEDILLE, RING, TREMA, OGONEK, MAKRON
// Gravis (ferfig für en_US.UTF-8 und lang.module)
DEADTRANS(grave, space, grave, 0x0000),	//Gravis
DEADTRANS(grave, grave, 0x0300, 0x0000),	//2x für Combining
DEADTRANS(grave, L'a', 0x00e0, 0x0000),
DEADTRANS(grave, L'A', 0x00c0, 0x0000),
DEADTRANS(grave, L'E', 0x00c8, 0x0000),
DEADTRANS(grave, L'e', 0x00e8, 0x0000),
DEADTRANS(grave, L'I', 0x00cc, 0x0000),
DEADTRANS(grave, L'i', 0x00ec, 0x0000),
DEADTRANS(grave, L'N', 0x01f8, 0x0000),
DEADTRANS(grave, L'n', 0x01f9, 0x0000),
DEADTRANS(grave, L'O', 0x00d2, 0x0000),
DEADTRANS(grave, L'o', 0x00f2, 0x0000),
DEADTRANS(grave, L'U', 0x00d9, 0x0000),
DEADTRANS(grave, L'u', 0x00f9, 0x0000),
DEADTRANS(grave, L'W', 0x1e80, 0x0000),
DEADTRANS(grave, L'w', 0x1e81, 0x0000),
DEADTRANS(grave, L'Y', 0x1ef2, 0x0000),
DEADTRANS(grave, L'y', 0x1ef3, 0x0000),
DEADTRANS(grave, Udiaeresis, 0x01db, 0x0000),	//Ü
DEADTRANS(grave, udiaeresis, 0x01dc, 0x0000),	//ü

//Cedille (ferfig für en_US.UTF-8 und lang.module)
DEADTRANS(cedilla, space, cedilla, 0x0000),	//Cedille
DEADTRANS(cedilla, cedilla, 0x0327, 0x0000),	 //2x für Combining
DEADTRANS(cedilla, L'C', 0x00c7, 0x0000),
DEADTRANS(cedilla, L'c', 0x00e7, 0x0000),
DEADTRANS(cedilla, L'D', 0x1e10, 0x0000),
DEADTRANS(cedilla, L'd', 0x1e11, 0x0000),
DEADTRANS(cedilla, L'G', 0x0122, 0x0000),
DEADTRANS(cedilla, L'g', 0x0123, 0x0000),
DEADTRANS(cedilla, L'H', 0x1e28, 0x0000),
DEADTRANS(cedilla, L'h', 0x1e29, 0x0000),
DEADTRANS(cedilla, L'K', 0x0136, 0x0000),
DEADTRANS(cedilla, L'k', 0x0137, 0x0000),
DEADTRANS(cedilla, L'L', 0x013b, 0x0000),
DEADTRANS(cedilla, L'l', 0x013c, 0x0000),
DEADTRANS(cedilla, L'N', 0x0145, 0x0000),
DEADTRANS(cedilla, L'n', 0x0146, 0x0000),
DEADTRANS(cedilla, L'R', 0x0156, 0x0000),
DEADTRANS(cedilla, L'r', 0x0157, 0x0000),
DEADTRANS(cedilla, L'S', 0x015e, 0x0000),
DEADTRANS(cedilla, L's', 0x015f, 0x0000),
DEADTRANS(cedilla, L'T', 0x0162, 0x0000),
DEADTRANS(cedilla, L't', 0x0163, 0x0000),
DEADTRANS(cedilla, L'A', 0x0104, 0x0000),	//Ogonek
DEADTRANS(cedilla, L'a', 0x0105, 0x0000),
DEADTRANS(cedilla, L'E', 0x0118, 0x0000),
DEADTRANS(cedilla, L'e', 0x0119, 0x0000),
DEADTRANS(cedilla, L'I', 0x012e, 0x0000),
DEADTRANS(cedilla, L'i', 0x012f, 0x0000),
DEADTRANS(cedilla, L'O', 0x01ea, 0x0000),
DEADTRANS(cedilla, L'o', 0x01eb, 0x0000),
DEADTRANS(cedilla, L'U', 0x0172, 0x0000),
DEADTRANS(cedilla, L'u', 0x0173, 0x0000),
// ENDE TASTE 2
// =====================================================================
// =====================================================================
// TASTE 3: AKUT, TILDE, QUERSTRICH, DOPPELAKUT, OGONEK, BREVE
// Akut (ferfig für en_US.UTF-8 und lang.module)
DEADTRANS(acute, space, acute, 0x0000),	//Akut
DEADTRANS(acute, acute, 0x0301, 0x0000),	//2x für Combining
DEADTRANS(acute, L'A', 0x00c1, 0x0000),
DEADTRANS(acute, L'a', 0x00e1, 0x0000),
DEADTRANS(acute, L'C', 0x0106, 0x0000),
DEADTRANS(acute, L'c', 0x0107, 0x0000),
DEADTRANS(acute, L'E', 0x00c9, 0x0000),
DEADTRANS(acute, L'e', 0x00e9, 0x0000),
DEADTRANS(acute, L'G', 0x01f4, 0x0000),
DEADTRANS(acute, L'g', 0x01f5, 0x0000),
DEADTRANS(acute, L'I', 0x00cd, 0x0000),
DEADTRANS(acute, L'i', 0x00ed, 0x0000),
DEADTRANS(acute, L'K', 0x1e30, 0x0000),
DEADTRANS(acute, L'k', 0x1e31, 0x0000),
DEADTRANS(acute, L'L', 0x0139, 0x0000),
DEADTRANS(acute, L'l', 0x013a, 0x0000),
DEADTRANS(acute, L'M', 0x1e3e, 0x0000),
DEADTRANS(acute, L'm', 0x1e3f, 0x0000),
DEADTRANS(acute, L'N', 0x0143, 0x0000),
DEADTRANS(acute, L'n', 0x0144, 0x0000),
DEADTRANS(acute, L'O', 0x00d3, 0x0000),
DEADTRANS(acute, L'o', 0x00f3, 0x0000),
DEADTRANS(acute, L'P', 0x1e54, 0x0000),
DEADTRANS(acute, L'p', 0x1e55, 0x0000),
DEADTRANS(acute, L'R', 0x0154, 0x0000),
DEADTRANS(acute, L'r', 0x0155, 0x0000),
DEADTRANS(acute, L'S', 0x015a, 0x0000),
DEADTRANS(acute, L's', 0x015b, 0x0000),
DEADTRANS(acute, L'U', 0x00da, 0x0000),
DEADTRANS(acute, L'u', 0x00fa, 0x0000),
DEADTRANS(acute, L'W', 0x1e82, 0x0000),
DEADTRANS(acute, L'w', 0x1e83, 0x0000),
DEADTRANS(acute, L'Y', 0x00dd, 0x0000),
DEADTRANS(acute, L'y', 0x00fd, 0x0000),
DEADTRANS(acute, L'Z', 0x0179, 0x0000),
DEADTRANS(acute, L'z', 0x017a, 0x0000),
DEADTRANS(acute, Udiaeresis, 0x01d7, 0x0000),	//Ü
DEADTRANS(acute, udiaeresis, 0x01d8, 0x0000),	//ü
DEADTRANS(acute, 0x00c6, 0x01fc, 0x0000),	//Æ
DEADTRANS(acute, 0x00e6, 0x01fd, 0x0000),	//æ

// Tilde  (ferfig für en_US.UTF-8 und lang.module)
DEADTRANS(L'~', space, L'~', 0x0000), //Tilde
DEADTRANS(L'~', L'~', 0x0303, 0x0000), //2x für Combining
DEADTRANS(L'~', L'A', 0x00c3, 0x0000),
DEADTRANS(L'~', L'a', 0x00e3, 0x0000),
DEADTRANS(L'~', L'E', 0x1ebc, 0x0000),
DEADTRANS(L'~', L'e', 0x1ebd, 0x0000),
DEADTRANS(L'~', L'I', 0x0128, 0x0000),
DEADTRANS(L'~', L'i', 0x0129, 0x0000),
DEADTRANS(L'~', L'N', 0x00d1, 0x0000),
DEADTRANS(L'~', L'n', 0x00f1, 0x0000),
DEADTRANS(L'~', L'O', 0x00d5, 0x0000),
DEADTRANS(L'~', L'o', 0x00f5, 0x0000),
DEADTRANS(L'~', L'U', 0x0168, 0x0000),
DEADTRANS(L'~', L'u', 0x0169, 0x0000),
DEADTRANS(L'~', L'V', 0x1e7c, 0x0000),
DEADTRANS(L'~', L'v', 0x1e7d, 0x0000),
DEADTRANS(L'~', L'Y', 0x1ef8, 0x0000),
DEADTRANS(L'~', L'y', 0x1ef9, 0x0000),
// ENDE TASTE 3
// =====================================================================
    0, 0
};


static ALLOC_SECTION_LDATA KBDTABLES KbdTables = {
// Modifier keys
    &CharModifiers,

	
// Characters tables
    aVkToWcharTable,

	
// Diakritika vorhanden
    aDeadKey,

	
// Namen der Keys
    aKeyNames,
    aKeyNamesExt,
    aKeyNamesDead,

	
// Scancodes zu Virtual Keys
    ausVK,
    sizeof(ausVK) / sizeof(ausVK[0]),
    aE0VscToVk,
    aE1VscToVk,

	
// Kein Rechtes Alt daher AltGr auskommentiert
//   MAKELONG(KLLF_ALTGR, KBD_VERSION),
    0,
	
// keine Ligaturen
    0,
    0,
    NULL
};


PKBDTABLES KbdLayerDescriptor(VOID)
{
    return &KbdTables;
}
