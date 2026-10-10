#pragma once

#include "MinHook.h"
#include "hde64.h"

#pragma pack(push, 1)

// Structs for instruction encoding
typedef struct _JMP_REL
{
    BYTE  opcode;
    DWORD operand;
} JMP_REL, *PJMP_REL;

typedef struct _JMP_ABS
{
    BYTE  opcode0;
    BYTE  opcode1;
    DWORD dummy;
    ULONG_PTR address;
} JMP_ABS, *PJMP_ABS;

typedef struct _CALL_ABS
{
    BYTE  opcode0;
    BYTE  opcode1;
    DWORD dummy;
    ULONG_PTR address;
} CALL_ABS;

typedef struct _JCC_REL
{
    BYTE  opcode0;
    BYTE  opcode1;
    DWORD operand;
} JCC_REL;

typedef struct _JCC_ABS
{
    BYTE  opcode;
    BYTE  dummy0;
    BYTE  dummy1;
    BYTE  dummy2;
    WORD  dummy3;
    BYTE  dummy4;
    BYTE  dummy5;
    DWORD dummy6;
    ULONG_PTR address;
} JCC_ABS;

#pragma pack(pop)

typedef struct _TRAMPOLINE
{
    LPVOID pTarget;
    LPVOID pDetour;
    LPVOID pTrampoline;
    LPVOID pRelay;
    BOOL   patchAbove;
    UINT   nIP;
    BYTE   oldIPs[8];
    BYTE   newIPs[8];
} TRAMPOLINE, *PTRAMPOLINE;

#ifdef __cplusplus
extern "C" {
#endif

BOOL CreateTrampolineFunction(PTRAMPOLINE ct);

#ifdef __cplusplus
}
#endif
