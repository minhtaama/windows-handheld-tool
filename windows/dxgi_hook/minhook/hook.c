#include "MinHook.h"
#include "buffer.h"
#include "trampoline.h"
#include <windows.h>
#include <tlhelp32.h>

typedef struct _HOOK_ENTRY
{
    LPVOID pTarget;
    LPVOID pDetour;
    LPVOID pTrampoline;
    BYTE   backup[8];
    BYTE   patch[8];
    BOOL   isEnabled;
    BOOL   queueEnable;
    UINT   nIP;
    BYTE   oldIPs[8];
    BYTE   newIPs[8];
} HOOK_ENTRY, *PHOOK_ENTRY;

static CRITICAL_SECTION g_cs;
static PHOOK_ENTRY      g_pHooks     = NULL;
static UINT             g_hooksCount = 0;
static UINT             g_hooksCap   = 0;
static BOOL             g_isInit     = FALSE;

static UINT FindHookEntry(LPVOID pTarget)
{
    for (UINT i = 0; i < g_hooksCount; ++i)
    {
        if (g_pHooks[i].pTarget == pTarget)
            return i;
    }
    return (UINT)-1;
}

static MH_STATUS EnableHookLL(UINT pos, BOOL enable)
{
    PHOOK_ENTRY pHook = &g_pHooks[pos];
    if (pHook->isEnabled == enable)
        return MH_OK;

    DWORD oldProtect;
    if (!VirtualProtect(pHook->pTarget, sizeof(JMP_REL), PAGE_EXECUTE_READWRITE, &oldProtect))
        return MH_ERROR_MEMORY_PROTECT;

    if (enable)
    {
        memcpy(pHook->pTarget, pHook->patch, sizeof(JMP_REL));
    }
    else
    {
        memcpy(pHook->pTarget, pHook->backup, sizeof(JMP_REL));
    }

    VirtualProtect(pHook->pTarget, sizeof(JMP_REL), oldProtect, &oldProtect);
    FlushInstructionCache(GetCurrentProcess(), pHook->pTarget, sizeof(JMP_REL));

    pHook->isEnabled = enable;
    return MH_OK;
}

MH_STATUS WINAPI MH_Initialize(VOID)
{
    if (g_isInit) return MH_ERROR_ALREADY_INITIALIZED;
    InitializeCriticalSection(&g_cs);
    InitializeBuffer();
    g_pHooks = NULL;
    g_hooksCount = 0;
    g_hooksCap = 0;
    g_isInit = TRUE;
    return MH_OK;
}

MH_STATUS WINAPI MH_Uninitialize(VOID)
{
    if (!g_isInit) return MH_ERROR_NOT_INITIALIZED;
    EnterCriticalSection(&g_cs);
    for (UINT i = 0; i < g_hooksCount; ++i)
    {
        if (g_pHooks[i].isEnabled)
            EnableHookLL(i, FALSE);
        if (g_pHooks[i].pTrampoline)
            FreeBuffer(g_pHooks[i].pTrampoline);
    }
    if (g_pHooks)
    {
        HeapFree(GetProcessHeap(), 0, g_pHooks);
        g_pHooks = NULL;
    }
    g_hooksCount = 0;
    g_hooksCap = 0;
    UninitializeBuffer();
    LeaveCriticalSection(&g_cs);
    DeleteCriticalSection(&g_cs);
    g_isInit = FALSE;
    return MH_OK;
}

MH_STATUS WINAPI MH_CreateHook(LPVOID pTarget, LPVOID pDetour, LPVOID *ppOriginal)
{
    if (!g_isInit) return MH_ERROR_NOT_INITIALIZED;
    if (!pTarget || !pDetour) return MH_ERROR_NOT_EXECUTABLE;
    if (!IsExecutableAddress(pTarget) || !IsExecutableAddress(pDetour)) return MH_ERROR_NOT_EXECUTABLE;

    EnterCriticalSection(&g_cs);

    if (FindHookEntry(pTarget) != (UINT)-1)
    {
        LeaveCriticalSection(&g_cs);
        return MH_ERROR_ALREADY_CREATED;
    }

    LPVOID pTrampoline = AllocateBuffer(pTarget);
    if (!pTrampoline)
    {
        LeaveCriticalSection(&g_cs);
        return MH_ERROR_MEMORY_ALLOC;
    }

    TRAMPOLINE ct;
    ct.pTarget     = pTarget;
    ct.pDetour     = pDetour;
    ct.pTrampoline = pTrampoline;

    if (!CreateTrampolineFunction(&ct))
    {
        FreeBuffer(pTrampoline);
        LeaveCriticalSection(&g_cs);
        return MH_ERROR_UNSUPPORTED_FUNCTION;
    }

    if (g_hooksCount >= g_hooksCap)
    {
        UINT newCap = g_hooksCap == 0 ? 16 : g_hooksCap * 2;
        PHOOK_ENTRY pNew = (PHOOK_ENTRY)HeapAlloc(GetProcessHeap(), HEAP_ZERO_MEMORY, newCap * sizeof(HOOK_ENTRY));
        if (!pNew)
        {
            FreeBuffer(pTrampoline);
            LeaveCriticalSection(&g_cs);
            return MH_ERROR_MEMORY_ALLOC;
        }
        if (g_pHooks)
        {
            memcpy(pNew, g_pHooks, g_hooksCount * sizeof(HOOK_ENTRY));
            HeapFree(GetProcessHeap(), 0, g_pHooks);
        }
        g_pHooks = pNew;
        g_hooksCap = newCap;
    }

    PHOOK_ENTRY pHook = &g_pHooks[g_hooksCount];
    pHook->pTarget     = pTarget;
    pHook->pDetour     = pDetour;
    pHook->pTrampoline = pTrampoline;
    pHook->isEnabled   = FALSE;

    memcpy(pHook->backup, pTarget, sizeof(JMP_REL));

    PJMP_REL pJmp = (PJMP_REL)pHook->patch;
    pJmp->opcode  = 0xE9;
    pJmp->operand = (DWORD)((ULONG_PTR)pDetour - ((ULONG_PTR)pTarget + sizeof(JMP_REL)));

    if (ppOriginal)
        *ppOriginal = pTrampoline;

    g_hooksCount++;
    LeaveCriticalSection(&g_cs);
    return MH_OK;
}

