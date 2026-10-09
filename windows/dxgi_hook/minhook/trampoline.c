#include "trampoline.h"
#include "buffer.h"
#include <string.h>

#define MEMORY_SLOT_SIZE 64

static BOOL IsCodePadding(LPBYTE pCode, UINT size)
{
    BYTE b = pCode[0];
    if (b != 0x00 && b != 0x90 && b != 0xCC)
        return FALSE;

    for (UINT i = 1; i < size; ++i)
    {
        if (pCode[i] != b)
            return FALSE;
    }
    return TRUE;
}

BOOL CreateTrampolineFunction(PTRAMPOLINE ct)
{
    CALL_ABS call = { 0xFF, 0x15, 0x00000000, 0x0000000000000000ULL };
    JMP_ABS  jmp  = { 0xFF, 0x25, 0x00000000, 0x0000000000000000ULL };
    JCC_ABS  jcc  = { 0x70, 0x0E, 0xFF, 0x25, 0x0000, 0x00, 0x00, 0x00000000, 0x0000000000000000ULL };

    UINT8     oldPos = 0;
    UINT8     newPos = 0;
    ULONG_PTR jmpDest = 0;
    BOOL      finished = FALSE;

    ct->patchAbove = FALSE;
    ct->nIP        = 0;

    do
    {
        hde64s hs;
        UINT   copySize;
        LPVOID pCopySrc;
        ULONG_PTR pOldInst = (ULONG_PTR)ct->pTarget + oldPos;
        ULONG_PTR pNewInst = (ULONG_PTR)ct->pTrampoline + newPos;

        copySize = hde64_disasm((LPVOID)pOldInst, &hs);
        if (hs.flags & F_ERROR)
            return FALSE;

        pCopySrc = (LPVOID)pOldInst;
        if (oldPos >= sizeof(JMP_REL))
        {
            jmp.address = pOldInst;
            pCopySrc = &jmp;
            copySize = sizeof(jmp);
            finished = TRUE;
        }
        else if ((hs.modrm & 0xC7) == 0x05)
        {
            // RIP-relative addressing
            PUCHAR pInst = (PUCHAR)pOldInst;
            PUCHAR pDest = (PUCHAR)pNewInst;
            memcpy(pDest, pInst, copySize);

            // Correct displacement
            *(PLONG)(pDest + (hs.disp.disp32 - (ULONG_PTR)pInst)) =
                (LONG)((pOldInst + hs.len + (LONG)hs.disp.disp32) - (pNewInst + hs.len));

            pCopySrc = pDest;
        }
        else if (hs.opcode == 0xE8)
        {
            // Direct CALL
            ULONG_PTR dest = pOldInst + hs.len + (INT32)hs.imm.imm32;
            call.address = dest;
            pCopySrc = &call;
            copySize = sizeof(call);
        }
        else if ((hs.opcode & 0xFD) == 0xE9)
        {
            // Direct JMP
            ULONG_PTR dest = pOldInst + hs.len;
            if (hs.opcode == 0xEB) // 8-bit relative
                dest += (INT8)hs.imm.imm8;
            else
                dest += (INT32)hs.imm.imm32;

            // Hook loop detection
            if ((ULONG_PTR)ct->pTarget <= dest && dest < ((ULONG_PTR)ct->pTarget + sizeof(JMP_REL)))
            {
                if (jmpDest < dest)
                    jmpDest = dest;
            }
            else
            {
                jmp.address = dest;
                pCopySrc = &jmp;
                copySize = sizeof(jmp);
            }
        }
        else if ((hs.opcode & 0xF0) == 0x70 || (hs.opcode2 & 0xF0) == 0x80)
        {
            // Direct Jcc
            ULONG_PTR dest = pOldInst + hs.len;
            if ((hs.opcode & 0xF0) == 0x70)
            {
                dest += (INT8)hs.imm.imm8;
                jcc.opcode = 0x70 | (hs.opcode & 0x0F);
            }
            else
            {
                dest += (INT32)hs.imm.imm32;
                jcc.opcode = 0x70 | (hs.opcode2 & 0x0F);
            }

            // Invert condition for JMP
            jcc.opcode ^= 0x01;
            jcc.address = dest;
            pCopySrc = &jcc;
            copySize = sizeof(jcc);
        }
        else if ((hs.opcode & 0xFE) == 0xC2)
        {
            // RET
            finished = (oldPos >= sizeof(JMP_REL));
        }

        // Check if buffer overflow
        if ((newPos + copySize) > (MEMORY_SLOT_SIZE - sizeof(JMP_ABS)))
            return FALSE;

        if (ct->nIP < (sizeof(ct->oldIPs) / sizeof(ct->oldIPs[0])))
        {
            ct->oldIPs[ct->nIP] = oldPos;
            ct->newIPs[ct->nIP] = newPos;
            ct->nIP++;
        }

        if (pCopySrc != (LPVOID)pNewInst)
        {
            memcpy((LPVOID)pNewInst, pCopySrc, copySize);
        }

        oldPos += hs.len;
        newPos += (UINT8)copySize;

        if (oldPos >= sizeof(JMP_REL) && !finished)
        {
            jmp.address = (ULONG_PTR)ct->pTarget + oldPos;
            memcpy((LPBYTE)ct->pTrampoline + newPos, &jmp, sizeof(jmp));
            newPos += sizeof(jmp);
            finished = TRUE;
        }

    } while (!finished);

    return TRUE;
}
