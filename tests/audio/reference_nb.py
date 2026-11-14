"""AMR-NB tone envelope after direct conference-rate conversion, without SIP."""
import ctypes as c
import json
import subprocess
import wave
import numpy as np

def envelope_ratio(folder):
    with wave.open(str(folder/'g711_reference.wav')) as w:
        assert w.getframerate() == 8000 and w.getsampwidth() == 2
        pcm = w.readframes(w.getnframes())
    source = folder/'reference-input.pcm'
    converted = folder/'reference-roundtrip.pcm'
    source.write_bytes(pcm)
    subprocess.run(['reference-resample',str(source),str(converted)],
                   check=True,capture_output=True)
    pcm = converted.read_bytes()
    lib = c.CDLL('libopencore-amrnb.so.0')
    lib.Encoder_Interface_init.argtypes = [c.c_int]
    lib.Encoder_Interface_init.restype = c.c_void_p
    lib.Encoder_Interface_Encode.argtypes = [c.c_void_p,c.c_int,c.POINTER(c.c_short),
                                           c.POINTER(c.c_ubyte),c.c_int]
    lib.Encoder_Interface_Encode.restype = c.c_int
    lib.Encoder_Interface_exit.argtypes = [c.c_void_p]
    state = lib.Encoder_Interface_init(0)
    assert state
    data = bytearray(b'#!AMR\n')
    try:
        for offset in range(0,len(pcm),320):
            samples = (c.c_short*160).from_buffer_copy(pcm[offset:offset+320])
            encoded = (c.c_ubyte*64)()
            size = lib.Encoder_Interface_Encode(state,7,samples,encoded,0)
            assert size == 32
            data.extend(bytes(encoded[:size]))
    finally:
        lib.Encoder_Interface_exit(state)
    path = folder/'reference-resampled.amr'
    path.write_bytes(data)
    decoded = path.with_suffix('.wav')
    subprocess.run(['ffmpeg','-v','error','-y','-i',str(path),str(decoded)],check=True)
    with wave.open(str(decoded)) as w:
        y = np.frombuffer(w.readframes(w.getnframes()),'<i2').astype(float)
    tone = y[12000:20000]
    rms = np.sqrt(np.convolve(tone*tone,np.ones(80)/80,'valid'))
    ratio = float(rms.min()/rms.max())
    (folder/'reference-envelope.json').write_text(json.dumps(dict(tone_rms_min_max=ratio)))
    return ratio
