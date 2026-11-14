"""Reject the recurring 10 ms dropout reproduced in the release executable."""
import json
import os
import wave
from pathlib import Path
import numpy as np

root = Path(os.environ.get('TEST_RESULTS', '/results'))
metrics = json.loads((root/'summary.json').read_text())
assert len(metrics) == 7, 'Expected the complete seven-case forward matrix'
for m in metrics:
    with wave.open(str(root/m['case']/'aligned-output.wav')) as w:
        assert w.getframerate() == 8000
        y = np.frombuffer(w.readframes(w.getnframes()), '<i2').astype(float)
    # Middle of the continuous 1 kHz tone, away from codec startup/transitions.
    tone = y[12000:20000]
    assert len(tone) == 8000, 'Truncated tone capture'
    rms = np.sqrt(np.convolve(tone*tone, np.ones(80)/80, 'valid'))
    assert rms.max() > 1000, f"{m['case']}: missing test tone"
    ratio = float(rms.min()/rms.max())
    assert ratio > .5, f"{m['case']}: periodic audio dropout, RMS ratio={ratio:.4f}"
    assert m['sequence_gaps'] == 0, f"{m['case']}: RTP sequence gaps"
    assert m['clipped_samples'] == 0, f"{m['case']}: clipped output"
    assert not m['ffmpeg_decoder_errors'], f"{m['case']}: decoder errors"
    if m['carrier_codec'] == 'PCMA':
        assert m['segments']['tone_1000_hz']['correlation'] > .99, m['case']
    else:
        assert set(m['amr_frame_types']) == {'7'}, m['case']
        assert m['rtp_payload_lengths'] == [33], m['case']
    print(f"PASS {m['case']}: 10ms tone RMS min/max={ratio:.3f}")
