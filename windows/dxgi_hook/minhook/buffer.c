#include "buffer.h"
#include <windows.h>

#define MEMORY_BLOCK_SIZE 0x10000
#define MAX_MEMORY_RANGE 0x20000000

typedef struct _MEMORY_SLOT
{
    union
    {
        struct _MEMORY_SLOT *pNext;
        BYTE buffer[MEMORY_SLOT_SIZE];
    };
} MEMORY_SLOT, *PMEMORY_SLOT;

typedef struct _MEMORY_BLOCK
{
    struct _MEMORY_BLOCK *pNext;
    PMEMORY_SLOT pFree;
    UINT usedCount;
} MEMORY_BLOCK, *PMEMORY_BLOCK;

static PMEMORY_BLOCK g_pMemoryBlocks = NULL;

VOID InitializeBuffer(VOID)
{
    g_pMemoryBlocks = NULL;
}

VOID UninitializeBuffer(VOID)
{
    PMEMORY_BLOCK pBlock = g_pMemoryBlocks;
    while (pBlock)
    {
        PMEMORY_BLOCK pNext = pBlock->pNext;
        VirtualFree(pBlock, 0, MEM_RELEASE);
        pBlock = pNext;
    }
    g_pMemoryBlocks = NULL;
}

static PMEMORY_BLOCK CreateMemoryBlock(LPVOID pOrigin)
{
    PMEMORY_BLOCK pBlock = NULL;
    ULONG_PTR minAddr = (ULONG_PTR)pOrigin > MAX_MEMORY_RANGE ? (ULONG_PTR)pOrigin - MAX_MEMORY_RANGE : 0x10000;
    ULONG_PTR maxAddr = (ULONG_PTR)pOrigin + MAX_MEMORY_RANGE;

    SYSTEM_INFO si;
    GetSystemInfo(&si);
    minAddr = max(minAddr, (ULONG_PTR)si.lpMinimumApplicationAddress);
    maxAddr = min(maxAddr, (ULONG_PTR)si.lpMaximumApplicationAddress);

    ULONG_PTR addr = (ULONG_PTR)pOrigin & ~(ULONG_PTR)0xFFFF;
    while (addr >= minAddr)
    {
        pBlock = (PMEMORY_BLOCK)VirtualAlloc((LPVOID)addr, MEMORY_BLOCK_SIZE, MEM_COMMIT | MEM_RESERVE, PAGE_EXECUTE_READWRITE);
        if (pBlock) break;
        if (addr < MEMORY_BLOCK_SIZE) break;
        addr -= MEMORY_BLOCK_SIZE;
    }
    if (!pBlock)
    {
        addr = ((ULONG_PTR)pOrigin & ~(ULONG_PTR)0xFFFF) + MEMORY_BLOCK_SIZE;
        while (addr <= maxAddr)
        {
            pBlock = (PMEMORY_BLOCK)VirtualAlloc((LPVOID)addr, MEMORY_BLOCK_SIZE, MEM_COMMIT | MEM_RESERVE, PAGE_EXECUTE_READWRITE);
            if (pBlock) break;
            addr += MEMORY_BLOCK_SIZE;
        }
    }
    if (!pBlock)
    {
        pBlock = (PMEMORY_BLOCK)VirtualAlloc(NULL, MEMORY_BLOCK_SIZE, MEM_COMMIT | MEM_RESERVE, PAGE_EXECUTE_READWRITE);
    }
    if (pBlock)
    {
        PMEMORY_SLOT pSlot = (PMEMORY_SLOT)((LPBYTE)pBlock + sizeof(MEMORY_BLOCK));
        pBlock->pFree = pSlot;
        pBlock->usedCount = 0;
        pBlock->pNext = g_pMemoryBlocks;
        g_pMemoryBlocks = pBlock;

        UINT totalSlots = (MEMORY_BLOCK_SIZE - sizeof(MEMORY_BLOCK)) / sizeof(MEMORY_SLOT);
        for (UINT i = 0; i < totalSlots - 1; ++i)
        {
            pSlot->pNext = (PMEMORY_SLOT)((LPBYTE)pSlot + sizeof(MEMORY_SLOT));
            pSlot = pSlot->pNext;
        }
        pSlot->pNext = NULL;
    }
    return pBlock;
}

LPVOID AllocateBuffer(LPVOID pOrigin)
{
    PMEMORY_BLOCK pBlock = g_pMemoryBlocks;
    while (pBlock)
    {
        if (pBlock->pFree)
        {
            PMEMORY_SLOT pSlot = pBlock->pFree;
            pBlock->pFree = pSlot->pNext;
            pBlock->usedCount++;
            return pSlot;
        }
        pBlock = pBlock->pNext;
    }
    pBlock = CreateMemoryBlock(pOrigin);
    if (pBlock && pBlock->pFree)
    {
        PMEMORY_SLOT pSlot = pBlock->pFree;
        pBlock->pFree = pSlot->pNext;
        pBlock->usedCount++;
        return pSlot;
    }
    return NULL;
}

VOID FreeBuffer(LPVOID pBuffer)
{
    PMEMORY_BLOCK pBlock = g_pMemoryBlocks;
    while (pBlock)
    {
        if (pBuffer >= (LPVOID)pBlock && pBuffer < (LPVOID)((LPBYTE)pBlock + MEMORY_BLOCK_SIZE))
        {
            PMEMORY_SLOT pSlot = (PMEMORY_SLOT)pBuffer;
            pSlot->pNext = pBlock->pFree;
            pBlock->pFree = pSlot;
            pBlock->usedCount--;
            return;
        }
        pBlock = pBlock->pNext;
    }
}

BOOL IsExecutableAddress(LPVOID pAddress)
{
    MEMORY_BASIC_INFORMATION mbi;
    if (VirtualQuery(pAddress, &mbi, sizeof(mbi)))
    {
        return (mbi.State == MEM_COMMIT &&
               (mbi.Protect & (PAGE_EXECUTE | PAGE_EXECUTE_READ | PAGE_EXECUTE_READWRITE | PAGE_EXECUTE_WRITECOPY)));
    }
    return FALSE;
}
