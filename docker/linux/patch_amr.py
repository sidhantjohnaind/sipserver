from pathlib import Path
p = Path('pjproject-2.15.1/pjmedia/src/pjmedia-codec/opencore_amr.c')
s = p.read_text()
for old, new in [
    ('PJ_FALSE,       /* octet align      */', 'PJ_TRUE,        /* octet align      */'),
    ('5900            /* bitrate          */', '12200           /* bitrate          */'),
]:
    assert old in s, old
    s = s.replace(old, new)
p.write_text(s)
