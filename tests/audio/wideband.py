"""Wideband transport, high-band preservation, fallback, and negative control."""
import json
import os
import wave
from pathlib import Path
import numpy as np
import test_converter as harness

root = harness.ROOT

def read(path):
    with wave.open(str(path)) as w:
        assert w.getsampwidth() == 2 and w.getnchannels() == 1
        return w.getframerate(), np.frombuffer(w.readframes(w.getnframes()), '<i2').astype(float)

def measure(folder):
    m = json.loads((folder/'capture.json').read_text())
    rate, y = read(folder/'output.wav')
    reference_rate, x = read(folder/'g711_reference.wav')
    # The decoded source fixture itself must contain the high-band component.
    reference = x[int(3.3*reference_rate):int(4.3*reference_rate)]
    reference_spectrum = np.abs(np.fft.rfft(reference*np.hanning(len(reference))))**2
    reference_freq = np.fft.rfftfreq(len(reference),1/reference_rate)
    reference_high = reference_spectrum[(reference_freq>=4500)&(reference_freq<=5500)].sum()
    reference_low = reference_spectrum[(reference_freq>=200)&(reference_freq<=1500)].sum()
    reference_band_ratio = float(reference_high/max(reference_low,1e-20))
    if reference_rate == 16000:
        assert reference_band_ratio > .001, 'Source fixture has no 5 kHz component'
    assert rate == m['output_pcm_rate']
    assert not m['ffmpeg_decoder_errors'] and not m['carrier_errors']
    assert m['sequence_gaps'] == 0
    assert m['captured_payload_types'] == [m['offered_carrier_payload_type']]
    assert m['rtp_timestamp_steps'] == [m['output_rtp_clock']//50]
    assert not np.any(np.abs(y) >= 32760), 'Clipped output'
    answer = (folder/'local_answer.sdp').read_text()
    offer = (folder/'upstream_offer.sdp').read_text()
    if m['local_codec'] == 'G722':
        assert 'G722/8000' in answer and 'G722/16000' not in answer
        assert m['input_pcm_rate'] == 16000 and m['input_rtp_clock'] == 8000
        assert m['input_payload_lengths'] == [160]
    if m['carrier_codec'] == 'AMR-WB':
        assert 'AMR-WB/16000' in offer
        assert set(m['amr_frame_types']) == {'2'}
        assert m['rtp_payload_lengths'] == [34]
    if m['carrier_codec'] == 'AMR':
        assert set(m['amr_frame_types']) == {'7'}
        assert m['rtp_payload_lengths'] == [33]

    # Find tone onset rather than imposing a particular jitter-buffer latency.
    window = rate//100
    rms = np.sqrt(np.convolve(y*y, np.ones(window)/window, 'valid'))
    audible = np.flatnonzero(rms > 1200)
    assert len(audible), 'Missing reference tone'
    onset = int(audible[0])
    tone = y[onset+rate//2:onset+3*rate//2]
    tone_rms = np.sqrt(np.convolve(tone*tone, np.ones(window)/window, 'valid'))
    ratio = float(tone_rms.min()/tone_rms.max())
    reference_window = reference_rate//100
    reference_tone = x[int(1.5*reference_rate):int(2.5*reference_rate)]
    reference_rms = np.sqrt(np.convolve(reference_tone*reference_tone,
                                       np.ones(reference_window)/reference_window,'valid'))
    reference_continuity = float(reference_rms.min()/reference_rms.max())
    # Re-encoding AMR-WB modulates a pure sine even without transport loss.
    # Reject near-silent blocks relative to the decoded source's own envelope.
    assert ratio > .25*reference_continuity, 'Near-silent blocks in the reference tone'

    # The multitone begins two seconds after tone onset: 300, 700, 5000 Hz.
    segment = y[onset+int(2.3*rate):onset+int(3.3*rate)]
    assert len(segment) == rate
    spectrum = np.abs(np.fft.rfft(segment*np.hanning(len(segment))))**2
    freq = np.fft.rfftfreq(len(segment), 1/rate)
    low = float(spectrum[(freq >= 200) & (freq <= 1500)].sum())
    high = float(spectrum[(freq >= 4500) & (freq <= 5500)].sum())
    band_ratio = high/max(low, 1e-20)
    result = dict(case=m['case'], input_pcm_rate=reference_rate,
                  output_pcm_rate=rate, tone_rms_min_max=ratio,
                  high_low_band_ratio=band_ratio,
                  reference_high_low_band_ratio=reference_band_ratio,
                  high_band_retention=(band_ratio/reference_band_ratio if reference_rate==16000 else None),
                  high_low_band_db=float(10*np.log10(max(band_ratio,1e-20))),
                  rtp_timestamp_steps=m['rtp_timestamp_steps'],
                  sequence_gaps=m['sequence_gaps'])
    (folder/'wideband-metrics.json').write_text(json.dumps(result,indent=2))
    return result

def run():
    original_root = root
    results = []
    for local, carrier in [('G722','G722'), ('G722','AMR-WB'),
                           ('AMR-WB','G722'), ('AMR-WB','AMR-WB'),
                           ('G722','AMR'), ('PCMA','AMR-WB')]:
        os.environ['ENABLE_WIDEBAND'] = '1'
        harness.run_case(local, carrier)
        folder = original_root/(local.lower()+'_to_'+carrier.lower())
        assert 'Conference media clock: 16000 Hz' in (folder/'bridge.log').read_text()
        result = measure(folder)
        if carrier != 'AMR' and local != 'PCMA':
            assert result['high_band_retention'] > .1, result
        elif carrier == 'AMR':
            assert result['output_pcm_rate'] == 8000, result
        else:
            assert result['input_pcm_rate'] == 8000 and result['output_pcm_rate'] == 16000, result
        results.append(result)
        print('PASS',json.dumps(result),flush=True)

    # Same AMR-WB wire format, but the legacy 8 kHz conference should lose 5 kHz.
    negative_root = original_root/'negative-8khz-clock'
    negative_root.mkdir(exist_ok=True)
    for name in ('cert.pem','key.pem'):
        (negative_root/name).write_bytes((original_root/name).read_bytes())
    try:
        harness.ROOT = negative_root
        os.environ['ENABLE_WIDEBAND'] = '0'
        harness.run_case('AMR-WB','AMR-WB')
        folder = negative_root/'amr-wb_to_amr-wb'
        assert 'Conference media clock: 8000 Hz' in (folder/'bridge.log').read_text()
        negative = measure(folder)
    finally:
        harness.ROOT = original_root
        os.environ['ENABLE_WIDEBAND'] = '1'
    positive = next(r for r in results if r['case']=='amr-wb_to_amr-wb')
    assert negative['high_band_retention'] < .01, negative
    assert positive['high_low_band_db']-negative['high_low_band_db'] > 20, (positive,negative)
    report = dict(positive_cases=results,negative_control=negative,
                  high_band_improvement_db=positive['high_low_band_db']-negative['high_low_band_db'])
    (original_root/'wideband-summary.json').write_text(json.dumps(report,indent=2))
    print('PASS 8 kHz negative control:',json.dumps(negative),flush=True)

if __name__ == '__main__':
    run()
