import struct, sys

PATH = '/root/fw-sp2/VD4224BDT_2.9.003.4.pkgtb'
d = open(PATH, 'rb').read()

FDT_BEGIN_NODE, FDT_END_NODE, FDT_PROP, FDT_NOP, FDT_END = 1, 2, 3, 4, 9


def dump(off, maxdepth=4):
    # fdt_header: magic totalsize off_dt_struct off_dt_strings off_mem_rsvmap
    #             version last_comp_version boot_cpuid_phys size_dt_strings size_dt_struct
    (magic, total, ofs, name_off, rs_off, version, last_comp, bootcpu,
     ts_size, st_size) = struct.unpack_from('>IIIIIIIIII', d, off)
    assert magic == 0xd00dfeed, hex(magic)
    print('=== DTB @%d total=%d ver=%d struct=%dB@%d strings=%dB@%d'
          % (off, total, version, st_size, ofs, ts_size, name_off))
    p = off + ofs
    end = off + ofs + st_size
    sbase = off + name_off
    path = []

    def cstr_at(a):
        e = d.index(b'\x00', a)
        return d[a:e].decode('latin1')

    while p < end:
        tok = struct.unpack_from('>I', d, p)[0]
        p += 4
        if tok == FDT_NOP:
            continue
        if tok == FDT_BEGIN_NODE:
            nm = cstr_at(p)
            p += len(nm) + 1
            p += (-p) % 4
            path.append(nm)
            if len(path) <= maxdepth:
                print('  ' * (len(path) - 1) + '{}/'.format(nm if nm else ''))
        elif tok == FDT_END_NODE:
            if path:
                path.pop()
        elif tok == FDT_PROP:
            ln = struct.unpack_from('>I', d, p)[0]
            p += 4
            nmoff = struct.unpack_from('>I', d, p)[0]
            p += 4
            nm = cstr_at(sbase + nmoff)
            val = d[p:p + ln]
            p += ln + ((-ln) % 4)
            if len(path) <= maxdepth:
                if all(32 <= c < 127 or c in (9, 10, 13) for c in val.rstrip(b'\x00')) and val.strip(b'\x00'):
                    shown = '"%s"' % val.rstrip(b'\x00').decode('latin1')
                else:
                    shown = '<%s>' % val.hex()
                print('  ' * len(path) + ('%s = %s' % (nm, shown)))
        elif tok == FDT_END:
            break
        else:
            print('unknown token %d at %d' % (tok, p - 4))
            break
    print()


dump(int(sys.argv[1]) if len(sys.argv) > 1 else 988)
