#include "hde64.h"
#include "table64.h"
#include <string.h>

static const uint8_t hde64_table[] = { HDE64_TABLE };

unsigned int hde64_disasm(const void *code, hde64s *hs)
{
    uint8_t x, c, *p = (uint8_t *)code, cflags, opcode, pref = 0;
    uint8_t *ht = (uint8_t *)hde64_table;
    uint8_t m_mod, m_reg, m_rm, disp_size = 0;
    uint8_t op64 = 0;

    memset(hs, 0, sizeof(hde64s));

    for (x = 16; x; x--) {
        switch (c = *p++) {
            case 0xf3:
                hs->p_rep = c;
                pref |= PRE_F3;
                break;
            case 0xf2:
                hs->p_rep = c;
                pref |= PRE_F2;
                break;
            case 0xf0:
                hs->p_lock = c;
                pref |= PRE_LOCK;
                break;
            case 0x26: case 0x2e: case 0x36:
            case 0x3e: case 0x64: case 0x65:
                hs->p_seg = c;
                pref |= PRE_SEG;
                break;
            case 0x66:
                hs->p_66 = c;
                pref |= PRE_66;
                break;
            case 0x67:
                hs->p_67 = c;
                pref |= PRE_67;
                break;
            default:
                goto no_more_prefixes;
        }
    }
    goto error;

no_more_prefixes:
    if ((c & 0xf0) == 0x40) {
        hs->rex = c;
        hs->rex_b = c & 0x01;
        hs->rex_x = (c & 0x02) >> 1;
        hs->rex_r = (c & 0x04) >> 2;
        hs->rex_w = (c & 0x08) >> 3;
        c = *p++;
    }

    hs->opcode = c;
    opcode = c;

    if (c == 0x0f) {
        hs->opcode2 = c = *p++;
        ht += DELTA_OPCODES;
    } else if (c >= 0xa0 && c <= 0xa3) {
        op64 = 1;
        if (pref & PRE_67)
            pref |= PRE_66;
        else
            pref &= ~PRE_66;
    }

    cflags = ht[c >> 2];
    cflags = (cflags >> ((c & 3) << 1)) & 3;

    if (cflags == 3) {
        ht += 128;
        cflags = ht[c >> 2];
        cflags = (cflags >> ((c & 3) << 1)) & 3;
        if (cflags == 3) goto error;
    }

    if (cflags & 2) {
        if (cflags & 1) {
            if (hs->opcode == 0x0f) goto error;
            if (opcode >= 0xd8 && opcode <= 0xdf) {
                uint8_t *t = (uint8_t *)hde64_table + DELTA_FPU_MODRM + (opcode - 0xd8);
                c = *p++;
                if (c >= 0xc0) {
                    t += DELTA_FPU_REG - DELTA_FPU_MODRM;
                }
                cflags = *t;
                goto no_modrm;
            }
        }
        c = *p++;
        hs->modrm = c;
        hs->modrm_mod = m_mod = c >> 6;
        hs->modrm_reg = m_reg = (c >> 3) & 7;
        hs->modrm_rm  = m_rm  = c & 7;

        if (c <= 0x3f) {
            if (m_rm == 4) {
                hs->flags |= F_SIB;
                c = *p++;
                hs->sib = c;
                hs->sib_scale = c >> 6;
                hs->sib_index = (c >> 3) & 7;
                hs->sib_base  = c & 7;
                if (hs->sib_base == 5) {
                    if (m_mod == 0) disp_size = 4;
                }
            } else if (m_rm == 5) {
                disp_size = 4;
                if (m_mod == 0) hs->flags |= F_RELATIVE;
            }
        } else if (c <= 0x7f) {
            disp_size = 1;
            if (m_rm == 4) {
                hs->flags |= F_SIB;
                c = *p++;
                hs->sib = c;
                hs->sib_scale = c >> 6;
                hs->sib_index = (c >> 3) & 7;
                hs->sib_base  = c & 7;
            }
        } else if (c <= 0xbf) {
            disp_size = 4;
            if (m_rm == 4) {
                hs->flags |= F_SIB;
                c = *p++;
                hs->sib = c;
                hs->sib_scale = c >> 6;
                hs->sib_index = (c >> 3) & 7;
                hs->sib_base  = c & 7;
            }
        }
    }

no_modrm:
    if (disp_size) {
        if (disp_size == 1) {
            hs->flags |= F_DISP8;
            hs->disp.disp8 = *p++;
        } else {
            hs->flags |= F_DISP32;
            hs->disp.disp32 = *(uint32_t *)p;
            p += 4;
        }
    }

    if (cflags & 1) {
        if (hs->opcode == 0x0f) {
            if (hs->opcode2 == 0x78 || hs->opcode2 == 0x79) {
                hs->flags |= F_IMM8;
                hs->imm.imm8 = *p++;
            }
        } else if (opcode == 0xc8) {
            hs->flags |= F_IMM16;
            hs->imm.imm16 = *(uint16_t *)p;
            p += 2;
            hs->flags |= F_IMM8;
            hs->imm.imm8 = *p++;
        } else if ((opcode & 0xf8) == 0xb8) {
            if (hs->rex_w) {
                hs->flags |= F_IMM64;
                hs->imm.imm64 = *(uint64_t *)p;
                p += 8;
            } else if (pref & PRE_66) {
                hs->flags |= F_IMM16;
                hs->imm.imm16 = *(uint16_t *)p;
                p += 2;
            } else {
                hs->flags |= F_IMM32;
                hs->imm.imm32 = *(uint32_t *)p;
                p += 4;
            }
        } else if ((opcode & 0xf0) == 0x70 || (opcode & 0xfc) == 0xe0 || opcode == 0xeb) {
            hs->flags |= F_IMM8 | F_RELATIVE;
            hs->imm.imm8 = *p++;
        } else if (opcode == 0xe8 || opcode == 0xe9) {
            hs->flags |= F_IMM32 | F_RELATIVE;
            hs->imm.imm32 = *(uint32_t *)p;
            p += 4;
        } else if ((opcode & 0xf8) == 0xb0 || opcode == 0x04 || opcode == 0x0c ||
                   opcode == 0x14 || opcode == 0x1c || opcode == 0x24 ||
                   opcode == 0x2c || opcode == 0x34 || opcode == 0x3c ||
                   opcode == 0xa8 || opcode == 0xcd || opcode == 0xd4 ||
                   opcode == 0xd5 || opcode == 0x6a) {
            hs->flags |= F_IMM8;
            hs->imm.imm8 = *p++;
        } else if (opcode == 0xc2 || opcode == 0xca) {
            hs->flags |= F_IMM16;
            hs->imm.imm16 = *(uint16_t *)p;
            p += 2;
        } else {
            if (pref & PRE_66) {
                hs->flags |= F_IMM16;
                hs->imm.imm16 = *(uint16_t *)p;
                p += 2;
            } else {
                hs->flags |= F_IMM32;
                hs->imm.imm32 = *(uint32_t *)p;
                p += 4;
            }
        }
    }

    hs->len = (uint8_t)(p - (uint8_t *)code);
    return hs->len;

error:
    hs->flags |= F_ERROR;
    hs->len = 0;
    return 0;
}