MH_STATUS WINAPI MH_CreateHookApi(LPCWSTR pszModule, LPCSTR pszProcName, LPVOID pDetour, LPVOID *ppOriginal)
{
    HMODULE hMod = GetModuleHandleW(pszModule);
    if (!hMod)
        hMod = LoadLibraryW(pszModule);
    if (!hMod)
        return MH_ERROR_MODULE_NOT_FOUND;

    FARPROC pProc = GetProcAddress(hMod, pszProcName);
    if (!pProc)
        return MH_ERROR_FUNCTION_NOT_FOUND;

    return MH_CreateHook((LPVOID)pProc, pDetour, ppOriginal);
}

MH_STATUS WINAPI MH_EnableHook(LPVOID pTarget)
{
    if (!g_isInit) return MH_ERROR_NOT_INITIALIZED;
    EnterCriticalSection(&g_cs);

    if (pTarget == MH_ALL_HOOKS)
    {
        for (UINT i = 0; i < g_hooksCount; ++i)
        {
            EnableHookLL(i, TRUE);
        }
        LeaveCriticalSection(&g_cs);
        return MH_OK;
    }

    UINT pos = FindHookEntry(pTarget);
    if (pos == (UINT)-1)
    {
        LeaveCriticalSection(&g_cs);
        return MH_ERROR_NOT_CREATED;
    }

    MH_STATUS status = EnableHookLL(pos, TRUE);
    LeaveCriticalSection(&g_cs);
    return status;
}

MH_STATUS WINAPI MH_DisableHook(LPVOID pTarget)
{
    if (!g_isInit) return MH_ERROR_NOT_INITIALIZED;
    EnterCriticalSection(&g_cs);

    if (pTarget == MH_ALL_HOOKS)
    {
        for (UINT i = 0; i < g_hooksCount; ++i)
        {
            EnableHookLL(i, FALSE);
        }
        LeaveCriticalSection(&g_cs);
        return MH_OK;
    }

    UINT pos = FindHookEntry(pTarget);
    if (pos == (UINT)-1)
    {
        LeaveCriticalSection(&g_cs);
        return MH_ERROR_NOT_CREATED;
    }

    MH_STATUS status = EnableHookLL(pos, FALSE);
    LeaveCriticalSection(&g_cs);
    return status;
}

MH_STATUS WINAPI MH_RemoveHook(LPVOID pTarget)
{
    if (!g_isInit) return MH_ERROR_NOT_INITIALIZED;
    EnterCriticalSection(&g_cs);

    UINT pos = FindHookEntry(pTarget);
    if (pos == (UINT)-1)
    {
        LeaveCriticalSection(&g_cs);
        return MH_ERROR_NOT_CREATED;
    }

    if (g_pHooks[pos].isEnabled)
        EnableHookLL(pos, FALSE);

    FreeBuffer(g_pHooks[pos].pTrampoline);

    if (pos < g_hooksCount - 1)
    {
        memcpy(&g_pHooks[pos], &g_pHooks[pos + 1], (g_hooksCount - pos - 1) * sizeof(HOOK_ENTRY));
    }
    g_hooksCount--;

    LeaveCriticalSection(&g_cs);
    return MH_OK;
}

const char * WINAPI MH_StatusToString(MH_STATUS status)
{
    switch (status)
    {
        case MH_UNKNOWN:                  return "MH_UNKNOWN";
        case MH_OK:                       return "MH_OK";
        case MH_ERROR_ALREADY_INITIALIZED:return "MH_ERROR_ALREADY_INITIALIZED";
        case MH_ERROR_NOT_INITIALIZED:    return "MH_ERROR_NOT_INITIALIZED";
        case MH_ERROR_ALREADY_CREATED:    return "MH_ERROR_ALREADY_CREATED";
        case MH_ERROR_NOT_CREATED:        return "MH_ERROR_NOT_CREATED";
        case MH_ERROR_ENABLED:            return "MH_ERROR_ENABLED";
        case MH_ERROR_DISABLED:           return "MH_ERROR_DISABLED";
        case MH_ERROR_NOT_EXECUTABLE:     return "MH_ERROR_NOT_EXECUTABLE";
        case MH_ERROR_UNSUPPORTED_FUNCTION:return "MH_ERROR_UNSUPPORTED_FUNCTION";
        case MH_ERROR_MEMORY_ALLOC:       return "MH_ERROR_MEMORY_ALLOC";
        case MH_ERROR_MEMORY_PROTECT:     return "MH_ERROR_MEMORY_PROTECT";
        case MH_ERROR_MODULE_NOT_FOUND:   return "MH_ERROR_MODULE_NOT_FOUND";
        case MH_ERROR_FUNCTION_NOT_FOUND: return "MH_ERROR_FUNCTION_NOT_FOUND";
        default:                          return "MH_UNKNOWN";
    }
}
